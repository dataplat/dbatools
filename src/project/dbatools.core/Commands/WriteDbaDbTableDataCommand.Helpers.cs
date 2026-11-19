#nullable enable

using System;
using System.Collections;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Message;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

public sealed partial class WriteDbaDbTableDataCommand
{
    protected override void BeginProcessing()
    {
        // Null variable to make sure upper-scope variables don't interfere later
        _steppablePipeline = null;

        // PS: $context = if ($SqlInstance.InputObject.ConnectionContext) { ... } else { $SqlInstance.ConnectionContext }
        object? inputObjectContext = PsProperty.Get(PsProperty.Get(SqlInstance, "InputObject"), "ConnectionContext");
        _context = LanguagePrimitives.IsTrue(inputObjectContext) ? inputObjectContext : PsProperty.Get(SqlInstance, "ConnectionContext");
        _startedWithANonPooledConnection = LanguagePrimitives.IsTrue(PsProperty.Get(_context, "NonPooledConnection"));

        // PS: if (-not $PSBoundParameters.Database) - VALUE truthiness, not key presence;
        // the branch then MUTATES $PSBoundParameters so the later Test-Bound reads true.
        bool databaseKeyPresent = MyInvocation.BoundParameters.ContainsKey("Database");
        object? effectiveDatabase = PsAssignment.Unwrap(Database);
        if (!LanguagePrimitives.IsTrue(effectiveDatabase))
        {
            object? contextDbName = PsProperty.Get(_context, "DatabaseName");
            if (LanguagePrimitives.IsTrue(contextDbName))
            {
                effectiveDatabase = contextDbName;
                _databaseName = PsToText(contextDbName);
            }
            else
            {
                // PS: $dbname = (Invoke-DbaQuery -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Query "SELECT DB_NAME() AS dbname").dbname
                object? dbname = null;
                foreach (PSObject item in NestedCommand.InvokeScoped(this, DbNameQueryScript, SqlInstance, SqlCredential))
                    dbname = PsProperty.Get(item, "dbname");
                effectiveDatabase = dbname;
                _databaseName = dbname is null ? null : PsToText(dbname);
            }
            databaseKeyPresent = true;
        }

        // PS: if (-not $Truncate) { $ConfirmPreference = "None" } - UNREPRESENTABLE for a
        // compiled cmdlet (no function-local preference variable); ConfirmImpact is Low, so
        // the deviation is reachable only for callers running $ConfirmPreference = 'Low'.

        #region Resolve Full Qualified Table Name
        PSObject? fqtnObj = null;
        foreach (PSObject item in NestedCommand.InvokeScoped(this, GetObjectNamePartsScript, Table))
            fqtnObj = item;

        if (!LanguagePrimitives.IsTrue(PsProperty.Get(fqtnObj, "Parsed")))
        {
            StopFunction("Unable to parse " + PsToText(PsProperty.Get(fqtnObj, "InputValue")) + " as a valid tablename.");
            return;
        }

        object? fqtnDatabase = PsProperty.Get(fqtnObj, "Database");
        if (fqtnDatabase is null && effectiveDatabase is null)
        {
            StopFunction("You must specify a database or fully qualified table name.");
            return;
        }

        // PS: if (Test-Bound -ParameterName Database) - always true after the defaulting
        // mutation above; the else branch is preserved for the never-bound-never-defaulted
        // shape (unreachable in practice).
        if (databaseKeyPresent)
        {
            if (fqtnDatabase is null)
            {
                _databaseName = PsToText(effectiveDatabase);
            }
            else if (PsString.Eq(PsToText(fqtnDatabase), PsToText(effectiveDatabase)))
            {
                _databaseName = PsToText(effectiveDatabase);
            }
            else
            {
                StopFunction("The database parameter " + PsToText(effectiveDatabase) + " differs from value from the fully qualified table name " + PsToText(fqtnDatabase) + ".");
                return;
            }
        }
        else
        {
            _databaseName = fqtnDatabase is null ? null : PsToText(fqtnDatabase);
        }

        object? fqtnSchema = PsProperty.Get(fqtnObj, "Schema");
        _schemaName = LanguagePrimitives.IsTrue(fqtnSchema) ? PsToText(fqtnSchema) : Schema;

        _originalDatabaseName = _databaseName;
        _tableName = PsToText(PsProperty.Get(fqtnObj, "Name"));

        _usingGlobalTempTable = false;
        if (_tableName.StartsWith("#", StringComparison.Ordinal))
        {
            WriteMessage(MessageLevel.Verbose, "The table " + _tableName + " should be in tempdb.dbo so we ignore input database and schema.");
            _databaseName = "tempdb";
            _schemaName = "dbo";
            if (_tableName.StartsWith("##", StringComparison.Ordinal))
            {
                // do not disconnect the SqlInstance if using a global temp table.
                _usingGlobalTempTable = true;
            }
            else if (!_startedWithANonPooledConnection)
            {
                // if using a session temp table, you must also give an already created connection to be able to use it in the same session it was created in.
                WriteMessage(MessageLevel.Warning, "The temp table being created will not be usable after this command completes. Either use a global temp table, like '#" + _tableName + "', or pass a NonPooled SqlConnection.");
            }
        }
        #endregion Resolve Full Qualified Table Name

        #region Connect to server
        try
        {
            if (_startedWithANonPooledConnection)
            {
                if (!LanguagePrimitives.IsTrue(PsProperty.Get(_context, "IsOpen")))
                    InvokePsMethod(PsProperty.Get(_context, "SqlConnectionObject"), "Open");
                _server = PsAssignment.Unwrap(PsProperty.Get(SqlInstance, "InputObject")) as Server;
            }
            else
            {
                ErrorRecord? connectError = null;
                foreach (PSObject item in NestedCommand.InvokeScoped(this, ConnectScript, SqlInstance, SqlCredential, _databaseName))
                {
                    ErrorRecord? caught = ExtractCaughtError(item);
                    if (caught is not null)
                        connectError = caught;
                    else
                        _server = PsAssignment.Unwrap(item) as Server;
                }
                if (connectError is not null)
                    throw new CaughtRecordException(connectError);
            }
        }
        catch (PipelineStoppedException) { throw; }
        catch (Exception ex)
        {
            StopFunction("Error occurred while establishing connection to " + PSObject.AsPSObject(SqlInstance).ToString(),
                target: SqlInstance, errorRecord: ToCaughtRecord(ex), category: ErrorCategory.ConnectionError);
            return;
        }
        #endregion Connect to server

        #region Quote Full Qualified Table Name
        StringBuilder quotedFQTN = new StringBuilder();
        // PS: $server.ServerType -ne 'SqlAzureDatabase' (enum vs string, case-insensitive)
        if (!PsString.Eq(PsToText(_server?.ServerType), "SqlAzureDatabase"))
        {
            quotedFQTN.Append('[');
            quotedFQTN.Append(_databaseName!.Contains("]") ? _databaseName.Replace("]", "]]") : _databaseName);
            quotedFQTN.Append("].");
        }

        quotedFQTN.Append('[');
        quotedFQTN.Append(_schemaName!.Contains("]") ? _schemaName.Replace("]", "]]") : _schemaName);
        quotedFQTN.Append("].");

        quotedFQTN.Append('[');
        quotedFQTN.Append(_tableName.Contains("]") ? _tableName.Replace("]", "]]") : _tableName);
        quotedFQTN.Append(']');

        _fqtn = quotedFQTN.ToString();
        WriteMessage(MessageLevel.SomewhatVerbose, "FQTN processed: " + _fqtn);
        #endregion Quote Full Qualified Table Name

        #region Test if table exists
        if (_tableName.StartsWith("#", StringComparison.Ordinal))
        {
            try
            {
                WriteMessage(MessageLevel.Verbose, "The table " + _tableName + " should be in tempdb and we try to find it.");
                _server!.ConnectionContext.ExecuteScalar("SELECT TOP(1) 1 FROM [" + _tableName + "]");
                _tableExists = true;
            }
            catch
            {
                _tableExists = false;
            }
        }
        else
        {
            // We don't use SMO here because it does not work for Azure SQL Database connected with AccessToken.
            try
            {
                _server!.ConnectionContext.ExecuteScalar("SELECT TOP(1) 1 FROM " + _fqtn);
                _tableExists = true;
            }
            catch
            {
                _tableExists = false;
            }
        }

        if (!_tableExists && !AutoCreateTable.ToBool())
        {
            StopFunction("Table does not exist and automatic creation of the table has not been selected. Specify the '-AutoCreateTable'-parameter to generate a suitable table.");
            return;
        }
        #endregion Test if table exists

        int bulkCopyOptions = 0;
        if (CheckConstraints.ToBool())
            bulkCopyOptions += (int)SqlBulkCopyOptions.CheckConstraints;
        if (FireTriggers.ToBool())
            bulkCopyOptions += (int)SqlBulkCopyOptions.FireTriggers;
        if (KeepIdentity.ToBool())
            bulkCopyOptions += (int)SqlBulkCopyOptions.KeepIdentity;
        if (KeepNulls.ToBool())
            bulkCopyOptions += (int)SqlBulkCopyOptions.KeepNulls;

        // Handle TableLock separately since it is enabled by default unless -NoTableLock is specified
        if (!NoTableLock.ToBool())
            bulkCopyOptions += (int)SqlBulkCopyOptions.TableLock;

        // Always include Default option
        bulkCopyOptions += (int)SqlBulkCopyOptions.Default;

        if (Truncate.ToBool())
        {
            if (ShouldProcess(PSObject.AsPSObject(SqlInstance).ToString(), "Truncating " + _fqtn))
            {
                try
                {
                    WriteMessage(MessageLevel.Verbose, "Truncating " + _fqtn + ".");
                    // PS: $db.Query($sql) - the dbatools ETS ScriptMethod over ExecuteWithResults.
                    DatabaseQuery(_server!.Databases[_databaseName], "TRUNCATE TABLE " + _fqtn);
                }
                catch (Exception ex)
                {
                    WriteMessage(MessageLevel.Warning, "Could not truncate " + _fqtn + ". Table may not exist or may have key constraints.", exception: WrapAsMethodInvocation(ex, "Query", 1));
                }
            }
        }

        WriteMessage(MessageLevel.Verbose, "Creating SqlBulkCopy object");
        try
        {
            _bulkCopy = new SqlBulkCopy(_server!.ConnectionContext.SqlConnectionObject, (SqlBulkCopyOptions)bulkCopyOptions, null);
        }
        catch
        {
            _bulkCopy = new SqlBulkCopy(_server!.ConnectionContext.ConnectionString, (SqlBulkCopyOptions)bulkCopyOptions);
        }

        _bulkCopy.DestinationTableName = _fqtn;
        _bulkCopy.BatchSize = BatchSize;
        _bulkCopy.NotifyAfter = NotifyAfter;
        // PS: $bulkCopy.BulkCopyTimeOut - the case-insensitive member binder lands on BulkCopyTimeout.
        _bulkCopy.BulkCopyTimeout = BulkCopyTimeOut;

        // The legacy bulk copy library uses a 4 byte integer to track the RowsCopied, so the only option is to use
        // integer wrap so that copy operations of row counts greater than [int32]::MaxValue will report accurate numbers.
        // See https://github.com/dataplat/dbatools/issues/6927 for more details
        _prevRowsCopied = 0;
        _totalRowsCopied = 0;

        _elapsed = System.Diagnostics.Stopwatch.StartNew();
        // Add RowCount output
        _bulkCopy.SqlRowsCopied += (sender, args) =>
        {
            _totalRowsCopied += GetAdjustedTotalRowsCopied(args.RowsCopied, _prevRowsCopied);

            string tstamp = DateTime.Now.ToString("yyyyMMddHHmmss", CultureInfo.CurrentCulture);
            WriteMessage(MessageLevel.Verbose, "[" + tstamp + "] The bulk copy library reported RowsCopied = " + args.RowsCopied + ". The previous RowsCopied = " + _prevRowsCopied + ". The adjusted total rows copied = " + _totalRowsCopied);

            // PS: [int](($script:totalRowsCopied / $rowCount) * 100) - PS [int] cast rounds to even.
            int percent = (int)LanguagePrimitives.ConvertTo(((double)_totalRowsCopied / _currentRowCount) * 100, typeof(int), CultureInfo.InvariantCulture);
            double timeTaken = Math.Round(_elapsed!.Elapsed.TotalSeconds, 1);
            ProgressRecord progress = new ProgressRecord(1, "Inserting " + _currentRowCount + " rows.", string.Format("Progress: {0} rows ({1}%) in {2} seconds", _totalRowsCopied, percent, timeTaken));
            progress.PercentComplete = percent;
            WriteProgress(progress);

            // save the previous count of rows copied to be used on the next event notification
            _prevRowsCopied = args.RowsCopied;
        };

        #region ConvertTo-DbaDataTable wrapper
        // PS: the function resolved ConvertTo-DbaDataTable with a [CommandTypes]::Function-typed
        // GetCommand - broken since the W1-002 flip (null command -> Begin threw -> every input
        // path no-oped behind "Failed to initialize "). The port resolves the REAL command.
        try
        {
            Hashtable splatCDDT = new Hashtable();
            foreach (PSObject item in NestedCommand.InvokeScoped(this, ConfigBagScript))
            {
                splatCDDT["TimeSpanType"] = PsProperty.Get(item, "TimeSpanType");
                splatCDDT["SizeType"] = PsProperty.Get(item, "SizeType");
                splatCDDT["IgnoreNull"] = PsProperty.Get(item, "IgnoreNull");
                splatCDDT["Raw"] = PsProperty.Get(item, "Raw");
            }
            ScriptBlock scriptCmd = ScriptBlock.Create("param($__parameters) & ConvertTo-DbaDataTable @__parameters");
            _steppablePipeline = scriptCmd.GetSteppablePipeline(CommandOrigin.Internal, new object[] { splatCDDT });
            using (NestedCommand.ShieldDefaultParameterValues(this))
            {
                _steppablePipeline.Begin(true);
            }
        }
        catch (PipelineStoppedException) { throw; }
        catch
        {
            StopFunction("Failed to initialize ");
        }
        #endregion ConvertTo-DbaDataTable wrapper
    }

    /// <summary>The absorbed Invoke-BulkCopy helper.</summary>
    private void BulkCopyWrite(object dataTable)
    {
        WriteMessage(MessageLevel.Verbose, "Importing in bulk to " + _fqtn);

        // PS: $rowCount = $DataTable.Rows.Count (member-path read; DataRow[] reads empty -> 0)
        long rowCount = 0;
        if (dataTable is DataTable table)
            rowCount = table.Rows.Count;
        if (rowCount == 0)
            rowCount = 1;
        _currentRowCount = rowCount;

        // PS: this gate lives in NESTED Invoke-BulkCopy, whose [CmdletBinding()] has NO
        // SupportsShouldProcess - its $Pscmdlet.ShouldProcess honours -WhatIf (message +
        // skip) but can NEVER confirm-prompt, whatever ConfirmPreference is (B's probe:
        // source prompts=0 at ConfirmPreference=Low; DEF-008 W1-043 re-open - a port
        // prompt here after a confirmed -Truncate leaves the table truncated-and-empty
        // on No, where the source repopulates it). WhatIf-only gate: call ShouldProcess
        // only when WhatIf is live (it never prompts under WhatIf), else proceed
        // unprompted exactly like the nested function.
        bool bulkCopyWhatIf = MyInvocation.BoundParameters.TryGetValue("WhatIf", out object? boundWhatIf)
            ? LanguagePrimitives.IsTrue(boundWhatIf)
            : LanguagePrimitives.IsTrue(GetVariableValue("WhatIfPreference"));
        if (!bulkCopyWhatIf || ShouldProcess(PSObject.AsPSObject(SqlInstance).ToString(), "Writing " + rowCount + " rows to " + _fqtn))
        {
            if (LanguagePrimitives.IsTrue(ColumnMap))
            {
                // PS: foreach ($columnname in $ColumnMap) - a Hashtable enumerates as ITSELF once.
                foreach (object? key in ColumnMap!.Keys)
                {
                    // PS method binder: int-typed keys/values land the ordinal overload,
                    // everything else string-converts (the W1-018 ColumnMap class).
                    AddColumnMapping(key, ColumnMap[key!]);
                }
            }
            else if (dataTable is DataTable mapTable)
            {
                foreach (DataColumn column in mapTable.Columns)
                    _bulkCopy!.ColumnMappings.Add(column.ColumnName, column.ColumnName);
            }

            try
            {
                if (dataTable is DataTable writeTable)
                    _bulkCopy!.WriteToServer(writeTable);
                else if (PsAssignment.Unwrap(dataTable) is DataRow[] rows)
                    _bulkCopy!.WriteToServer(rows);
                else if (PsAssignment.Unwrap(dataTable) is DataRow row)
                    _bulkCopy!.WriteToServer(new[] { row });
                else if (PsAssignment.Unwrap(dataTable) is DataSet)
                    throw new PSInvalidOperationException("Cannot convert argument \"table\", with value: \"" + PsToText(dataTable) + "\", for \"WriteToServer\" to type \"System.Data.DataTable\"");
            }
            catch (Exception ex) when (ex is not PSInvalidOperationException and not PipelineStoppedException)
            {
                throw WrapAsMethodInvocation(ex, "WriteToServer", 1);
            }

            if (rowCount != 0)
            {
                ProgressRecord completed = new ProgressRecord(1, "Inserting " + rowCount + " rows", "Complete");
                completed.RecordType = ProgressRecordType.Completed;
                WriteProgress(completed);
            }
        }
    }

    /// <summary>PS ColumnMappings.Add binder parity (the W1-018 class): each Int32-typed
    /// operand independently lands its ordinal slot - the binder resolves ALL FOUR mixed
    /// overloads (codex r1 F3).</summary>
    private void AddColumnMapping(object? key, object? value)
    {
        object? rawKey = PsAssignment.Unwrap(key);
        object? rawValue = PsAssignment.Unwrap(value);
        if (rawKey is int sourceOrdinal && rawValue is int destinationOrdinal)
            _bulkCopy!.ColumnMappings.Add(sourceOrdinal, destinationOrdinal);
        else if (rawKey is int sourceOrdinalOnly)
            _bulkCopy!.ColumnMappings.Add(sourceOrdinalOnly, PsToText(rawValue));
        else if (rawValue is int destinationOrdinalOnly)
            _bulkCopy!.ColumnMappings.Add(PsToText(rawKey), destinationOrdinalOnly);
        else
            _bulkCopy!.ColumnMappings.Add(PsToText(rawKey), PsToText(rawValue));
    }

    /// <summary>The absorbed New-Table helper. Throws under -EnableException (the nested
    /// Stop-Function shape); warns and returns otherwise - the CALLER still marks
    /// tableExists true afterward (the function's quirk).</summary>
    private void NewTable(object dataTable)
    {
        WriteMessage(MessageLevel.Verbose, "Creating table for " + _fqtn);

        // Create schema if it doesn't exist (skip for temp tables)
        if (!_tableName!.StartsWith("#", StringComparison.Ordinal))
        {
            try
            {
                SmoDatabase database = _server!.Databases[_databaseName];
                database.Schemas.Refresh();
                Microsoft.SqlServer.Management.Smo.Schema? schemaExists = database.Schemas[_schemaName];
                if (schemaExists is null)
                {
                    WriteMessage(MessageLevel.Verbose, "Schema [" + _schemaName + "] does not exist in database [" + _databaseName + "]. Creating schema.");
                    string schemaSql = "CREATE SCHEMA [" + _schemaName + "] AUTHORIZATION dbo";

                    if (ShouldProcess(PSObject.AsPSObject(SqlInstance).ToString(), "Creating schema [" + _schemaName + "] in database [" + _databaseName + "]"))
                    {
                        try
                        {
                            DatabaseQuery(database, schemaSql);
                            database.Schemas.Refresh();
                            WriteMessage(MessageLevel.Verbose, "Successfully created schema [" + _schemaName + "]");
                        }
                        catch (Exception ex)
                        {
                            StopFunction("Failed to create schema [" + _schemaName + "] in database [" + _databaseName + "]. The schema may have been created by another process, or you may lack CREATE SCHEMA permissions.",
                                errorRecord: new ErrorRecord(WrapAsMethodInvocation(ex, "Query", 1), "Write-DbaDbTableData", ErrorCategory.NotSpecified, null));
                            return;
                        }
                    }
                    else
                    {
                        // If ShouldProcess returns false (WhatIf scenario), we still need to return to avoid table creation attempts
                        return;
                    }
                }
            }
            catch (PipelineStoppedException) { throw; }
            catch (Exception ex) when (ex is not CaughtRecordException)
            {
                StopFunction("Failed to check for schema existence: [" + _schemaName + "] in database [" + _databaseName + "]",
                    errorRecord: ToCaughtRecord(ex));
                return;
            }
        }

        // Get SQL datatypes by best guess on first data row
        System.Collections.Generic.List<string> sqlDataTypes = new System.Collections.Generic.List<string>();
        DataColumnCollection? columns = (dataTable as DataTable)?.Columns;

        if (columns is null)
            columns = (PsAssignment.Unwrap(dataTable) as DataRow)?.Table?.Columns;

        if (columns is null)
        {
            StopFunction("Unable to get column definition from input data, so AutoCreateTable is not possible");
            return;
        }

        foreach (DataColumn column in columns)
        {
            string sqlColumnName = column.ColumnName;
            // (the function's $columnValue reads are dead code - the value is never used)

            /*
                PS to SQL type conversion
                If data type exists in hash table, use the corresponding SQL type
                Else, fallback to nvarchar.
                If UseDynamicStringLength is specified, the DataColumn MaxLength is used if specified
            */
            string sqlDataType;
            string typeKey = column.DataType.ToString();
            if (PStoSQLTypes.ContainsKey(typeKey))
            {
                sqlDataType = (string)PStoSQLTypes[typeKey]!;
                if (UseDynamicStringLength.ToBool() && column.MaxLength > 0 && column.DataType == typeof(string))
                    sqlDataType = sqlDataType.Replace("(MAX)", "(" + column.MaxLength + ")");
            }
            else
            {
                sqlDataType = "nvarchar(MAX)";
            }

            sqlDataTypes.Add("[" + sqlColumnName + "] " + sqlDataType);
        }

        string sql = "CREATE TABLE " + _fqtn + " (" + string.Join(" NULL,", sqlDataTypes) + " NULL)";

        WriteMessage(MessageLevel.Debug, sql);

        if (ShouldProcess(PSObject.AsPSObject(SqlInstance).ToString(), "Creating table " + _fqtn))
        {
            try
            {
                DatabaseQuery(_server!.Databases[_databaseName], sql);
            }
            catch (Exception ex)
            {
                StopFunction("The following query failed: " + sql,
                    errorRecord: new ErrorRecord(WrapAsMethodInvocation(ex, "Query", 1), "Write-DbaDbTableData", ErrorCategory.NotSpecified, null));
                return;
            }
        }
    }

    /// <summary>PS: $database.Query($sql) - the dbatools ETS ScriptMethod (xml/dbatools.Types.ps1xml):
    /// ($this.ExecuteWithResults($Query)).Tables[0]. A null database target raises the PS
    /// method-on-null failure.</summary>
    private static DataTable? DatabaseQuery(SmoDatabase? database, string query)
    {
        if (database is null)
            throw new PSInvalidOperationException("You cannot call a method on a null-valued expression.");
        DataSet dataSet = database.ExecuteWithResults(query);
        return dataSet.Tables.Count > 0 ? dataSet.Tables[0] : null;
    }

    /// <summary>Absorbed private/functions/Get-AdjustedTotalRowsCopied.ps1 (the Import-DbaCsv
    /// shape): adjusts for the legacy 4-byte rows-copied counter wrap (dataplat/dbatools#6927).</summary>
    internal static long GetAdjustedTotalRowsCopied(long reportedRowsCopied, long previousRowsCopied)
    {
        long newRowCountAdded = 0;

        if (reportedRowsCopied > 0)
        {
            if (previousRowsCopied >= 0)
                newRowCountAdded = reportedRowsCopied - previousRowsCopied;
            else
                // integer wrap just changed from negative to positive
                newRowCountAdded = Math.Abs(previousRowsCopied) + reportedRowsCopied;
        }
        else if (reportedRowsCopied < 0)
        {
            if (previousRowsCopied >= 0)
                // integer wrap just changed from positive to negative
                newRowCountAdded = (int.MaxValue - previousRowsCopied) + Math.Abs(int.MinValue - reportedRowsCopied) + 1;
            else
                newRowCountAdded = Math.Abs(previousRowsCopied) - Math.Abs(reportedRowsCopied);
        }

        return newRowCountAdded;
    }

    /// <summary>PS: @{ 'System.Int32' = 'int'; ... } - keys compare against the DataColumn's
    /// System.Type via -contains (Type string-converts to its FullName, linguistically
    /// case-insensitive), so the short-name keys are unreachable but preserved verbatim.</summary>
    private static readonly Hashtable PStoSQLTypes = new Hashtable(40, StringComparer.CurrentCultureIgnoreCase)
    {
        //PS datatype      = SQL data type
        { "System.Int32", "int" },
        { "System.UInt32", "bigint" },
        { "System.Int16", "smallint" },
        { "System.UInt16", "int" },
        { "System.Int64", "bigint" },
        { "System.UInt64", "decimal(20,0)" },
        { "System.Decimal", "decimal(38,5)" },
        { "System.Single", "bigint" },
        { "System.Double", "float" },
        { "System.Byte", "tinyint" },
        { "System.Byte[]", "varbinary(MAX)" },
        { "System.SByte", "smallint" },
        { "System.TimeSpan", "nvarchar(30)" },
        { "System.String", "nvarchar(MAX)" },
        { "System.Char", "nvarchar(1)" },
        { "System.DateTime", "datetime2" },
        { "System.DateTimeOffset", "datetimeoffset" },
        { "System.Boolean", "bit" },
        { "System.Guid", "uniqueidentifier" },
        { "Int32", "int" },
        { "UInt32", "bigint" },
        { "Int16", "smallint" },
        { "UInt16", "int" },
        { "Int64", "bigint" },
        { "UInt64", "decimal(20,0)" },
        { "Decimal", "decimal(38,5)" },
        { "Single", "bigint" },
        { "Double", "float" },
        { "Byte", "tinyint" },
        { "Byte[]", "varbinary(MAX)" },
        { "SByte", "smallint" },
        { "TimeSpan", "nvarchar(30)" },
        { "String", "nvarchar(MAX)" },
        { "Char", "nvarchar(1)" },
        { "DateTime", "datetime2" },
        { "DateTimeOffset", "datetimeoffset" },
        { "Boolean", "bit" },
        { "Bool", "bit" },
        { "Guid", "uniqueidentifier" },
        { "int", "int" },
        { "long", "bigint" },
    };

    /// <summary>Marker exception carrying a nested command's caught record through the C#
    /// try/catch seams (rebuilt into the original record at the Stop-Function site).</summary>
    private sealed class CaughtRecordException : Exception
    {
        public ErrorRecord Record { get; }
        public CaughtRecordException(ErrorRecord record) : base(record.Exception?.Message ?? "nested failure")
        {
            Record = record;
        }
    }

    /// <summary>PS: catch { $_ } - unwraps the marker, keeps real runtime records, rebuilds
    /// hand-built shapes (ParentContainsErrorRecordException drops the chain).</summary>
    private static ErrorRecord ToCaughtRecord(Exception ex)
    {
        if (ex is CaughtRecordException caught)
            return caught.Record;
        if (ex is RuntimeException runtime && runtime.ErrorRecord is not null &&
            runtime.ErrorRecord.Exception is not ParentContainsErrorRecordException)
        {
            return runtime.ErrorRecord;
        }
        return new ErrorRecord(ex, "Write-DbaDbTableData", ErrorCategory.NotSpecified, null);
    }

    /// <summary>Rebuilds the MethodInvocationException the PS method binder raised:
    /// 'Exception calling "Name" with "N" argument(s): "inner"'.</summary>
    private static MethodInvocationException WrapAsMethodInvocation(Exception inner, string methodName, int argumentCount)
    {
        string text = "Exception calling \"" + methodName + "\" with \"" + argumentCount + "\" argument(s): \"" + inner.Message + "\"";
        return new MethodInvocationException(text, inner);
    }

    /// <summary>PS dynamic method dispatch on an untyped context object (ServerConnection
    /// members reached through the member binder).</summary>
    private static object? InvokePsMethod(object? target, string methodName, params object?[] arguments)
    {
        object? baseObject = PsAssignment.Unwrap(target);
        if (baseObject is null)
            throw new PSInvalidOperationException("You cannot call a method on a null-valued expression.");
        try
        {
            return baseObject.GetType().InvokeMember(methodName,
                System.Reflection.BindingFlags.InvokeMethod | System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance,
                null, baseObject, arguments, CultureInfo.InvariantCulture);
        }
        catch (System.Reflection.TargetInvocationException tie) when (tie.InnerException is not null)
        {
            throw WrapAsMethodInvocation(tie.InnerException, methodName, arguments.Length);
        }
    }

    /// <summary>PS interpolation-style text ([string]/"$x" - null renders empty).</summary>
    private static string PsToText(object? value)
    {
        if (value is null)
            return "";
        return PSObject.AsPSObject(value).ToString();
    }

    /// <summary>Detects the hop script's caught-error marker (outcome-as-data).</summary>
    private static ErrorRecord? ExtractCaughtError(PSObject? item)
    {
        if (item?.BaseObject is PSCustomObject)
        {
            PSPropertyInfo? marker = item.Properties["__dbatoolsCaughtError"];
            if (marker?.Value is not null)
                return PsAssignment.Unwrap(marker.Value) as ErrorRecord;
        }
        return null;
    }

    private const string DbNameQueryScript = """
param($__instance, $__credential)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__instance, $__credential)
    Invoke-DbaQuery -SqlInstance $__instance -SqlCredential $__credential -Query "SELECT DB_NAME() AS dbname" 3>&1
} $__instance $__credential
""";

    private const string GetObjectNamePartsScript = """
param($__table)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__table)
    Get-ObjectNameParts -ObjectName $__table
} $__table
""";

    private const string ConnectScript = """
param($__instance, $__credential, $__database)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__instance, $__credential, $__database)
    try {
        Connect-DbaInstance -SqlInstance $__instance -SqlCredential $__credential -Database $__database -NonPooledConnection 3>&1
    } catch {
        [PSCustomObject]@{ __dbatoolsCaughtError = $PSItem }
    }
} $__instance $__credential $__database
""";

    private const string ConfigBagScript = """
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [PSCustomObject]@{
        TimeSpanType = (Get-DbatoolsConfigValue -FullName 'commands.Write-DbaDbTableData.timespantype' -Fallback 'TotalMilliseconds')
        SizeType     = (Get-DbatoolsConfigValue -FullName 'commands.Write-DbaDbTableData.sizetype' -Fallback 'Int64')
        IgnoreNull   = (Get-DbatoolsConfigValue -FullName 'commands.Write-DbaDbTableData.ignorenull' -Fallback $false)
        Raw          = (Get-DbatoolsConfigValue -FullName 'commands.Write-DbaDbTableData.raw' -Fallback $false)
    }
}
""";

    // The bound -WhatIf/-Confirm forward explicitly (W1-021 preference propagation: a
    // compiled cmdlet's ambient WhatIf never reaches a nested InvokeScript command).
    private const string DisconnectScript = """
param($__server, $__whatIf, $__confirm)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__server, $__whatIf, $__confirm)
    $__splat = @{}
    if ($null -ne $__whatIf) { $__splat["WhatIf"] = $__whatIf }
    if ($null -ne $__confirm) { $__splat["Confirm"] = $__confirm }
    $null = $__server | Disconnect-DbaInstance @__splat
} $__server $__whatIf $__confirm
""";
}
