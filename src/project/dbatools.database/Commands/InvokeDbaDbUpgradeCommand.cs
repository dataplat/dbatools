#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Upgrades databases after a compatibility-level change: sets compatibility, target recovery time,
/// DBCC CHECKDB DATA_PURITY, DBCC UPDATEUSAGE, statistics, and view refreshes. Port of
/// public/Invoke-DbaDbUpgrade.ps1; the workflow remains a module-scoped PowerShell compatibility hop.
///
/// SINGLE HOP. The source's begin block does exactly one thing - "if ($Force) { $ConfirmPreference =
/// 'none' }" - so there is no begin state to carry and no separate begin hop. That line is folded to
/// the top of the process hop body (the Dismount-DbaDatabase pattern): -Force is a DECLARED
/// parameter here, so it is constant across records and setting the preference per record is
/// identical to the source's run-once begin. (Contrast Invoke-DbaDbDataMasking, where $Force is
/// UNDECLARED and dynamic, so its value must be resolved once in a begin hop and carried.) A
/// hop-local $ConfirmPreference does suppress the outer cmdlet's ShouldProcess - measured on a real
/// compiled cmdlet through the module-scoped hop in migration/logs/probe-20260718-force-confirmpref.
///
/// Only InputObject is ValueFromPipeline; SqlInstance is NOT. So piping databases fires process per
/// record with InputObject rebinding each time, and supplying -SqlInstance instead fires process
/// exactly once. Either way the body's "$InputObject += $server.Databases" cannot accumulate across
/// records the way Invoke-DbaDbShrink's does.
///
/// CROSS-RECORD STATE. FIVE per-step result variables carry: CompatibilityResult,
/// targetRecoveryTimeResult, DataPurityResult, UpdateUsageResult and UpdateStatsResult. Each is
/// assigned ONLY INSIDE its own ShouldProcess gate (or the matching skip branch), so a DECLINED
/// gate - every gate under -WhatIf - leaves it unassigned for the current database, holding the
/// previous database's or previous RECORD's value, while all of them are read unconditionally by
/// the emitted object. They ride the state sentinel with per-name Assigned flags so
/// unset-vs-assigned survives.
///
/// RefreshViewResult deliberately does NOT carry, and the contrast is the point: it is assigned
/// "Success" BEFORE its per-view gates and "Skipped" in the alternative branch, so one branch
/// always assigns it and a declined gate can only prevent the "Fail" overwrite. Assigned-inside-
/// the-gate is what makes a variable carry; assigned-before-the-gate does not.
///
/// $server does NOT carry either. It is assigned in a try whose catch is Stop-Function -Continue,
/// and a continue inside a catch skips the rest of that loop iteration - measured, not assumed -
/// so the "$InputObject += $server.Databases" line below it is unreachable after a connection
/// failure and can never read a stale server. The second assignment ($db.Parent) is unconditional.
///
/// TEST-BOUND NEVER RIDES A HOP - it scope-walks the caller, and inside the hop that caller is the
/// generated scriptblock. The two guards use the multi-name "-not" form, so five boundness flags are
/// carried and the guards become plain boolean expressions over them:
///   Test-Bound -not 'SqlInstance','InputObject'
///   Test-Bound -not 'Database','InputObject','ExcludeDatabase','AllUserDatabases'
/// The flags report what the CALLER bound, which is what the source tested.
///
/// All seven $Pscmdlet.ShouldProcess gates route to the real cmdlet via $__realCmdlet so a
/// "Yes to All" answer persists across the whole invocation rather than resetting per hop
/// (SupportsShouldProcess, ConfirmImpact Medium mirrored). The single Stop-Function is -Continue and
/// there is no Test-FunctionInterrupt in the source, so no interrupt flag is ever raised and none is
/// carried. The three bare "continue" statements ride verbatim but are NOT alike: the two argument
/// guards sit in the process block ahead of any loop, so they exit the record, while the third is
/// inside the "foreach ($db in $InputObject)" loop and merely skips a database already at the right
/// compatibility level. Dot-sourcing preserves both meanings unchanged. In-hop Stop-Function/Write-Message carry
/// -FunctionName. Surface pinned by migration/baselines/Invoke-DbaDbUpgrade.json - SqlInstance
/// declares an explicit Position 0, which suppresses the implicit auto-numbering, so every other
/// parameter is correctly positionless.
/// </summary>
[Cmdlet(VerbsLifecycle.Invoke, "DbaDbUpgrade", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class InvokeDbaDbUpgradeCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to upgrade.</summary>
    [Parameter]
    public object[]? Database { get; set; }

    /// <summary>Databases to skip.</summary>
    [Parameter]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Skip the DBCC CHECKDB DATA_PURITY step.</summary>
    [Parameter]
    public SwitchParameter NoCheckDb { get; set; }

    /// <summary>Skip the DBCC UPDATEUSAGE step.</summary>
    [Parameter]
    public SwitchParameter NoUpdateUsage { get; set; }

    /// <summary>Skip the statistics update step.</summary>
    [Parameter]
    public SwitchParameter NoUpdateStats { get; set; }

    /// <summary>Skip the view refresh step.</summary>
    [Parameter]
    public SwitchParameter NoRefreshView { get; set; }

    /// <summary>Upgrade every user database on the instance.</summary>
    [Parameter]
    public SwitchParameter AllUserDatabases { get; set; }

    /// <summary>Suppress confirmation prompts.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    /// <summary>SMO Database object(s), typically from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The six per-step result variables. Each is assigned only inside its own ShouldProcess gate
    // (or its no-change branch), so a DECLINED gate - every gate under -WhatIf - leaves it holding
    // the previous database's or previous record's value, and all six are read unconditionally by
    // the emitted object. The source's function scope carries that; a per-record hop would not.
    private Hashtable? _state;

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__invokeDbaDbUpgradeState"))
            {
                _state = sentinel["__invokeDbaDbUpgradeState"] as Hashtable;
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, ExcludeDatabase, NoCheckDb.ToBool(),
            NoUpdateUsage.ToBool(), NoUpdateStats.ToBool(), NoRefreshView.ToBool(),
            AllUserDatabases.ToBool(), Force.ToBool(), InputObject, EnableException.ToBool(), _state, this,
            MyInvocation.BoundParameters.ContainsKey("SqlInstance"),
            MyInvocation.BoundParameters.ContainsKey("InputObject"),
            MyInvocation.BoundParameters.ContainsKey("Database"),
            MyInvocation.BoundParameters.ContainsKey("ExcludeDatabase"),
            MyInvocation.BoundParameters.ContainsKey("AllUserDatabases"),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block VERBATIM per record, dot-sourced so the two record-exiting guards, the
    // loop-local database-skip continue, and any early exit all keep their source meanings. Edits: the two Test-Bound guards become
    // boolean expressions over the carried boundness flags (Test-Bound scope-walks the caller and
    // can never ride a hop), the seven $Pscmdlet gates route to $__realCmdlet, and -FunctionName is
    // stamped on the 21 direct Stop-Function/Write-Message calls. The source's begin line
    // "if ($Force) { $ConfirmPreference = 'none' }" is folded to the top: -Force is a declared
    // parameter, so per-record is identical to the source's run-once begin.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $NoCheckDb, $NoUpdateUsage, $NoUpdateStats, $NoRefreshView, $AllUserDatabases, $Force, $InputObject, $EnableException, $__state, $__realCmdlet, $__boundSqlInstance, $__boundInputObject, $__boundDatabase, $__boundExcludeDatabase, $__boundAllUserDatabases, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [object[]]$Database, [object[]]$ExcludeDatabase, $NoCheckDb, $NoUpdateUsage, $NoUpdateStats, $NoRefreshView, $AllUserDatabases, $Force, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__state, $__realCmdlet, $__boundSqlInstance, $__boundInputObject, $__boundDatabase, $__boundExcludeDatabase, $__boundAllUserDatabases, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # the source's begin block, folded here (its only effect is $ConfirmPreference; -Force is a
    # declared parameter so it is constant across records and per-record equals run-once)
    if ($Force) { $ConfirmPreference = 'none' }

    # Restore the six per-step result variables. Each is assigned only inside its own ShouldProcess
    # gate (or no-change branch), so a declined gate leaves it holding the previous database's or
    # previous record's value - which the emitted object then reports.
    if ($null -ne $__state) {
        foreach ($__name in "CompatibilityResult", "targetRecoveryTimeResult", "DataPurityResult", "UpdateUsageResult", "UpdateStatsResult") {
            if ($__state[$__name + "Assigned"]) { Set-Variable -Name $__name -Value $__state[$__name] }
        }
    }

    . {

        if ((-not $__boundSqlInstance -and -not $__boundInputObject)) {
            Write-Message -Level Warning -Message "You must specify either a SQL instance or pipe a database collection" -FunctionName Invoke-DbaDbUpgrade -ModuleName "dbatools"
            continue
        }

        if ((-not $__boundDatabase -and -not $__boundInputObject -and -not $__boundExcludeDatabase -and -not $__boundAllUserDatabases)) {
            Write-Message -Level Warning -Message "You must explicitly specify a database. Use -Database, -ExcludeDatabase, -AllUserDatabases or pipe a database collection" -FunctionName Invoke-DbaDbUpgrade -ModuleName "dbatools"
            continue
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Invoke-DbaDbUpgrade
            }
            $InputObject += $server.Databases | Where-Object IsAccessible
        }

        $InputObject = $InputObject | Where-Object { $_.IsSystemObject -eq $false }
        if ($Database) {
            $InputObject = $InputObject | Where-Object Name -In $Database
        }
        if ($ExcludeDatabase) {
            $InputObject = $InputObject | Where-Object Name -NotIn $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            # create objects to use in updates
            $server = $db.Parent
            $serverVersion = $server.VersionMajor
            Write-Message -Level Verbose -Message "SQL Server is using Version: $serverVersion" -FunctionName Invoke-DbaDbUpgrade -ModuleName "dbatools"

            $dbLevel = $db.CompatibilityLevel
            $serverLevel = [Microsoft.SqlServer.Management.Smo.CompatibilityLevel]"Version$($serverVersion)0"
            $levelOk = $dbLevel -eq $serverLevel
            $timeOk = if ($serverVersion -ge 13 -and $db.TargetRecoveryTime -ne 60) { $false } else { $true }

            if (-not $Force) {
                # skip over databases at the correct level and correct target recovery time, unless -Force
                if ($levelOk -and $timeOk) {
                    Write-Message -Level VeryVerbose -Message "Skipping $db because compatibility is at the correct level and target recovery time is correct. Use -Force if you want to run all the additional steps." -FunctionName Invoke-DbaDbUpgrade -ModuleName "dbatools"
                    continue
                }
            }

            Write-Message -Level Verbose -Message "Updating $db compatibility to SQL Instance level" -FunctionName Invoke-DbaDbUpgrade -ModuleName "dbatools"
            if (-not $levelOk) {
                If ($__realCmdlet.ShouldProcess($server, "Updating $db compatibility on $server from $dbLevel to $serverLevel")) {
                    try {
                        $db.CompatibilityLevel = $serverLevel
                        $db.Alter()
                        $CompatibilityResult = $serverLevel.ToString().Replace('Version', '')
                    } catch {
                        Write-Message -Level Warning -Message "Failed run Compatibility Upgrade" -ErrorRecord $_ -Target $instance -FunctionName Invoke-DbaDbUpgrade -ModuleName "dbatools"
                        $CompatibilityResult = "Fail"
                    }
                }
            } else {
                $CompatibilityResult = "No change"
            }

            Write-Message -Level Verbose -Message "Updating $db target recovery time to 60 seconds on SQL Server 2016 or newer" -FunctionName Invoke-DbaDbUpgrade -ModuleName "dbatools"
            if (-not $timeOk) {
                If ($__realCmdlet.ShouldProcess($server, "Updating $db target recovery time on $server from $($db.TargetRecoveryTime) seconds to 60 seconds")) {
                    try {
                        $db.TargetRecoveryTime = 60
                        $db.Alter()
                        $targetRecoveryTimeResult = 60
                    } catch {
                        Write-Message -Level Warning -Message "Failed to change target recovery time" -ErrorRecord $_ -Target $instance -FunctionName Invoke-DbaDbUpgrade -ModuleName "dbatools"
                        $targetRecoveryTimeResult = "Fail"
                    }
                }
            } else {
                $targetRecoveryTimeResult = "No change"
            }

            if (!($NoCheckDb)) {
                Write-Message -Level Verbose -Message "Updating $db with DBCC CHECKDB DATA_PURITY" -FunctionName Invoke-DbaDbUpgrade -ModuleName "dbatools"
                If ($__realCmdlet.ShouldProcess($server, "Updating $db with DBCC CHECKDB DATA_PURITY")) {
                    $tsqlCheckDB = "DBCC CHECKDB ('$($db.Name)') WITH DATA_PURITY, NO_INFOMSGS"
                    try {
                        $db.ExecuteNonQuery($tsqlCheckDB)
                        $DataPurityResult = "Success"
                    } catch {
                        Write-Message -Level Warning -Message "Failed run DBCC CHECKDB with DATA_PURITY on $db" -ErrorRecord $_ -Target $instance -FunctionName Invoke-DbaDbUpgrade -ModuleName "dbatools"
                        $DataPurityResult = "Fail"
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "Ignoring CHECKDB DATA_PURITY" -FunctionName Invoke-DbaDbUpgrade -ModuleName "dbatools"
            }

            if (!($NoUpdateUsage)) {
                Write-Message -Level Verbose -Message "Updating $db with DBCC UPDATEUSAGE" -FunctionName Invoke-DbaDbUpgrade -ModuleName "dbatools"
                If ($__realCmdlet.ShouldProcess($server, "Updating $db with DBCC UPDATEUSAGE")) {
                    $tsqlUpdateUsage = "DBCC UPDATEUSAGE ($db) WITH NO_INFOMSGS;"
                    try {
                        $db.ExecuteNonQuery($tsqlUpdateUsage)
                        $UpdateUsageResult = "Success"
                    } catch {
                        Write-Message -Level Warning -Message "Failed to run DBCC UPDATEUSAGE on $db" -ErrorRecord $_ -Target $instance -FunctionName Invoke-DbaDbUpgrade -ModuleName "dbatools"
                        $UpdateUsageResult = "Fail"
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "Ignore DBCC UPDATEUSAGE" -FunctionName Invoke-DbaDbUpgrade -ModuleName "dbatools"
                $UpdateUsageResult = "Skipped"
            }

            if (!($NoUpdatestats)) {
                Write-Message -Level Verbose -Message "Updating $db statistics" -FunctionName Invoke-DbaDbUpgrade -ModuleName "dbatools"
                If ($__realCmdlet.ShouldProcess($server, "Updating $db statistics")) {
                    $tsqlStats = "EXEC sp_updatestats;"
                    try {
                        $db.ExecuteNonQuery($tsqlStats)
                        $UpdateStatsResult = "Success"
                    } catch {
                        Write-Message -Level Warning -Message "Failed to run sp_updatestats on $db" -ErrorRecord $_ -Target $instance -FunctionName Invoke-DbaDbUpgrade -ModuleName "dbatools"
                        $UpdateStatsResult = "Fail"
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "Ignoring sp_updatestats" -FunctionName Invoke-DbaDbUpgrade -ModuleName "dbatools"
                $UpdateStatsResult = "Skipped"
            }

            if (!($NoRefreshView)) {
                Write-Message -Level Verbose -Message "Refreshing $db Views" -FunctionName Invoke-DbaDbUpgrade -ModuleName "dbatools"
                $dbViews = $db.Views | Where-Object IsSystemObject -eq $false
                $RefreshViewResult = "Success"
                foreach ($dbview in $dbviews) {
                    $viewName = $dbView.Name
                    $viewSchema = $dbView.Schema
                    $fullName = $viewSchema + "." + $viewName

                    $tsqlupdateView = "EXECUTE sp_refreshview N'$fullName';  "

                    If ($__realCmdlet.ShouldProcess($server, "Refreshing view $fullName on $db")) {
                        try {
                            $db.ExecuteNonQuery($tsqlupdateView)
                        } catch {
                            Write-Message -Level Warning -Message "Failed update view $fullName on $db" -ErrorRecord $_ -Target $instance -FunctionName Invoke-DbaDbUpgrade -ModuleName "dbatools"
                            $RefreshViewResult = "Fail"
                        }
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "Ignore View Refreshes" -FunctionName Invoke-DbaDbUpgrade -ModuleName "dbatools"
                $RefreshViewResult = "Skipped"
            }

            If ($__realCmdlet.ShouldProcess("console", "Outputting object")) {
                $db.Refresh()

                [PSCustomObject]@{
                    ComputerName          = $server.ComputerName
                    InstanceName          = $server.ServiceName
                    SqlInstance           = $server.DomainInstanceName
                    Database              = $db.name
                    OriginalCompatibility = $dbLevel.ToString().Replace('Version', '')
                    CurrentCompatibility  = $db.CompatibilityLevel.ToString().Replace('Version', '')
                    Compatibility         = $CompatibilityResult
                    TargetRecoveryTime    = $targetRecoveryTimeResult
                    DataPurity            = $DataPurityResult
                    UpdateUsage           = $UpdateUsageResult
                    UpdateStats           = $UpdateStatsResult
                    RefreshViews          = $RefreshViewResult
                }
            }
        }
    }

    $__snap = @{}
    foreach ($__name in "CompatibilityResult", "targetRecoveryTimeResult", "DataPurityResult", "UpdateUsageResult", "UpdateStatsResult") {
        $__v = Get-Variable -Name $__name -Scope 0 -ErrorAction Ignore
        if ($__v) { $__snap[$__name + "Assigned"] = $true; $__snap[$__name] = $__v.Value } else { $__snap[$__name + "Assigned"] = $false }
    }
    @{ __invokeDbaDbUpgradeState = $__snap }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $NoCheckDb $NoUpdateUsage $NoUpdateStats $NoRefreshView $AllUserDatabases $Force $InputObject $EnableException $__state $__realCmdlet $__boundSqlInstance $__boundInputObject $__boundDatabase $__boundExcludeDatabase $__boundAllUserDatabases $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
