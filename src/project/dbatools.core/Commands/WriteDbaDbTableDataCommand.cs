#nullable enable

using System;
using System.Collections;
using System.Data;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// High-speed bulk insert via SqlBulkCopy. Port of public/Write-DbaDbTableData.ps1 (W1-043).
/// The begin block resolves the connection context (reusing a piped-in non-pooled Server or
/// connecting non-pooled through the REAL Connect-DbaInstance hop), defaults -Database from
/// the context or a SELECT DB_NAME() ride on the compiled Invoke-DbaQuery, parses the FQTN
/// through the still-PS private Get-ObjectNameParts, probes table existence with the
/// function's ExecuteScalar try/catch, sums the SqlBulkCopyOptions, and builds the bulk-copy
/// object with the ctor fallback and the wrap-adjusted SqlRowsCopied progress handler
/// (Get-AdjustedTotalRowsCopied absorbed like Import-DbaCsv). Non-table pipeline input rides
/// a steppable pipeline over the REAL ConvertTo-DbaDataTable with the function's four
/// config-driven splat values - NOTE: the function resolved that command with a
/// [CommandTypes]::Function-typed GetCommand, which the W1-002 flip broke (every input path
/// died "Failed to initialize " - live regression 2026-07-11..13); the port resolves the
/// real command and RESTORES the intended behavior. The three write scenarios (single
/// table-typed object, enumerated table-typed objects, converted property bags at End)
/// share NewTable/BulkCopyTable translations that preserve the nested Stop-Function
/// EnableException interplay (a non-EE create failure still marks tableExists true - the
/// function's quirk). Gate map (W1-043 re-open fix): the bulk-copy write gate lives in
/// NESTED Invoke-BulkCopy with no SupportsShouldProcess, so it honours -WhatIf but never
/// confirm-prompts - ported as a WhatIf-only gate (see Helpers BulkCopy); the schema/table
/// creation gates live in nested New-Table WITH SupportsShouldProcess and the truncate gate
/// on the function itself - both prompt normally. The REMAINING accepted deviation is
/// narrower than this note once claimed: the function's `if (-not $Truncate)
/// { $ConfirmPreference = "None" }` mutes the truncate/create gates' prompts on
/// non-Truncate runs - a function-local preference write with no compiled equivalent;
/// deviation only for callers at $ConfirmPreference Low AND not passing -Truncate, on the
/// New-Table gates only. Positions: Table 3, Schema 4
/// (the function's explicit pins; nothing else positional).
/// Surface pinned by migration/baselines/Write-DbaDbTableData.json.
/// </summary>
[Cmdlet(VerbsCommunications.Write, "DbaDbTableData", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed partial class WriteDbaDbTableDataCommand : DbaBaseCmdlet
{
    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    [Parameter(Mandatory = true)]
    [ValidateNotNull]
    public DbaInstanceParameter SqlInstance { get; set; } = null!;

    [Parameter]
    [ValidateNotNull]
    public PSCredential? SqlCredential { get; set; }

    [Parameter]
    public object? Database { get; set; }

    [Parameter(Mandatory = true, ValueFromPipeline = true)]
    [Alias("DataTable")]
    [ValidateNotNull]
    public object InputObject { get; set; } = null!;

    [Parameter(Position = 3, Mandatory = true)]
    [ValidateNotNullOrEmpty]
    [PsStringCast]
    public string Table { get; set; } = null!;

    [Parameter(Position = 4)]
    [ValidateNotNullOrEmpty]
    public string Schema { get; set; } = "dbo";

    [Parameter]
    [PsIntCast]
    [ValidateNotNull]
    public int BatchSize { get; set; } = 50000;

    [Parameter]
    [PsIntCast]
    [ValidateNotNull]
    public int NotifyAfter { get; set; } = 5000;

    [Parameter]
    public SwitchParameter AutoCreateTable { get; set; }

    [Parameter]
    public SwitchParameter NoTableLock { get; set; }

    [Parameter]
    public SwitchParameter CheckConstraints { get; set; }

    [Parameter]
    public SwitchParameter FireTriggers { get; set; }

    [Parameter]
    public SwitchParameter KeepIdentity { get; set; }

    [Parameter]
    public SwitchParameter KeepNulls { get; set; }

    [Parameter]
    public SwitchParameter Truncate { get; set; }

    [Parameter]
    [PsIntCast]
    [ValidateNotNull]
    public int BulkCopyTimeOut { get; set; } = 5000;

    [Parameter]
    public Hashtable? ColumnMap { get; set; }

    [Parameter]
    public SwitchParameter UseDynamicStringLength { get; set; }

    private object? _context;
    private bool _startedWithANonPooledConnection;
    private string? _databaseName;
    private string? _originalDatabaseName;
    private string? _schemaName;
    private string? _tableName;
    private string _fqtn = "";
    private bool _usingGlobalTempTable;
    private bool _tableExists;
    private Server? _server;
    private SqlBulkCopy? _bulkCopy;
    private SteppablePipeline? _steppablePipeline;
    private long _prevRowsCopied;
    private long _totalRowsCopied;
    private long _currentRowCount;
    private System.Diagnostics.Stopwatch? _elapsed;

    protected override void ProcessRecord()
    {
        // PS: if (Test-FunctionInterrupt) { return }
        if (Interrupted)
            return;

        // PS: $InputObject.GetType() - the PS member binder reads through the PSObject wrapper.
        object input = PsAssignment.Unwrap(InputObject)!;
        Type inputType = input.GetType();

        object inputData;
        if (inputType == typeof(DataSet))
        {
            inputData = ((DataSet)input).Tables;
            inputType = typeof(DataTable[]);
        }
        else
        {
            inputData = input;
        }

        #region Scenario 1: Single valid table
        // PS: $inputType -in $validTypes - Type -eq Type is EXACT equality.
        if (IsValidTableType(inputType))
        {
            if (!_tableExists)
            {
                try
                {
                    NewTable(input);
                    _tableExists = true;
                }
                catch (PipelineStoppedException) { throw; }
                catch (Exception ex)
                {
                    StopFunction("Failed to create table " + _fqtn, target: SqlInstance, errorRecord: ToCaughtRecord(ex));
                    return;
                }
            }

            try { BulkCopyWrite(input); }
            catch (PipelineStoppedException) { throw; }
            catch (Exception ex)
            {
                StopFunction("Failed to bulk import to " + _fqtn, target: SqlInstance, errorRecord: ToCaughtRecord(ex));
            }
            return;
        }
        #endregion Scenario 1: Single valid table

        IEnumerable enumerable = LanguagePrimitives.GetEnumerable(inputData) ?? new object[] { inputData };
        foreach (object? rawObject in enumerable)
        {
            object? item = PsAssignment.Unwrap(rawObject);

            #region Scenario 2: Multiple valid tables
            if (item is not null && IsValidTableType(item.GetType()))
            {
                if (!_tableExists)
                {
                    try
                    {
                        NewTable(item);
                        _tableExists = true;
                    }
                    catch (PipelineStoppedException) { throw; }
                    catch (Exception ex)
                    {
                        StopFunction("Failed to create table " + _fqtn, target: SqlInstance, errorRecord: ToCaughtRecord(ex));
                        return;
                    }
                }

                try { BulkCopyWrite(item); }
                catch (PipelineStoppedException) { throw; }
                catch (Exception ex)
                {
                    // PS: Stop-Function ... -Continue (function-local foreach continue)
                    StopFunction("Failed to bulk import to " + _fqtn, target: SqlInstance, errorRecord: ToCaughtRecord(ex), continueLoop: true);
                }
                continue;
            }
            #endregion Scenario 2: Multiple valid tables

            #region Scenario 3: Invalid data types
            if (item is null)
            {
                // PS: the if-condition's $object.GetType() dies method-on-null - a
                // statement-terminating error that skips the WHOLE if/else (the null never
                // reaches the steppable) and continues with the next element (codex r1 F4,
                // lab-proven).
                WriteError(new ErrorRecord(new PSInvalidOperationException("You cannot call a method on a null-valued expression."), "InvokeMethodOnNull", ErrorCategory.InvalidOperation, null));
                continue;
            }
            // PS: $null = $steppablePipeline.Process($object)
            using (NestedCommand.ShieldDefaultParameterValues(this))
            {
                _steppablePipeline!.Process(rawObject);
            }
            #endregion Scenario 3: Invalid data types
        }
    }

    protected override void EndProcessing()
    {
        // PS: if (Test-FunctionInterrupt) { return }
        if (Interrupted)
            return;

        #region ConvertTo-DbaDataTable wrapper
        Array dataTable;
        using (NestedCommand.ShieldDefaultParameterValues(this))
        {
            dataTable = _steppablePipeline!.End();
        }

        // Handle both single DataTable and array of DataTables
        object? tableToUse = null;
        if (LanguagePrimitives.IsTrue(dataTable))
        {
            if (dataTable.Length > 0)
                tableToUse = PsAssignment.Unwrap(dataTable.GetValue(0));
        }

        if (tableToUse is DataTable table && table.Rows.Count > 0)
        {
            if (!_tableExists)
            {
                try
                {
                    NewTable(table);
                    _tableExists = true;
                }
                catch (PipelineStoppedException) { throw; }
                catch (Exception ex)
                {
                    StopFunction("Failed to create table " + _fqtn, target: SqlInstance, errorRecord: ToCaughtRecord(ex));
                    return;
                }
            }

            try { BulkCopyWrite(table); }
            catch (PipelineStoppedException) { throw; }
            catch (Exception ex)
            {
                StopFunction("Failed to bulk import to " + _fqtn, target: SqlInstance, errorRecord: ToCaughtRecord(ex));
            }
        }
        #endregion ConvertTo-DbaDataTable wrapper

        if (_bulkCopy is not null)
        {
            _bulkCopy.Close();
            ((IDisposable)_bulkCopy).Dispose();
        }

        if (!(_startedWithANonPooledConnection || _usingGlobalTempTable))
        {
            // Close non-pooled connection as this is not done automatically. If it is a reused Server SMO, connection will be opened again automatically on next request.
            if (_server is not null)
            {
                object? boundWhatIf = MyInvocation.BoundParameters.TryGetValue("WhatIf", out object? whatIfValue) ? whatIfValue : null;
                object? boundConfirm = MyInvocation.BoundParameters.TryGetValue("Confirm", out object? confirmValue) ? confirmValue : null;
                foreach (PSObject item in NestedCommand.InvokeScoped(this, DisconnectScript, _server, boundWhatIf, boundConfirm))
                    WriteObject(item);
            }
        }
        else if (!PsString.Eq(_originalDatabaseName, _databaseName))
        {
            // if a temptable was created, it sets the open connection's database to tempdb indefinitely. We want to get back to the original database context at the start of this command.
            WriteMessage(MessageLevel.Verbose, "The current database has changed from the original database. switching back to the original database.");
            InvokePsMethod(_context, "ExecuteNonQuery", "USE [" + _originalDatabaseName + "]");
        }
    }

    /// <summary>PS: $validTypes = @([System.Data.DataSet], [System.Data.DataTable],
    /// [System.Data.DataRow], [System.Data.DataRow[]]) - Type equality is exact.</summary>
    private static bool IsValidTableType(Type type)
    {
        return type == typeof(DataSet) || type == typeof(DataTable) || type == typeof(DataRow) || type == typeof(DataRow[]);
    }
}
