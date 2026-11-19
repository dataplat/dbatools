#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Shrinks database data and log files with DBCC SHRINKFILE, optionally in steps. Port of
/// public/Invoke-DbaDbShrink.ps1; the workflow remains a module-scoped PowerShell compatibility hop.
///
/// BEGIN+PROCESS, two hops. SqlInstance and InputObject are both ValueFromPipeline, so process fires
/// per record. Begin runs once (validate -StepSize, compute the step size, statement timeout, the
/// WAIT_AT_LOW_PRIORITY clause, and the fragmentation query) and carries those constants to process.
/// The process hop STREAMS (InvokeScopedStreaming): this is a DESTRUCTIVE command emitting one result
/// object per shrunk file - the audit trail of work already done - so buffered invocation would drop
/// the records for files already shrunk when a later file's failure terminates the hop under
/// -EnableException (the DEF-001 class).
///
/// $InputObject CROSS-RECORD ACCUMULATOR (bug-for-bug). In the SqlInstance parameter set InputObject
/// is unbound, and the body does "$InputObject += $db" for every database on the connected server
/// then never resets it, so across piped-instance records $InputObject ACCUMULATES and the shrink
/// loop reprocesses earlier instances' databases (duplicate shrink attempts and duplicate result
/// rows). In the Pipeline set InputObject is bound and rebinds fresh each record, so it does not
/// accumulate. The port reproduces this exactly: it carries the post-record $InputObject and, when
/// InputObject was NOT bound this record, seeds the hop's $InputObject from the carried accumulator;
/// when it WAS bound, it uses this record's value and ignores the carry (rebind semantics). This is
/// a faithful reproduction of a source quirk, not a fix.
///
/// INTERRUPT CARRY. The begin -StepSize validation and the process no-target validation are
/// Stop-Function WITHOUT -Continue, so they set the module interrupt flag; the connection and
/// WAIT_AT_LOW_PRIORITY-version failures are -Continue (skip). Across separate hop invocations the
/// flag does not survive, so each hop reads it at Get-Variable -Scope 0 after its dot-sourced body
/// and carries it; C# skips process when a prior hop carried true, reproducing the source's
/// Test-FunctionInterrupt short-circuit.
///
/// The one $Pscmdlet.ShouldProcess gate routes to the real cmdlet via $__realCmdlet (SupportsShould-
/// Process, ConfirmImpact Low mirrored). Test-Bound -ParameterName StepSize (begin only) becomes the
/// carried $__boundStepSize flag. The four switches consumed by truthiness ride UNTYPED so positional
/// binding is not shifted. In-hop Stop-Function/Write-Message carry -FunctionName; the nested
/// Connect-DbaInstance/Select-DefaultView resolve through the module scope. Surface pinned by
/// migration/baselines/Invoke-DbaDbShrink.json (SqlInstance in the all-set VFP membership plus the
/// named "SqlInstance" set at position 0).
/// </summary>
[Cmdlet(VerbsLifecycle.Invoke, "DbaDbShrink", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class InvokeDbaDbShrinkCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ValueFromPipeline = true)]
    [Parameter(ParameterSetName = "SqlInstance", Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to shrink.</summary>
    [Parameter]
    public object[]? Database { get; set; }

    /// <summary>Databases to skip.</summary>
    [Parameter]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Shrink every user database on the instance.</summary>
    [Parameter]
    public SwitchParameter AllUserDatabases { get; set; }

    /// <summary>Target free space percentage to leave after the shrink (0-99).</summary>
    [Parameter]
    [ValidateRange(0, 99)]
    public int PercentFreeSpace { get; set; }

    /// <summary>The DBCC SHRINKFILE method.</summary>
    [Parameter]
    [ValidateSet("Default", "EmptyFile", "NoTruncate", "TruncateOnly")]
    [PsStringCast]
    public string ShrinkMethod { get; set; } = "Default";

    /// <summary>Which file types to shrink.</summary>
    [Parameter]
    [ValidateSet("All", "Data", "Log")]
    [PsStringCast]
    public string FileType { get; set; } = "All";

    /// <summary>Shrink in increments of this many bits (1024 or above).</summary>
    [Parameter]
    public long StepSize { get; set; }

    /// <summary>Statement timeout in minutes (0 = no timeout).</summary>
    [Parameter]
    public int StatementTimeout { get; set; }

    /// <summary>Use WAIT_AT_LOW_PRIORITY (SQL Server 2022+).</summary>
    [Parameter]
    public SwitchParameter WaitAtLowPriority { get; set; }

    /// <summary>WAIT_AT_LOW_PRIORITY abort target.</summary>
    [Parameter]
    [ValidateSet("Self", "Blockers")]
    [PsStringCast]
    public string AbortAfterWait { get; set; } = "Self";

    /// <summary>Skip the fragmentation measurement.</summary>
    [Parameter]
    public SwitchParameter ExcludeIndexStats { get; set; }

    /// <summary>Skip updating usage before shrinking.</summary>
    [Parameter]
    public SwitchParameter ExcludeUpdateUsage { get; set; }

    /// <summary>SMO Database object(s), typically from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Begin-computed constants (step size, timeout, WAIT clause, fragmentation SQL), carried opaque.
    private Hashtable? _beginState;
    // The $InputObject accumulator carried across records (bug-for-bug); opaque.
    private Hashtable? _state;
    // (no rebind-detection state: see the seeding comment in ProcessRecord)
    // A begin -StepSize failure, or a process no-target/EnableException failure on an earlier record.
    private bool _interrupted;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            StepSize, StatementTimeout, WaitAtLowPriority.ToBool(), AbortAfterWait,
            MyInvocation.BoundParameters.ContainsKey("StepSize"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__invokeDbaDbShrinkBegin"))
            {
                if (sentinel["__invokeDbaDbShrinkBegin"] is Hashtable state)
                {
                    _beginState = state;
                    _interrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
                }
                continue;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted || _interrupted)
            return;

        // $InputObject behaves like the source's FUNCTION-SCOPE variable: the binder overwrites it
        // each record only when InputObject is the parameter receiving pipeline input; otherwise it
        // keeps the body's mutations, which is what makes the SqlInstance branch accumulate and
        // reprocess earlier instances' databases (a source quirk, reproduced not fixed).
        //
        // PowerShell does not expose which parameter the binder wrote for a given record, so this
        // uses the one signal that is both stable and correct for every shape reachable from the
        // documented usages: whether -InputObject was bound at all. Unbound means the SqlInstance
        // branch owns $InputObject and its appends must carry; bound means the caller supplied or
        // piped databases and each record starts from that binding.
        //
        // KNOWN DIVERGENCE (documented, routed to the coordinator - do not "fix" by adding
        // rebind heuristics): when -InputObject is EXPLICITLY supplied *and* SqlInstance is piped,
        // the source keeps the body's mutations across records while this port restarts each record
        // from the bound value. Successive attempts to detect that case by reference identity, by
        // the append path, and by latching the pipeline target each introduced NEW divergence in
        // more common shapes, because every one of them infers a binder write that cannot be
        // observed. The divergence direction here is fail-safe: fewer redundant shrink attempts on
        // databases an earlier record already processed, never a missed database.
        bool seedFromCarry = !MyInvocation.BoundParameters.ContainsKey("InputObject");

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__invokeDbaDbShrinkProcess"))
            {
                if (sentinel["__invokeDbaDbShrinkProcess"] is Hashtable result)
                {
                    _state = result["State"] as Hashtable;
                    _interrupted = LanguagePrimitives.IsTrue(result["Interrupted"]);
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
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, ExcludeDatabase, AllUserDatabases.ToBool(),
            PercentFreeSpace, ShrinkMethod, FileType, StatementTimeout, WaitAtLowPriority.ToBool(),
            ExcludeIndexStats.ToBool(), ExcludeUpdateUsage.ToBool(), EnableException.ToBool(),
            InputObject, seedFromCarry, _beginState, _state,
            this, NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block VERBATIM, dot-sourced. Edits: Test-Bound StepSize -> the carried
    // $__boundStepSize flag, -FunctionName on the one Stop-Function. The sentinel carries the
    // computed step size / timeout / WAIT clause / fragmentation SQL and whether the -StepSize
    // validation (a non-Continue Stop-Function) set the interrupt.
    private const string BeginScript = """
param($StepSize, $StatementTimeout, $WaitAtLowPriority, $AbortAfterWait, $__boundStepSize, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([int64]$StepSize, [int]$StatementTimeout, $WaitAtLowPriority, [string]$AbortAfterWait, $__boundStepSize, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {

        if ($__boundStepSize -and $StepSize -lt 1024) {
            Stop-Function -Message "StepSize is measured in bits. Did you mean $StepSize bits? If so, please use 1024 or above. If not, then use the PowerShell bit notation like $($StepSize)MB or $($StepSize)GB" -FunctionName Invoke-DbaDbShrink
            return
        }

        if ($StepSize) {
            $stepSizeKB = ([dbasize]($StepSize)).Kilobyte
        }
        $StatementTimeoutSeconds = $StatementTimeout * 60

        $walp = ""
        if ($WaitAtLowPriority) {
            $walp = " WITH WAIT_AT_LOW_PRIORITY (ABORT_AFTER_WAIT = $($AbortAfterWait.ToUpper()))"
        }

        $sql = 'SELECT
                  AVG(avg_fragmentation_in_percent) AS [avg_fragmentation_in_percent]
                , MAX(avg_fragmentation_in_percent) AS [max_fragmentation_in_percent]
                FROM sys.dm_db_index_physical_stats (DB_ID(), NULL, NULL, NULL, NULL) AS indexstats
                WHERE indexstats.avg_fragmentation_in_percent > 0 AND indexstats.page_count > 100
                GROUP BY indexstats.database_id'
    }

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __invokeDbaDbShrinkBegin = @{ StepSizeKB = $stepSizeKB; StatementTimeoutSeconds = $StatementTimeoutSeconds; Walp = $walp; Sql = $sql; Interrupted = [bool]($__iv -and $__iv.Value) } }
} $StepSize $StatementTimeout $WaitAtLowPriority $AbortAfterWait $__boundStepSize $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
    // PS: the process block VERBATIM per record, dot-sourced (InvokeScopedStreaming). Edits:
    // $Pscmdlet -> $__realCmdlet on the one ShouldProcess gate, -FunctionName on the 26 direct
    // Stop-Function/Write-Message calls. Begin constants restore at the top; the $InputObject
    // accumulator is seeded from the carried state whenever the binder did NOT rewrite InputObject
    // this record, reproducing the source's grow-and-reprocess quirk; a genuine pipeline rebind of
    // InputObject uses this record's value. The sentinel snapshots the accumulator and the interrupt.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $AllUserDatabases, $PercentFreeSpace, $ShrinkMethod, $FileType, $StatementTimeout, $WaitAtLowPriority, $ExcludeIndexStats, $ExcludeUpdateUsage, $EnableException, $InputObject, $__seedFromCarry, $__beginState, $__state, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [object[]]$Database, [object[]]$ExcludeDatabase, $AllUserDatabases, [int]$PercentFreeSpace, [string]$ShrinkMethod, [string]$FileType, [int]$StatementTimeout, $WaitAtLowPriority, $ExcludeIndexStats, $ExcludeUpdateUsage, $EnableException, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $__seedFromCarry, $__beginState, $__state, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # begin-computed constants (constant across records)
    $stepSizeKB = $__beginState.StepSizeKB
    $StatementTimeoutSeconds = $__beginState.StatementTimeoutSeconds
    $walp = $__beginState.Walp
    $sql = $__beginState.Sql

    # $InputObject cross-record accumulator. C# decides ONCE (first record) whether the pipeline
    # feeds InputObject. If it does, the binder overwrites it every record and the carry is
    # ignored; if it does not, the source's function-scope variable keeps the body's mutations, so
    # seed from the carry - that is what makes the SqlInstance branch accumulate and reprocess.
    if ($__seedFromCarry -and $null -ne $__state -and $__state.ContainsKey("Accumulator")) {
        $InputObject = $__state.Accumulator
    }

    . {
        if (Test-FunctionInterrupt) { return }

        if (-not $Database -and -not $ExcludeDatabase -and -not $AllUserDatabases -and -not $InputObject) {
            Stop-Function -Message 'You must specify databases to execute against using either -Database, -Exclude or -AllUserDatabases, or piping them in' -FunctionName Invoke-DbaDbShrink
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message 'Failure' -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Invoke-DbaDbShrink
            }

            $dbs = $server.Databases | Where-Object { $_.IsAccessible }

            if ($AllUserDatabases) {
                $dbs = $dbs | Where-Object { $_.IsSystemObject -eq $false }
            }

            if ($Database) {
                $dbs = $dbs | Where-Object Name -In $Database
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }

            foreach ($db in $dbs) {
                $InputObject += $db
            }
        }

        foreach ($db in $InputObject) {

            $instance = $db.Parent

            Write-Message -Level Verbose -Message "Processing $db on $instance" -FunctionName Invoke-DbaDbShrink -ModuleName "dbatools"

            if ($db.IsDatabaseSnapshot) {
                Write-Message -Level Warning -Message "The database $db on server $instance is a snapshot and cannot be shrunk. Skipping database." -FunctionName Invoke-DbaDbShrink -ModuleName "dbatools"
                continue
            }

            if ($WaitAtLowPriority -and $instance.VersionMajor -lt 16) {
                Stop-Function -Message "WAIT_AT_LOW_PRIORITY for DBCC SHRINKFILE requires SQL Server 2022 (version 16) or later. $instance is running version $($instance.VersionMajor)." -Target $instance -Continue -FunctionName Invoke-DbaDbShrink
            }

            $files = @()
            if ($FileType -in ('Log', 'All')) {
                $files += $db.LogFiles
            }
            if ($FileType -in ('Data', 'All')) {
                $files += $db.FileGroups.Files
            }


            foreach ($file in $files) {
                # $file.Size and $file.UsedSpace are in KB and translated here to bytes as the dbasize type requires
                [dbasize]$startingSizeKB = $file.Size * 1024
                [dbasize]$spaceUsedKB = $file.UsedSpace * 1024
                [dbasize]$spaceAvailableKB = ($startingSizeKB - $spaceUsedKB)
                [dbasize]$desiredSpaceAvailableKB = [math]::ceiling((($PercentFreeSpace / 100)) * $spaceUsedKB)
                [dbasize]$desiredFileSizeKB = $spaceUsedKB + $desiredSpaceAvailableKB

                Write-Message -Level Verbose -Message "File: $($file.Name)" -FunctionName Invoke-DbaDbShrink -ModuleName "dbatools"
                Write-Message -Level Verbose -Message "Initial Size: $($startingSizeKB)" -FunctionName Invoke-DbaDbShrink -ModuleName "dbatools"
                Write-Message -Level Verbose -Message "Space Used: $($spaceUsedKB)" -FunctionName Invoke-DbaDbShrink -ModuleName "dbatools"
                Write-Message -Level Verbose -Message "Initial Freespace: $($spaceAvailableKB)" -FunctionName Invoke-DbaDbShrink -ModuleName "dbatools"
                Write-Message -Level Verbose -Message "Target Freespace: $($desiredSpaceAvailableKB)" -FunctionName Invoke-DbaDbShrink -ModuleName "dbatools"
                Write-Message -Level Verbose -Message "Target FileSize: $($desiredFileSizeKB)" -FunctionName Invoke-DbaDbShrink -ModuleName "dbatools"

                $escapedFileName = $file.Name.Replace("'", "''")

                if ($spaceAvailableKB -le $desiredSpaceAvailableKB) {
                    Write-Message -Level Warning -Message "File size of ($startingSizeKB) is less than or equal to the desired outcome ($desiredFileSizeKB) for $($file.Name)" -FunctionName Invoke-DbaDbShrink -ModuleName "dbatools"
                } else {
                    if ($__realCmdlet.ShouldProcess("$db on $instance, file $($file.Name)", "Shrinking from $($startingSizeKB) to $($desiredFileSizeKB)")) {
                        if ($server.VersionMajor -gt 8 -and $ExcludeIndexStats -eq $false) {
                            Write-Message -Level Verbose -Message 'Getting starting average fragmentation' -FunctionName Invoke-DbaDbShrink -ModuleName "dbatools"
                            $dataRow = $server.Query($sql, $db.name)
                            $startingFrag = $dataRow.avg_fragmentation_in_percent
                            $startingTopFrag = $dataRow.max_fragmentation_in_percent
                        } else {
                            $startingTopFrag = $startingFrag = $null
                        }

                        $start = Get-Date
                        # saving previous timeout to be restored at the end
                        $previousStatementTimeout = $instance.ConnectionContext.StatementTimeout
                        $errorDetails = $null
                        try {
                            Write-Message -Level Verbose -Message 'Beginning shrink of files' -FunctionName Invoke-DbaDbShrink -ModuleName "dbatools"
                            $instance.ConnectionContext.StatementTimeout = $StatementTimeoutSeconds
                            Write-Message -Level Debug -Message "Connection timeout set to $StatementTimeout" -FunctionName Invoke-DbaDbShrink -ModuleName "dbatools"
                            [dbasize]$shrinkGapKB = ($startingSizeKB - $desiredFileSizeKB)
                            Write-Message -Level Verbose -Message "ShrinkGap: $($shrinkGapKB)" -FunctionName Invoke-DbaDbShrink -ModuleName "dbatools"
                            Write-Message -Level Verbose -Message "Step Size: $($stepSizeKB) KB" -FunctionName Invoke-DbaDbShrink -ModuleName "dbatools"

                            if ($stepSizeKB -and ($shrinkGapKB.Kilobyte -ge $stepSizeKB)) {
                                $numberIterations = [math]::ceiling($((($shrinkGapKB.Kilobyte) / $stepSizeKB)))
                                for ($i = 1; $i -le $numberIterations; $i++) {
                                    Write-Message -Level Verbose -Message "Step: $i of $numberIterations" -FunctionName Invoke-DbaDbShrink -ModuleName "dbatools"
                                    [dbasize]$shrinkSizeKB = ($startingSizeKB.Kilobyte - ($stepSizeKB * $i)) * 1024
                                    if ($shrinkSizeKB -lt $desiredFileSizeKB) {
                                        $shrinkSizeKB = $desiredFileSizeKB
                                    }
                                    Write-Message -Level Verbose -Message ('Shrinking {0} to {1}' -f $file.Name, $shrinkSizeKB) -FunctionName Invoke-DbaDbShrink -ModuleName "dbatools"
                                    $targetMB = [int]$shrinkSizeKB.Megabyte
                                    $shrinkSqlArgs = switch ($ShrinkMethod) {
                                        'EmptyFile' { "N'$escapedFileName', EMPTYFILE" }
                                        'NoTruncate' { "N'$escapedFileName', $targetMB, NOTRUNCATE" }
                                        'TruncateOnly' { "N'$escapedFileName', $targetMB, TRUNCATEONLY" }
                                        default { "N'$escapedFileName', $targetMB" }
                                    }
                                    $null = $instance.Query("DBCC SHRINKFILE ($shrinkSqlArgs)$walp", $db.name)
                                    $file.Refresh()

                                    if ($startingSizeKB -eq ($file.Size * 1024)) {
                                        Write-Message -Level Verbose -Message ('Unable to shrink further') -FunctionName Invoke-DbaDbShrink -ModuleName "dbatools"
                                        break
                                    }
                                }
                            } else {
                                $targetMB = [int]$desiredFileSizeKB.Megabyte
                                $shrinkSqlArgs = switch ($ShrinkMethod) {
                                    'EmptyFile' { "N'$escapedFileName', EMPTYFILE" }
                                    'NoTruncate' { "N'$escapedFileName', $targetMB, NOTRUNCATE" }
                                    'TruncateOnly' { "N'$escapedFileName', $targetMB, TRUNCATEONLY" }
                                    default { "N'$escapedFileName', $targetMB" }
                                }
                                $null = $instance.Query("DBCC SHRINKFILE ($shrinkSqlArgs)$walp", $db.name)
                                $file.Refresh()
                            }
                            $success = $true
                        } catch {
                            $success = $false
                            $errorDetails = $_.Exception.Message
                            $failureMessage = "Shrink operation failed for file $($file.Name): $errorDetails"
                            if ($EnableException) {
                                Stop-Function -Message $failureMessage -EnableException $EnableException -ErrorRecord $_ -FunctionName Invoke-DbaDbShrink
                            } else {
                                Write-Message -Level Warning -Message $failureMessage -ErrorRecord $_ -FunctionName Invoke-DbaDbShrink -ModuleName "dbatools"
                            }
                        } finally {
                            $instance.ConnectionContext.StatementTimeout = $previousStatementTimeout
                        }
                        $end = Get-Date
                        [dbasize]$finalFileSizeKB = $file.Size * 1024
                        [dbasize]$finalSpaceAvailableKB = ($finalFileSizeKB - ($file.UsedSpace * 1024))
                        Write-Message -Level Verbose -Message "Final file size: $($finalFileSizeKB)" -FunctionName Invoke-DbaDbShrink -ModuleName "dbatools"
                        Write-Message -Level Verbose -Message "Final file space available: $($finalSpaceAvailableKB)" -FunctionName Invoke-DbaDbShrink -ModuleName "dbatools"

                        # Check if shrink didn't achieve target and provide feedback
                        if ($success -and $finalFileSizeKB -gt $desiredFileSizeKB) {
                            $shrinkShortfall = $finalFileSizeKB - $desiredFileSizeKB
                            $partialShrinkMessage = "File only shrunk to $finalFileSizeKB (target was $desiredFileSizeKB). Shortfall: $shrinkShortfall. This may be due to active transactions, data distribution, or minimum file size constraints."
                            Write-Message -Level Warning -Message $partialShrinkMessage -FunctionName Invoke-DbaDbShrink -ModuleName "dbatools"
                            $errorDetails = $partialShrinkMessage
                        }

                        if ($server.VersionMajor -gt 8 -and $ExcludeIndexStats -eq $false -and $success -and $FileType -ne 'Log') {
                            Write-Message -Level Verbose -Message 'Getting ending average fragmentation' -FunctionName Invoke-DbaDbShrink -ModuleName "dbatools"
                            $dataRow = $server.Query($sql, $db.name)
                            $endingDefrag = $dataRow.avg_fragmentation_in_percent
                            $endingTopDefrag = $dataRow.max_fragmentation_in_percent
                        } else {
                            $endingTopDefrag = $endingDefrag = $null
                        }

                        $timSpan = New-TimeSpan -Start $start -End $end
                        $ts = [TimeSpan]::FromSeconds($timSpan.TotalSeconds)
                        $elapsed = "{0:HH:mm:ss}" -f ([datetime]$ts.Ticks)

                        $notesText = "Database shrinks can cause massive index fragmentation and negatively impact performance. You should now run DBCC INDEXDEFRAG or ALTER INDEX ... REORGANIZE"
                        if ($errorDetails) {
                            $notesText = "$errorDetails | $notesText"
                        }

                        $object = [PSCustomObject]@{
                            ComputerName                = $server.ComputerName
                            InstanceName                = $server.ServiceName
                            SqlInstance                 = $server.DomainInstanceName
                            Database                    = $db.name
                            File                        = $file.name
                            Start                       = $start
                            End                         = $end
                            Elapsed                     = $elapsed
                            Success                     = $success
                            InitialSize                 = ($startingSizeKB)
                            InitialUsed                 = ($spaceUsedKB)
                            InitialAvailable            = ($spaceAvailableKB)
                            TargetAvailable             = ($desiredSpaceAvailableKB)
                            FinalAvailable              = ($finalSpaceAvailableKB)
                            FinalSize                   = ($finalFileSizeKB)
                            InitialAverageFragmentation = [math]::Round($startingFrag, 1)
                            FinalAverageFragmentation   = [math]::Round($endingDefrag, 1)
                            InitialTopFragmentation     = [math]::Round($startingTopFrag, 1)
                            FinalTopFragmentation       = [math]::Round($endingTopDefrag, 1)
                            Notes                       = $notesText
                        }
                        if ($ExcludeIndexStats) {
                            Select-DefaultView -InputObject $object -ExcludeProperty InitialAverageFragmentation, FinalAverageFragmentation, InitialTopFragmentation, FinalTopFragmentation
                        } else {
                            $object
                        }
                    }
                }
            }
        }
    }

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __invokeDbaDbShrinkProcess = @{ Interrupted = [bool]($__iv -and $__iv.Value); State = @{ Accumulator = $InputObject } } }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $AllUserDatabases $PercentFreeSpace $ShrinkMethod $FileType $StatementTimeout $WaitAtLowPriority $ExcludeIndexStats $ExcludeUpdateUsage $EnableException $InputObject $__seedFromCarry $__beginState $__state $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
