#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Configures Query Store options on one or more databases. Port of
/// public/Set-DbaDbQueryStoreOption.ps1; the workflow remains a module-scoped PowerShell
/// compatibility hop.
///
/// The hop runs once PER INSTANCE. The source foreaches $SqlInstance and keeps no cross-instance
/// state in that loop, and the loop emits a verbose line per database, so batching every instance
/// into a single hop would emit all of that verbose output ahead of all results instead of
/// interleaving it per instance the way the script function does.
///
/// Splitting per instance creates one problem this port has to solve. The source's two parameter
/// guards - "you must specify a database(s)" and "you must specify something to change" - sit ABOVE
/// the instance loop, so the function evaluates them ONCE PER RECORD and their `return` abandons the
/// whole record, every instance included. Run naively inside a per-instance hop they would warn once
/// per instance and abandon only that instance. So the guards are wrapped in `if ($__runGuards)`,
/// true only for the first element of the record, and a trip is reported back through the stop latch
/// that the hard Stop-Function already sets: the hop's finally reports it, and the C# loop breaks,
/// abandoning the remaining instances exactly as the function's `return` did.
///
/// That latch is deliberately NOT carried between RECORDS. The source has no Test-FunctionInterrupt
/// guard, so a later record re-enters the process body and re-evaluates the guards, warning again -
/// carrying the latch would suppress warnings the function actually repeats. It is scoped to one
/// record's instance loop and nothing more.
///
/// The source's begin block appends the three system databases to $ExcludeDatabase. That folds into
/// the top of the hop with no carry and no guard, because $ExcludeDatabase is mutated ONLY in begin
/// and only READ in the process body, and the hop re-binds it from the cmdlet property on every
/// invocation - so appending per hop yields the same array each time rather than compounding. (This
/// is the same shape as Test-DbaDbQueryStore MINUS that command's process-side append, which is what
/// forced a guarded carry there.)
///
/// Test-Bound cannot ride the hop - inside one the caller is the scriptblock, not this cmdlet - so
/// the single call site is flag-substituted. The ShouldProcess gates are routed to the OUTER cmdlet
/// so -Confirm's "Yes to All" answer survives across pipeline records instead of being forgotten by
/// a per-record inner runtime.
///
/// No local needs a cross-record carry: $server, $dbs, $db, $dbName and $query are each assigned and
/// read within one iteration ($query is reset to "" per database before being appended to).
///
/// The hop streams rather than buffers. This command MUTATES server state, and each emitted object
/// records a database whose Query Store settings were actually changed.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaDbQueryStoreOption", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(PSObject))]
public sealed class SetDbaDbQueryStoreOptionCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Only configure these databases.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>Skip these databases. The system databases are always added to this list.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Configure every database on the instance.</summary>
    [Parameter]
    public SwitchParameter AllDatabases { get; set; }

    /// <summary>The desired Query Store state.</summary>
    [Parameter(Position = 4)]
    [ValidateSet("ReadWrite", "ReadOnly", "Off")]
    public string[]? State { get; set; }

    /// <summary>Data flush interval, in seconds.</summary>
    [Parameter(Position = 5)]
    public long FlushInterval { get; set; }

    /// <summary>Statistics collection interval, in minutes.</summary>
    [Parameter(Position = 6)]
    public long CollectionInterval { get; set; }

    /// <summary>Maximum Query Store size, in MB.</summary>
    [Parameter(Position = 7)]
    public long MaxSize { get; set; }

    /// <summary>The query capture mode.</summary>
    [Parameter(Position = 8)]
    [ValidateSet("Auto", "All", "None", "Custom")]
    public string[]? CaptureMode { get; set; }

    /// <summary>The size-based cleanup mode.</summary>
    [Parameter(Position = 9)]
    [ValidateSet("Auto", "Off")]
    public string[]? CleanupMode { get; set; }

    /// <summary>Stale query threshold, in days.</summary>
    [Parameter(Position = 10)]
    public long StaleQueryThreshold { get; set; }

    /// <summary>Maximum plans retained per query.</summary>
    [Parameter(Position = 11)]
    public long MaxPlansPerQuery { get; set; }

    /// <summary>The wait statistics capture mode.</summary>
    [Parameter(Position = 12)]
    [ValidateSet("On", "Off")]
    public string[]? WaitStatsCaptureMode { get; set; }

    /// <summary>Custom capture policy: execution count.</summary>
    [Parameter(Position = 13)]
    public long CustomCapturePolicyExecutionCount { get; set; }

    /// <summary>Custom capture policy: total compile CPU time, in milliseconds.</summary>
    [Parameter(Position = 14)]
    public long CustomCapturePolicyTotalCompileCPUTimeMS { get; set; }

    /// <summary>Custom capture policy: total execution CPU time, in milliseconds.</summary>
    [Parameter(Position = 15)]
    public long CustomCapturePolicyTotalExecutionCPUTimeMS { get; set; }

    /// <summary>Custom capture policy: stale threshold, in hours.</summary>
    [Parameter(Position = 16)]
    public long CustomCapturePolicyStaleThresholdHours { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {

        // guardTripped is a LOCAL, not a field, and that is the point: it must abandon the rest of
        // THIS record's instances the way the function's `return` did, and must not leak into the
        // next record, where the function re-evaluates the guards and warns again.
        bool guardTripped = false;
        bool runGuards = true;

        foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
        {
            if (Interrupted || guardTripped)
                return;

            NestedCommand.InvokeScopedStreaming(this, item =>
            {
                if (item is not null && LanguagePrimitives.IsTrue(
                    item.Properties["__setDbaDbQueryStoreOptionState"]?.Value))
                {
                    if (LanguagePrimitives.IsTrue(item.Properties["GuardTripped"]?.Value))
                        guardTripped = true;
                    return;
                }
                if (item?.BaseObject is ErrorRecord nestedError)
                {
                    NestedCommand.RemoveDuplicateError(this, nestedError);
                    WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                    return;
                }
                WriteObject(item);
            }, BodyScript,
                new[] { instance }, SqlCredential, Database, ExcludeDatabase, AllDatabases, State,
                FlushInterval, CollectionInterval, MaxSize, CaptureMode, CleanupMode,
                StaleQueryThreshold, MaxPlansPerQuery, WaitStatsCaptureMode,
                CustomCapturePolicyExecutionCount, CustomCapturePolicyTotalCompileCPUTimeMS,
                CustomCapturePolicyTotalExecutionCPUTimeMS, CustomCapturePolicyStaleThresholdHours,
                EnableException.ToBool(), this, runGuards, TestBound(nameof(State)),
                NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
                NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));

            runGuards = false;
        }
    }

    // PS: the source's begin append followed by its process body VERBATIM. Substitutions only:
    // $Pscmdlet -> $__realCmdlet, the Test-Bound call site -> a flag, -FunctionName on
    // Stop-Function/Write-Message, and the two pre-loop guards wrapped in if ($__runGuards).
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $AllDatabases, $State, $FlushInterval, $CollectionInterval, $MaxSize, $CaptureMode, $CleanupMode, $StaleQueryThreshold, $MaxPlansPerQuery, $WaitStatsCaptureMode, $CustomCapturePolicyExecutionCount, $CustomCapturePolicyTotalCompileCPUTimeMS, $CustomCapturePolicyTotalExecutionCPUTimeMS, $CustomCapturePolicyStaleThresholdHours, $EnableException, $__realCmdlet, $__runGuards, $__boundState, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [object[]]$Database, [object[]]$ExcludeDatabase, $AllDatabases, [string[]]$State, [int64]$FlushInterval, [int64]$CollectionInterval, [int64]$MaxSize, [string[]]$CaptureMode, [string[]]$CleanupMode, [int64]$StaleQueryThreshold, [int64]$MaxPlansPerQuery, [string[]]$WaitStatsCaptureMode, [int64]$CustomCapturePolicyExecutionCount, [int64]$CustomCapturePolicyTotalCompileCPUTimeMS, [int64]$CustomCapturePolicyTotalExecutionCPUTimeMS, [int64]$CustomCapturePolicyStaleThresholdHours, $EnableException, $__realCmdlet, $__runGuards, $__boundState, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    try {

            $ExcludeDatabase += 'master', 'tempdb', "model"

        if ($__runGuards) {
                if (-not $Database -and -not $ExcludeDatabase -and -not $AllDatabases) {
                    Stop-Function -Message "You must specify a database(s) to execute against using either -Database, -ExcludeDatabase or -AllDatabases" -FunctionName Set-DbaDbQueryStoreOption
                    return
                }
    
                if (-not $State -and -not $FlushInterval -and -not $CollectionInterval -and -not $MaxSize -and -not $CaptureMode -and -not $CleanupMode -and -not $StaleQueryThreshold -and -not $MaxPlansPerQuery -and -not $WaitStatsCaptureMode -and -not $CustomCapturePolicyExecutionCount -and -not $CustomCapturePolicyTotalCompileCPUTimeMS -and -not $CustomCapturePolicyTotalExecutionCPUTimeMS -and -not $CustomCapturePolicyStaleThresholdHours) {
                    Stop-Function -Message "You must specify something to change." -FunctionName Set-DbaDbQueryStoreOption
                    return
                }
        }

            foreach ($instance in $SqlInstance) {
                try {
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 13
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaDbQueryStoreOption
                }

                if ($CaptureMode -contains "Custom" -and $server.VersionMajor -lt 15) {
                    Stop-Function -Message "Custom capture mode can onlly be set in SQL Server 2019 and above" -Continue -FunctionName Set-DbaDbQueryStoreOption
                }

                if (($CustomCapturePolicyExecutionCount -or $CustomCapturePolicyTotalCompileCPUTimeMS -or $CustomCapturePolicyTotalExecutionCPUTimeMS -or $CustomCapturePolicyStaleThresholdHours) -and $server.VersionMajor -lt 15) {
                    Write-Message -Level Warning -Message "Custom Capture Policies can only be set in SQL Server 2019 and above. These options will be skipped for $instance" -FunctionName Set-DbaDbQueryStoreOption -ModuleName "dbatools"
                }

                # We have to exclude all the system databases since they cannot have the Query Store feature enabled
                $dbs = Get-DbaDatabase -SqlInstance $server -ExcludeDatabase $ExcludeDatabase -Database $Database | Where-Object { $_.IsAccessible -and !$_.IsDatabaseSnapshot }

                foreach ($db in $dbs) {
                    $dbName = $db.Name
                    Write-Message -Level Verbose -Message "Processing $dbName on $instance" -FunctionName Set-DbaDbQueryStoreOption -ModuleName "dbatools"

                    if ($db.IsAccessible -eq $false) {
                        Write-Message -Level Warning -Message "The database $db on server $instance is not accessible. Skipping database." -FunctionName Set-DbaDbQueryStoreOption -ModuleName "dbatools"
                        continue
                    }

                    if ($State) {
                        if ($__realCmdlet.ShouldProcess("$db on $instance", "Changing DesiredState to $state")) {
                            $db.QueryStoreOptions.DesiredState = $State
                            $db.QueryStoreOptions.Alter()
                            $db.QueryStoreOptions.Refresh()
                        }
                    }

                    if ($db.QueryStoreOptions.DesiredState -eq "Off" -and (-not $__boundState)) {
                        Write-Message -Level Warning -Message "State is set to Off; cannot change values. Please update State to ReadOnly or ReadWrite." -FunctionName Set-DbaDbQueryStoreOption -ModuleName "dbatools"
                        continue
                    }

                    if ($FlushInterval) {
                        if ($__realCmdlet.ShouldProcess("$db on $instance", "Changing DataFlushIntervalInSeconds to $FlushInterval")) {
                            $db.QueryStoreOptions.DataFlushIntervalInSeconds = $FlushInterval
                        }
                    }

                    if ($CollectionInterval) {
                        if ($__realCmdlet.ShouldProcess("$db on $instance", "Changing StatisticsCollectionIntervalInMinutes to $CollectionInterval")) {
                            $db.QueryStoreOptions.StatisticsCollectionIntervalInMinutes = $CollectionInterval
                        }
                    }

                    if ($MaxSize) {
                        if ($__realCmdlet.ShouldProcess("$db on $instance", "Changing MaxStorageSizeInMB to $MaxSize")) {
                            $db.QueryStoreOptions.MaxStorageSizeInMB = $MaxSize
                        }
                    }

                    if ($CaptureMode) {
                        if ($__realCmdlet.ShouldProcess("$db on $instance", "Changing QueryCaptureMode to $CaptureMode")) {
                            $db.QueryStoreOptions.QueryCaptureMode = $CaptureMode
                        }
                    }

                    if ($CleanupMode) {
                        if ($__realCmdlet.ShouldProcess("$db on $instance", "Changing SizeBasedCleanupMode to $CleanupMode")) {
                            $db.QueryStoreOptions.SizeBasedCleanupMode = $CleanupMode
                        }
                    }

                    if ($StaleQueryThreshold) {
                        if ($__realCmdlet.ShouldProcess("$db on $instance", "Changing StaleQueryThresholdInDays to $StaleQueryThreshold")) {
                            $db.QueryStoreOptions.StaleQueryThresholdInDays = $StaleQueryThreshold
                        }
                    }

                    $query = ""

                    if ($server.VersionMajor -ge 14) {
                        if ($MaxPlansPerQuery) {
                            if ($__realCmdlet.ShouldProcess("$db on $instance", "Changing MaxPlansPerQuery to $($MaxPlansPerQuery)")) {
                                $query += "ALTER DATABASE [$dbName] SET QUERY_STORE = ON (MAX_PLANS_PER_QUERY = $($MaxPlansPerQuery)); "
                            }
                        }

                        if ($WaitStatsCaptureMode) {
                            if ($__realCmdlet.ShouldProcess("$db on $instance", "Changing WaitStatsCaptureMode to $($WaitStatsCaptureMode)")) {
                                if ($WaitStatsCaptureMode -eq "ON" -or $WaitStatsCaptureMode -eq "OFF") {
                                    $query += "ALTER DATABASE [$dbName] SET QUERY_STORE = ON (WAIT_STATS_CAPTURE_MODE = $($WaitStatsCaptureMode)); "
                                }
                            }
                        }
                    }

                    if ($server.VersionMajor -ge 15) {
                        if ($db.QueryStoreOptions.QueryCaptureMode -eq "CUSTOM") {
                            if ($CustomCapturePolicyStaleThresholdHours) {
                                if ($__realCmdlet.ShouldProcess("$db on $instance", "Changing CustomCapturePolicyStaleThresholdHours to $($CustomCapturePolicyStaleThresholdHours)")) {
                                    $query += "ALTER DATABASE [$dbName] SET QUERY_STORE = ON ( QUERY_CAPTURE_POLICY = ( STALE_CAPTURE_POLICY_THRESHOLD = $($CustomCapturePolicyStaleThresholdHours) HOURS)); "
                                }
                            }

                            if ($CustomCapturePolicyExecutionCount) {
                                if ($__realCmdlet.ShouldProcess("$db on $instance", "Changing CustomCapturePolicyExecutionCount to $($CustomCapturePolicyExecutionCount)")) {
                                    $query += "ALTER DATABASE [$dbName] SET QUERY_STORE = ON (QUERY_CAPTURE_POLICY = (EXECUTION_COUNT = $($CustomCapturePolicyExecutionCount))); "
                                }
                            }
                            if ($CustomCapturePolicyTotalCompileCPUTimeMS) {
                                if ($__realCmdlet.ShouldProcess("$db on $instance", "Changing CustomCapturePolicyTotalCompileCPUTimeMS to $($CustomCapturePolicyTotalCompileCPUTimeMS)")) {
                                    $query += "ALTER DATABASE [$dbName] SET QUERY_STORE = ON (QUERY_CAPTURE_POLICY = (TOTAL_COMPILE_CPU_TIME_MS = $($CustomCapturePolicyTotalCompileCPUTimeMS))); "
                                }
                            }

                            if ($CustomCapturePolicyTotalExecutionCPUTimeMS) {
                                if ($__realCmdlet.ShouldProcess("$db on $instance", "Changing CustomCapturePolicyTotalExecutionCPUTimeMS to $($CustomCapturePolicyTotalExecutionCPUTimeMS)")) {
                                    $query += "ALTER DATABASE [$dbName] SET QUERY_STORE = ON (QUERY_CAPTURE_POLICY = (TOTAL_EXECUTION_CPU_TIME_MS = $($CustomCapturePolicyTotalExecutionCPUTimeMS))); "
                                }
                            }
                        }
                    }

                    # Alter the Query Store Configuration
                    if ($__realCmdlet.ShouldProcess("$db on $instance", "Altering Query Store configuration on database")) {
                        try {
                            $db.QueryStoreOptions.Alter()
                            $db.Alter()
                            $db.Refresh()

                            if ($query -ne "") {
                                $db.Query($query, $dbName)
                            }
                        } catch {
                            Stop-Function -Message "Could not modify configuration." -Category InvalidOperation -InnerErrorRecord $_ -Target $db -Continue -FunctionName Set-DbaDbQueryStoreOption
                        }
                    }

                    if ($__realCmdlet.ShouldProcess("$db on $instance", "Getting results from Get-DbaDbQueryStoreOption")) {
                        Get-DbaDbQueryStoreOption -SqlInstance $server -Database $dbName -Verbose:$false
                    }
                }
            }

    } finally {
        # The hard guards above set the graceful-stop latch before returning. Report it so the C#
        # instance loop can abandon this record's remaining instances, exactly as the function's
        # `return` did. Emitted from a finally because those guards return early.
        [pscustomobject]@{
            __setDbaDbQueryStoreOptionState = $true
            GuardTripped                    = [bool](Test-FunctionInterrupt)
        }
    }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $AllDatabases $State $FlushInterval $CollectionInterval $MaxSize $CaptureMode $CleanupMode $StaleQueryThreshold $MaxPlansPerQuery $WaitStatsCaptureMode $CustomCapturePolicyExecutionCount $CustomCapturePolicyTotalCompileCPUTimeMS $CustomCapturePolicyTotalExecutionCPUTimeMS $CustomCapturePolicyStaleThresholdHours $EnableException $__realCmdlet $__runGuards $__boundState $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
