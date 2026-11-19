#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Corrects page/row-count inaccuracies in catalog views via DBCC UPDATEUSAGE. The begin-block query
/// construction (the NO_INFOMSGS / COUNT_ROWS ladder keyed off boundness plus the verbose echo of the
/// built query), the per-instance connect, the per-database enumeration, the Table/Index #options#
/// substitution (with the Get-ObjectNameParts escaping and numeric-vs-quoted branches), the two
/// ShouldProcess gates, and the per-row result object remain a module-scoped PowerShell compatibility
/// hop; the compiled cmdlet supplies the begin/process lifetime, routes both ShouldProcess gates through
/// its real runtime (ConfirmImpact High), carries the begin-scoped query builder into the process hop,
/// and carries the function-scoped $results the source leaks across pipeline records. Surface pinned by
/// migration/baselines/Invoke-DbaDbDbccUpdateUsage.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Invoke, "DbaDbDbccUpdateUsage", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class InvokeDbaDbDbccUpdateUsageCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Databases to update usage statistics for (names or IDs).</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>A single table or indexed view (name or object ID) to update.</summary>
    [Parameter(Position = 3)]
    [PsStringCast]
    public string? Table { get; set; }

    /// <summary>A single index (name or index ID) to update; requires Table.</summary>
    [Parameter(Position = 4)]
    [PsStringCast]
    public string? Index { get; set; }

    /// <summary>Suppresses informational DBCC messages (WITH NO_INFOMSGS).</summary>
    [Parameter]
    public SwitchParameter NoInformationalMessages { get; set; }

    /// <summary>Recalculates row counts in addition to page counts (COUNT_ROWS).</summary>
    [Parameter]
    public SwitchParameter CountRows { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // $stringBuilder is built once in the source begin block and read every process record; carry it
    // forward so the process hop reads the same query the begin scope produced.
    private object? _stringBuilder;

    // $results is function-scoped in the source: it is assigned only inside the execute-ShouldProcess
    // gate but read inside the SEPARATE output foreach. A per-record hop resets it, so we carry it
    // forward to reproduce the source's cross-record function-scope leak bug-for-bug. Starts null.
    private object? _resultsState;

    // Per-invocation token so the process carrier sentinel is distinguishable from real output.
    private readonly string _processToken = Guid.NewGuid().ToString("N");

    protected override void BeginProcessing()
    {
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            TestBound(nameof(NoInformationalMessages)), TestBound(nameof(CountRows)),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__InvokeDbaDbDbccUpdateUsageBeginComplete"]?.Value))
            {
                _stringBuilder = UnwrapHopValue(item.Properties["StringBuilder"]?.Value);
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && string.Equals(
                item.Properties["__InvokeDbaDbDbccUpdateUsageProcessComplete"]?.Value as string, _processToken, StringComparison.Ordinal))
            {
                _resultsState = UnwrapHopValue(item.Properties["Results"]?.Value);
            }
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            _stringBuilder, SqlInstance, SqlCredential, Database, Table, Index, EnableException.ToBool(),
            _resultsState, this, _processToken,
            TestBound(nameof(Database)), TestBound(nameof(Table)), TestBound(nameof(Index)),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // Carried hop state arrives PSObject-wrapped. A PSCustomObject carries its content on the
    // wrapper rather than the BaseObject, so unwrapping one would discard it - keep it wrapped.
    private static object? UnwrapHopValue(object? value)
    {
        if (value is PSObject wrapper && wrapper.BaseObject is not PSCustomObject)
            return wrapper.BaseObject;
        return value;
    }

    private const string BeginScript = """
param($__boundNoInformationalMessages, $__boundCountRows, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($__boundNoInformationalMessages, $__boundCountRows)

    # Test-Bound replacement: the source keyed the NO_INFOMSGS / COUNT_ROWS suffixes off whether the
    # caller EXPLICITLY bound each switch (a boundness check, not its value); module scope cannot see
    # the caller's bound set, so boundness is carried in as a flag per parameter.
    $stringBuilder = New-Object System.Text.StringBuilder
    $null = $stringBuilder.Append("DBCC UPDATEUSAGE(#options#)")
    if ($__boundNoInformationalMessages) {
        $null = $stringBuilder.Append(" WITH NO_INFOMSGS")
        if ($__boundCountRows) {
            $null = $stringBuilder.Append(", COUNT_ROWS")
        }
    } else {
        if ($__boundCountRows) {
            $null = $stringBuilder.Append(" WITH COUNT_ROWS")
        }
    }
    Write-Message -Message "$($StringBuilder.ToString())" -Level Verbose -FunctionName Invoke-DbaDbDbccUpdateUsage -ModuleName "dbatools"

    [pscustomobject]@{ __InvokeDbaDbDbccUpdateUsageBeginComplete = $true; StringBuilder = $stringBuilder }
} $__boundNoInformationalMessages $__boundCountRows @__commonParameters 3>&1 2>&1
""";

    private const string ProcessScript = """
param($StringBuilder, $SqlInstance, $SqlCredential, $Database, $Table, $Index, $EnableException, $results, $__realCmdlet, $__processToken, $__boundDatabase, $__boundTable, $__boundIndex, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param($StringBuilder, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string[]]$Database, [string]$Table, [string]$Index, $EnableException, $results, $__realCmdlet, $__processToken, $__boundDatabase, $__boundTable, $__boundIndex)

    foreach ($instance in $SqlInstance) {
        Write-Message -Message "Attempting Connection to $instance" -Level Verbose -FunctionName Invoke-DbaDbDbccUpdateUsage -ModuleName "dbatools"
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Invoke-DbaDbDbccUpdateUsage
        }

        $dbs = $server.Databases

        if ($__boundDatabase) {
            $dbs = $dbs | Where-Object { ($_.Name -In $Database) -or ($_.ID -In $Database) }
        }

        foreach ($db in $dbs) {
            Write-Message -Level Verbose -Message "Processing $db on $instance" -FunctionName Invoke-DbaDbDbccUpdateUsage -ModuleName "dbatools"

            if ($db.IsAccessible -eq $false) {
                Stop-Function -Message "The database $db is not accessible. Skipping." -Continue -FunctionName Invoke-DbaDbDbccUpdateUsage
            }

            try {
                $query = $StringBuilder.ToString()
                if ($__boundTable) {
                    if ($Table -notmatch "^\d+$") {
                        $tableNameParts = Get-ObjectNameParts -ObjectName $Table
                        if ($tableNameParts.Name) {
                            $escapedTableName = $tableNameParts.Name.Replace("]", "]]")
                            if ($tableNameParts.Schema) {
                                $escapedTableSchema = $tableNameParts.Schema.Replace("]", "]]")
                                $tableIdentifier = "[$escapedTableSchema].[$escapedTableName]"
                            } else {
                                $tableIdentifier = "[$escapedTableName]"
                            }
                        } else {
                            $tableIdentifier = $Table
                        }
                    }
                    if ($__boundIndex) {
                        if ($Table -match "^\d+$") {
                            if ($Index -match "^\d+$") {
                                $query = $query.Replace('#options#', "'$($db.name)', $Table, $Index")
                            } else {
                                $query = $query.Replace('#options#', "'$($db.name)', $Table, '$Index'")
                            }
                        } else {
                            if ($Index -match "^\d+$") {
                                $query = $query.Replace('#options#', "'$($db.name)', '$tableIdentifier', $Index")
                            } else {
                                $query = $query.Replace('#options#', "'$($db.name)', '$tableIdentifier', '$Index'")
                            }
                        }
                    } else {
                        if ($Table -match "^\d+$") {
                            $query = $query.Replace('#options#', "'$($db.name)', $Table")
                        } else {
                            $query = $query.Replace('#options#', "'$($db.name)', '$tableIdentifier'")
                        }
                    }
                } else {
                    $query = $query.Replace('#options#', "'$($db.name)'")
                }

                if ($__realCmdlet.ShouldProcess($server.Name, "Execute the command $query against $instance")) {
                    Write-Message -Message "Query to run: $query" -Level Verbose -FunctionName Invoke-DbaDbDbccUpdateUsage -ModuleName "dbatools"
                    $results = $server | Invoke-DbaQuery  -Query $query -MessagesToOutput
                    Write-Message -Message "$($results.Count)" -Level Verbose -FunctionName Invoke-DbaDbDbccUpdateUsage -ModuleName "dbatools"
                }
            } catch {
                Stop-Function -Message "Error capturing data on $db" -Target $instance -ErrorRecord $_ -Exception $_.Exception -Continue -FunctionName Invoke-DbaDbDbccUpdateUsage
            }

            foreach ($row in $results) {
                if ($__realCmdlet.ShouldProcess("console", "Outputting object")) {
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $db.name
                        Cmd          = $query.ToString()
                        Output       = $results
                    }
                }
            }
        }
    }

    [pscustomobject]@{ __InvokeDbaDbDbccUpdateUsageProcessComplete = $__processToken; Results = $results }
} $StringBuilder $SqlInstance $SqlCredential $Database $Table $Index $EnableException $results $__realCmdlet $__processToken $__boundDatabase $__boundTable $__boundIndex @__commonParameters 3>&1 2>&1
""";
}
