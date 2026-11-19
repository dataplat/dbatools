#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Tests the status of log shipping for databases on one or more instances.
/// Port of public/Test-DbaDbLogShipStatus.ps1; surface pinned by
/// migration/baselines/Test-DbaDbLogShipStatus.json.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaDbLogShipStatus")]
public sealed class TestDbaDbLogShipStatusCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server instance or instances to test.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Only test the specified database(s).</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>Exclude the specified database(s).</summary>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? ExcludeDatabase { get; set; }

    /// <summary>Return a condensed default view.</summary>
    [Parameter]
    public SwitchParameter Simple { get; set; }

    /// <summary>Only return rows for the primary instance.</summary>
    [Parameter]
    public SwitchParameter Primary { get; set; }

    /// <summary>Only return rows for the secondary instance.</summary>
    [Parameter]
    public SwitchParameter Secondary { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        base.BeginProcessing();

        // SEPARATE BEGIN HOP (the RemoveDbaDbLogShipping pattern). The source's begin block builds
        // the query string $sql from $Database/$ExcludeDatabase AND emits a Write-Message -Level
        // Debug of $sql ONCE. The process block reads $sql at :222 ($server.Query($sql)). Folding
        // begin into the process hop would rebuild $sql and re-emit the Debug message PER PIPED
        // RECORD - an observable divergence. So begin runs ONCE here and harvests $sql into _state.
        // No ShouldProcess anywhere, so no prompt-state transplant; no C1 assert needed.
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            Database, ExcludeDatabase,
            EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w4067State"))
            {
                _state = sentinel["__w4067State"] as Hashtable;
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
        if (Interrupted)
        {
            return;
        }

        // WHOLE-RECORD hop. Cross-record state rides the __w4067State sentinel and is re-updated
        // each record: the begin-built $sql (from the begin hop, constant thereafter) PLUS the
        // three timestamp leaks $lastBackup/$lastCopy/$lastRestore (codex-caught DEF-012: assigned
        // only in the Status-in-0,1 branch but read unconditionally at output, so they leak the
        // prior record's values in the source's shared process scope - carried bug-for-bug). NO
        // Test-Bound (no bound flags), NO ShouldProcess (no transplant/gate), NO param carry.
        // $Database/$ExcludeDatabase are not read in process. Switches Simple/Primary/Secondary and
        // EnableException are passed UNTYPED/.ToBool() (switch-shift rule). $instance/$server/
        // $result/$results/$statusDetails/$object are process-locals reset before use each record.
        //
        // [DEF-001] CLOSED by adopting A's shipped NestedCommand.InvokeScopedStreaming (ab7492c):
        // this row emits per-result/per-instance and could lose an earlier emit if a later instance
        // threw terminating under -EnableException, and a downstream `| Select -First 1` stopped the
        // source but not the buffered port. Streaming writes each record as produced. Safe on this
        // READ-ONLY row (no ShouldProcess gate, so none of the -WhatIf-transcript interaction I
        // measured on the gate rows). The state sentinel rides the callback as the last emitted item.
        // [T8/DEF-002] on Database/ExcludeDatabase [string[]] CLOSED via [PsStringArrayCast].
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w4067State"))
            {
                _state = sentinel["__w4067State"] as Hashtable;
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
            SqlInstance, SqlCredential, Simple.ToBool(), Primary.ToBool(), Secondary.ToBool(),
            _state,
            EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source BEGIN block VERBATIM, byte-proven against source lines 138-199 after reversing
    // the single direct-Write-Message DEF-006 rewrite (the :199 Debug carries a # SOURCE: marker;
    // -FunctionName + -ModuleName "dbatools"). $sql is built inside the dot-block (dot-sourcing
    // keeps it in scope) and harvested into the sentinel after.
    private const string BeginScript = """
param($Database, $ExcludeDatabase, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string[]]$Database, [string[]]$ExcludeDatabase, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        # Setup the query
        [string[]]$query = "
IF ( OBJECT_ID('tempdb..#logshippingstatus') ) IS NOT NULL
BEGIN
DROP TABLE #logshippingstatus;
END;

CREATE TABLE #logshippingstatus
(
    Status BIT ,
    IsPrimary BIT ,
    Server VARCHAR(100) ,
    DatabaseName VARCHAR(100) ,
    TimeSinceLastBackup INT ,
    LastBackupFile VARCHAR(255) ,
    BackupThreshold INT ,
    IsBackupAlertEnabled BIT ,
    TimeSinceLastCopy INT ,
    LastCopiedFile VARCHAR(255) ,
    TimeSinceLastRestore INT ,
    LastRestoredFile VARCHAR(255) ,
    LastRestoredLatency INT ,
    RestoreThreshold INT ,
    IsRestoreAlertEnabled BIT
);

INSERT INTO #logshippingstatus
(   Status ,
    IsPrimary ,
    Server ,
    DatabaseName ,
    TimeSinceLastBackup ,
    LastBackupFile ,
    BackupThreshold ,
    IsBackupAlertEnabled ,
    TimeSinceLastCopy ,
    LastCopiedFile ,
    TimeSinceLastRestore ,
    LastRestoredFile ,
    LastRestoredLatency ,
    RestoreThreshold ,
    IsRestoreAlertEnabled
)
EXEC sys.sp_help_log_shipping_monitor"

        $select = "SELECT * FROM #logshippingstatus"

        if ($Database -or $ExcludeDatabase) {

            if ($database) {
                $where += "DatabaseName IN ('$($Database -join ''',''')')"
            } elseif ($ExcludeDatabase) {
                $where += "DatabaseName NOT IN ('$($ExcludeDatabase -join ''',''')')"
            }

            $select = "$select WHERE $where"
        }

        $query += $select
        $query += "DROP TABLE #logshippingstatus"
        $sql = $query -join ";`n"
        Write-Message -level Debug -Message $sql -FunctionName Test-DbaDbLogShipStatus -ModuleName "dbatools" # SOURCE: Write-Message -level Debug -Message $sql
    }

    @{ __w4067State = @{ sql = $sql } }
} $Database $ExcludeDatabase $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the source PROCESS block VERBATIM, byte-proven against source lines 203-318 after
    // stripping the 3 Stop-Function -FunctionName appends and reversing the single direct
    // Write-Message DEF-006 rewrite (the :212 Warning, # SOURCE marker). $sql is seeded from the
    // carried sentinel before the body; the dot-block preserves the source's Continue/return flow.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Simple, $Primary, $Secondary, $__state, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, $Simple, $Primary, $Secondary, $__state, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # seed the begin-built query carried from the begin hop, AND the three cross-record timestamp
    # leaks. $lastBackup/$lastCopy/$lastRestore are assigned only in the Status-in-0,1 branch
    # (:272-288) but read UNCONDITIONALLY when building the output object (:298/302/304), so in the
    # source's shared process scope a later record whose result has Status NOT in 0,1 inherits the
    # PRIOR record's timestamps. That is the W4-055 per-branch DEF-012 leak; carried bug-for-bug,
    # restore-if-carried only (NOT initialised - matches the source, undefined until first assigned).
    if ($null -ne $__state -and $__state.ContainsKey('sql')) { $sql = $__state.sql }
    if ($null -ne $__state -and $__state.ContainsKey('lastBackup')) { $lastBackup = $__state.lastBackup }
    if ($null -ne $__state -and $__state.ContainsKey('lastCopy')) { $lastCopy = $__state.lastCopy }
    if ($null -ne $__state -and $__state.ContainsKey('lastRestore')) { $lastRestore = $__state.lastRestore }

    . {
        foreach ($instance in $SqlInstance) {
            # Try connecting to the instance
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Test-DbaDbLogShipStatus
            }

            if ($server.EngineEdition -match "Express") {
                Write-Message -Level Warning -Message "$instance is Express Edition which does not support Log Shipping" -FunctionName Test-DbaDbLogShipStatus -ModuleName "dbatools" # SOURCE: Write-Message -Level Warning -Message "$instance is Express Edition which does not support Log Shipping"
                continue
            }

            # Check the variables
            if ($Primary -and $Secondary) {
                Stop-Function -Message "Invalid parameter combination. Please enter either -Primary or -Secondary" -Target $instance -Continue -FunctionName Test-DbaDbLogShipStatus
            }

            # Get the log shipped databases
            $results = @($server.Query($sql))

            # Check if any rows were returned
            if ($results.Count -lt 1) {
                Stop-Function -Message "No information available about any log shipped databases for $instance. Please check the instance name." -Target $instance -Continue -FunctionName Test-DbaDbLogShipStatus
            }

            # Filter the results
            if ($Primary) {
                $results = $results | Where-Object { $_.IsPrimary -eq $true }
            }

            if ($Secondary) {
                $results = $results | Where-Object { $_.IsPrimary -eq $false }
            }

            # Loop through each of the results
            foreach ($result in $results) {

                # Setup a variable to hold the errors
                $statusDetails = @()

                # Check if there are any results that need to be returned
                if ($result.Status -notin 0, 1) {
                    $statusDetails += "N/A"
                } else {
                    # Check the status of the row is true which indicates that something is wrong
                    if ($result.Status) {
                        # Check if the row is part of the primary or secondary instance
                        if ($result.IsPrimary) {
                            # Check the backup
                            if (-not $result.TimeSinceLastBackup) {
                                $statusDetails += "The backup has never been executed."
                            } elseif ($result.TimeSinceLastBackup -ge $result.BackupThreshold) {
                                $statusDetails += "The backup has not been executed in the last $($result.BackupThreshold) minutes"
                            }
                        } elseif (-not $result.IsPrimary) {
                            # Check the restore
                            if ($null -eq $result.TimeSinceLastRestore) {
                                $statusDetails += "The restore has never been executed."
                            } elseif ($result.TimeSinceLastRestore -ge $result.RestoreThreshold) {
                                $statusDetails += "The restore has not been executed in the last $($result.RestoreThreshold) minutes"
                            }
                        }
                    } else {
                        $statusDetails += "All OK"
                    }


                    # Check the time for the backup, copy and restore
                    if ($result.TimeSinceLastBackup -eq [DBNull]::Value) {
                        $lastBackup = "N/A"
                    } else {
                        $lastBackup = (Get-Date).AddMinutes(- $result.TimeSinceLastBackup)
                    }

                    if ($result.TimeSinceLastCopy -eq [DBNull]::Value) {
                        $lastCopy = "N/A"
                    } else {
                        $lastCopy = (Get-Date).AddMinutes(- $result.TimeSinceLastCopy)
                    }

                    if ($result.TimeSinceLastRestore -eq [DBNull]::Value) {
                        $lastRestore = "N/A"
                    } else {
                        $lastRestore = (Get-Date).AddMinutes(- $result.TimeSinceLastRestore)
                    }
                }

                # Set up the custom object
                $object = [PSCustomObject]@{
                    ComputerName          = $server.ComputerName
                    InstanceName          = $server.ServiceName
                    SqlInstance           = $server.DomainInstanceName
                    Database              = $result.DatabaseName
                    InstanceType          = switch ($result.IsPrimary) { $true { "Primary Instance" } $false { "Secondary Instance" } }
                    TimeSinceLastBackup   = $lastBackup
                    LastBackupFile        = $result.LastBackupFile
                    BackupThreshold       = $result.BackupThreshold
                    IsBackupAlertEnabled  = $result.IsBackupAlertEnabled
                    TimeSinceLastCopy     = $lastCopy
                    LastCopiedFile        = $result.LastCopiedFile
                    TimeSinceLastRestore  = $lastRestore
                    LastRestoredFile      = $result.LastRestoredFile
                    LastRestoredLatency   = $result.LastRestoredLatency
                    RestoreThreshold      = $result.RestoreThreshold
                    IsRestoreAlertEnabled = $result.IsRestoreAlertEnabled
                    Status                = $statusDetails -join ","
                }

                if ($Simple) {
                    $object | Select-DefaultView -Property SqlInstance, Database, InstanceType, Status
                } else {
                    $object
                }
            }
        }
    }

    @{ __w4067State = @{ sql = $sql; lastBackup = $lastBackup; lastCopy = $lastCopy; lastRestore = $lastRestore } }
} $SqlInstance $SqlCredential $Simple $Primary $Secondary $__state $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}