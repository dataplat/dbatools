#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves Query Store configuration for user databases. Port of public/Get-DbaDbQueryStoreOption.ps1;
/// the workflow remains a module-scoped PowerShell compatibility hop.
///
/// A begin+process port (SqlInstance is ValueFromPipeline, so process fires per record). The source begin
/// block augments $ExcludeDatabase by appending the system databases master/tempdb/model (SMO cannot report
/// Query Store on those); that augmented array is the begin's ONLY output and is carried begin->process via a
/// sentinel (_excludeDatabase) - the process block then reads it verbatim in its Get-DbaDatabase call. No
/// accumulator, no interrupt (the one Stop-Function is -Continue), no Test-Bound, no ShouldProcess. The only
/// process edits are -FunctionName Get-DbaDbQueryStoreOption on the one Stop-Function and one Write-Message.
/// Surface pinned by migration/baselines/Get-DbaDbQueryStoreOption.json (positions 0-3, no aliases, no ShouldProcess).
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaDbQueryStoreOption")]
public sealed class GetDbaDbQueryStoreOptionCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances (SQL 2016+).</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>The database(s) to exclude (master/tempdb/model are always excluded).</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Carried begin->process: the augmented ExcludeDatabase (source + master/tempdb/model).
    private object[]? _excludeDatabase;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__qsoBegin"))
            {
                if (sentinel["__qsoBegin"] is Hashtable state)
                {
                    _excludeDatabase = state["ExcludeDatabase"] as object[];
                }
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, BeginScript,
            ExcludeDatabase, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
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
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, _excludeDatabase, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }
    // PS: the begin block VERBATIM - augments $ExcludeDatabase, then the sentinel carries it to process.
    private const string BeginScript = """
param($ExcludeDatabase, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([object[]]$ExcludeDatabase, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        # We exclude model because SMO cannot tell if Query Store is enabled there
        $ExcludeDatabase += 'master', 'tempdb', "model"
    @{ __qsoBegin = @{ ExcludeDatabase = [object[]]$ExcludeDatabase } }
} $ExcludeDatabase $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process block VERBATIM. Edit: -FunctionName Get-DbaDbQueryStoreOption on the one Stop-Function
    // and one Write-Message. $ExcludeDatabase arrives already augmented by the begin block (via _excludeDatabase).
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [object[]]$Database, [object[]]$ExcludeDatabase, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 13
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Get-DbaDbQueryStoreOption
            }

            # We have to exclude system databases since they cannot have the Query Store feature enabled
            $dbs = Get-DbaDatabase -SqlInstance $server -ExcludeDatabase $ExcludeDatabase -Database $Database | Where-Object IsAccessible

            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Processing $($db.Name) on $instance" -FunctionName Get-DbaDbQueryStoreOption -ModuleName "dbatools"
                $qso = $db.QueryStoreOptions

                if ($server.VersionMajor -eq 14) {
                    $QueryStoreOptions = Invoke-DbaQuery -SqlInstance $server -Database $db.Name -Query "SELECT max_plans_per_query AS MaxPlansPerQuery, wait_stats_capture_mode_desc AS WaitStatsCaptureMode FROM sys.database_query_store_options;" -As PSObject
                } elseif ($server.VersionMajor -ge 15) {
                    $QueryStoreOptions = Invoke-DbaQuery -SqlInstance $server -Database $db.Name -Query "SELECT max_plans_per_query AS MaxPlansPerQuery, wait_stats_capture_mode_desc AS WaitStatsCaptureMode, capture_policy_execution_count AS CustomCapturePolicyExecutionCount, capture_policy_stale_threshold_hours AS CustomCapturePolicyStaleThresholdHours, capture_policy_total_compile_cpu_time_ms AS CustomCapturePolicyTotalCompileCPUTimeMS, capture_policy_total_execution_cpu_time_ms AS CustomCapturePolicyTotalExecutionCPUTimeMS FROM sys.database_query_store_options;" -As PSObject
                }

                Add-Member -Force -InputObject $qso -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                Add-Member -Force -InputObject $qso -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                Add-Member -Force -InputObject $qso -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                Add-Member -Force -InputObject $qso -MemberType NoteProperty Database -Value $db.Name

                if ($server.VersionMajor -eq 13) {
                    Select-DefaultView -InputObject $qso -Property ComputerName, InstanceName, SqlInstance, Database, ActualState, DataFlushIntervalInSeconds, StatisticsCollectionIntervalInMinutes, MaxStorageSizeInMB, CurrentStorageSizeInMB, QueryCaptureMode, SizeBasedCleanupMode, StaleQueryThresholdInDays
                } elseif ($server.VersionMajor -eq 14) {
                    Add-Member -Force -InputObject $qso -MemberType NoteProperty -Name MaxPlansPerQuery -Value $QueryStoreOptions.MaxPlansPerQuery
                    Add-Member -Force -InputObject $qso -MemberType NoteProperty -Name WaitStatsCaptureMode -Value $QueryStoreOptions.WaitStatsCaptureMode
                    Select-DefaultView -InputObject $qso -Property ComputerName, InstanceName, SqlInstance, Database, ActualState, DataFlushIntervalInSeconds, StatisticsCollectionIntervalInMinutes, MaxStorageSizeInMB, CurrentStorageSizeInMB, QueryCaptureMode, SizeBasedCleanupMode, StaleQueryThresholdInDays, MaxPlansPerQuery, WaitStatsCaptureMode
                } elseif ($server.VersionMajor -ge 15) {
                    Add-Member -Force -InputObject $qso -MemberType NoteProperty -Name CustomCapturePolicyExecutionCount -Value $QueryStoreOptions.CustomCapturePolicyExecutionCount
                    Add-Member -Force -InputObject $qso -MemberType NoteProperty -Name CustomCapturePolicyTotalCompileCPUTimeMS -Value $QueryStoreOptions.CustomCapturePolicyTotalCompileCPUTimeMS
                    Add-Member -Force -InputObject $qso -MemberType NoteProperty -Name CustomCapturePolicyTotalExecutionCPUTimeMS -Value $QueryStoreOptions.CustomCapturePolicyTotalExecutionCPUTimeMS
                    Add-Member -Force -InputObject $qso -MemberType NoteProperty -Name CustomCapturePolicyStaleThresholdHours -Value $QueryStoreOptions.CustomCapturePolicyStaleThresholdHours
                    Select-DefaultView -InputObject $qso -Property ComputerName, InstanceName, SqlInstance, Database, ActualState, DataFlushIntervalInSeconds, StatisticsCollectionIntervalInMinutes, MaxStorageSizeInMB, CurrentStorageSizeInMB, QueryCaptureMode, SizeBasedCleanupMode, StaleQueryThresholdInDays, MaxPlansPerQuery, WaitStatsCaptureMode, CustomCapturePolicyExecutionCount, CustomCapturePolicyTotalCompileCPUTimeMS, CustomCapturePolicyTotalExecutionCPUTimeMS, CustomCapturePolicyStaleThresholdHours
                }
            }
        }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
