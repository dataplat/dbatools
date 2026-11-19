#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using System.Numerics;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves backup history for availability group databases across all replicas,
/// accumulating reachable replicas per pipeline record and aggregating the history
/// in the end block. Port of public/Get-DbaAgBackupHistory.ps1; surface pinned by
/// migration/baselines/Get-DbaAgBackupHistory.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaAgBackupHistory", DefaultParameterSetName = "Default")]
public sealed class GetDbaAgBackupHistoryCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances (replicas or a listener).</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The availability group whose database backup history is returned.</summary>
    [Parameter(Mandatory = true)]
    [PsStringCast]
    public string? AvailabilityGroup { get; set; }

    /// <summary>Restricts results to these databases.</summary>
    [Parameter]
    public string[]? Database { get; set; }

    /// <summary>Excludes these databases from the results.</summary>
    [Parameter]
    public string[]? ExcludeDatabase { get; set; }

    /// <summary>Includes copy-only backups in the results.</summary>
    [Parameter]
    public SwitchParameter IncludeCopyOnly { get; set; }

    /// <summary>Deletion-era switch retained on the NoLast set.</summary>
    [Parameter(ParameterSetName = "NoLast")]
    public SwitchParameter Force { get; set; }

    /// <summary>Only backups taken after this point in time.</summary>
    [Parameter]
    public DateTime Since { get; set; } = new DateTime(1970, 1, 1);

    /// <summary>Recovery fork GUID filter. The source declares a ValidateScript (GUID
    /// regex or empty string); expressed here as the equivalent ValidatePattern - same
    /// accept/reject set, binding-error text differs. The empty branch anchors with \z
    /// because the source's ('' -eq $_) rejects a lone newline that ^$ would tolerate;
    /// the GUID branch keeps $, matching the source -match's own trailing-newline
    /// tolerance (codex r1).</summary>
    [Parameter]
    [ValidatePattern(@"^\z|^(\{){0,1}[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}(\}){0,1}$")]
    public string? RecoveryFork { get; set; }

    /// <summary>Returns the most recent backup chain per database.</summary>
    [Parameter]
    public SwitchParameter Last { get; set; }

    /// <summary>Returns the most recent full backup per database.</summary>
    [Parameter]
    public SwitchParameter LastFull { get; set; }

    /// <summary>Returns the most recent differential backup per database.</summary>
    [Parameter]
    public SwitchParameter LastDiff { get; set; }

    /// <summary>Returns the most recent log backup per database.</summary>
    [Parameter]
    public SwitchParameter LastLog { get; set; }

    /// <summary>Restricts results to these backup device types.</summary>
    [Parameter]
    public string[]? DeviceType { get; set; }

    /// <summary>Returns one row per media rather than coalescing striped backups.</summary>
    [Parameter]
    public SwitchParameter Raw { get; set; }

    /// <summary>Only backups with a last LSN greater than this value.</summary>
    [Parameter]
    public BigInteger LastLsn { get; set; }

    /// <summary>Includes mirror backups in the results.</summary>
    [Parameter]
    public SwitchParameter IncludeMirror { get; set; }

    /// <summary>Restricts results to these backup types.</summary>
    [Parameter]
    [ValidateSet("Full", "Log", "Differential", "File", "Differential File", "Partial Full", "Partial Differential")]
    public string[]? Type { get; set; }

    /// <summary>LSN property used when sorting for the Last* filters.</summary>
    [Parameter]
    [ValidateSet("FirstLsn", "DatabaseBackupLsn", "LastLsn")]
    [PsStringCast]
    public string LsnSort { get; set; } = "FirstLsn";

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The cross-record $serverList accumulator (begin-initialized, appended per record,
    // consumed in end) rides the __w4013State sentinel.
    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        string[] boundKeys = new string[MyInvocation.BoundParameters.Keys.Count];
        MyInvocation.BoundParameters.Keys.CopyTo(boundKeys, 0);
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            ParameterSetName, boundKeys,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (DrainSentinelOrError(item))
            {
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

        // [DEF-001] closed via InvokeScopedStreaming (ab7492c). Streaming changes -WhatIf transcript
        // capture (documented observability change, not behaviour); the parity runner strips the
        // transcript gate-message. Fleet-confirmed non-blocker (C's streamed ShouldProcess wave, MSTest 487/487).
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (DrainSentinelOrError(item))
            {
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, AvailabilityGroup, EnableException.ToBool(), _state,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void EndProcessing()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, EndScript,
            AvailabilityGroup, Last.ToBool(), LastFull.ToBool(), LastDiff.ToBool(),
            LastLog.ToBool(), LsnSort, EnableException.ToBool(),
            TestBound(nameof(Database)), new Hashtable(MyInvocation.BoundParameters), _state,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (DrainSentinelOrError(item))
            {
                continue;
            }
            WriteObject(item);
        }
    }

    private bool DrainSentinelOrError(PSObject? item)
    {
        if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__w4013State"))
        {
            _state = sentinel["__w4013State"] as Hashtable;
            return true;
        }
        if (item?.BaseObject is ErrorRecord nestedError)
        {
            NestedCommand.RemoveDuplicateError(this, nestedError);
            WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            return true;
        }
        return false;
    }

    // PS: the begin block VERBATIM. Substitutions: two -FunctionName appends and two
    // inline rewrites with SOURCE comments - $PSCmdlet.ParameterSetName and
    // $PSBoundParameters.Keys cannot resolve inside a hop, so the C# carries the set
    // name and the bound-key list (binding order preserved). The empty accumulator
    // rides out on the __w4013State sentinel.
    private const string BeginScript = """
param($__parameterSetName, $__boundParameterKeys, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($__parameterSetName, [string[]]$__boundParameterKeys, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        Write-Message -Level System -Message "Active Parameter set: $($__parameterSetName)." -FunctionName Get-DbaAgBackupHistory # SOURCE: $($PSCmdlet.ParameterSetName) -ModuleName "dbatools"
        Write-Message -Level System -Message "Bound parameters: $($__boundParameterKeys -join ", ")" -FunctionName Get-DbaAgBackupHistory # SOURCE: $($PSBoundParameters.Keys -join ", ") -ModuleName "dbatools"
        $serverList = @()
    @{ __w4013State = @{ serverList = $serverList } }
} $__parameterSetName $__boundParameterKeys $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process foreach VERBATIM between the state injection and the sentinel
    // re-emission; four -FunctionName appends only. $serverList continuity across
    // records rides the sentinel (live SMO Server objects).
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $AvailabilityGroup, $EnableException, $__state, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string]$AvailabilityGroup, $EnableException, $__state, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    $serverList = $__state.serverList
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Get-DbaAgBackupHistory
            }

            # Only work on instances with availability groups
            if ($server.AvailabilityGroups.Count -eq 0) {
                Stop-Function -Message "Instance $instance has no availability groups, so skipping." -Target $instance -Continue -FunctionName Get-DbaAgBackupHistory
            }

            # Only work on instances with the specific availability group
            if ($AvailabilityGroup -notin $server.AvailabilityGroups.Name) {
                Stop-Function -Message "Instance $instance has no availability group named '$AvailabilityGroup', so skipping." -Target $instance -Continue -FunctionName Get-DbaAgBackupHistory
            }

            Write-Message -Level Verbose -Message "Added $server to serverList" -FunctionName Get-DbaAgBackupHistory -ModuleName "dbatools"
            $serverList += $server
        }
    @{ __w4013State = @{ serverList = $serverList } }
} $SqlInstance $SqlCredential $AvailabilityGroup $EnableException $__state $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the end block VERBATIM after the state injection. Substitutions: nine
    // -FunctionName appends, the Test-Bound Database flag, and the W3-090
    // $PSBoundParameters carry - the automatic variable cannot survive a hop, so the
    // C# passes new Hashtable(MyInvocation.BoundParameters) and the source's
    // Add/Remove/splat mutations operate on the carried copy (SOURCE comments per
    // site). The dot-block keeps the source's early return from skipping the hop tail.
    private const string EndScript = """
param($AvailabilityGroup, $Last, $LastFull, $LastDiff, $LastLog, $LsnSort, $EnableException, $__boundDatabase, $__boundParameters, $__state, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string]$AvailabilityGroup, $Last, $LastFull, $LastDiff, $LastLog, [string]$LsnSort, $EnableException, $__boundDatabase, $__boundParameters, $__state, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    $serverList = $__state.serverList
    . {
        if ($serverList.Count -eq 0) {
            Stop-Function -Message "No instances with availability group named '$AvailabilityGroup' found, so finishing without results." -FunctionName Get-DbaAgBackupHistory
            return
        }

        if ($serverList.Count -eq 1) {
            Write-Message -Level Verbose -Message "We have one server, so it should be a listener" -FunctionName Get-DbaAgBackupHistory -ModuleName "dbatools"
            $server = $serverList[0]

            $replicaNames = ($server.AvailabilityGroups | Where-Object { $_.Name -in $AvailabilityGroup } ).AvailabilityReplicas.Name
            Write-Message -Level Verbose -Message "We have found these replicas: $replicaNames" -FunctionName Get-DbaAgBackupHistory -ModuleName "dbatools"

            $serverList = $replicaNames
        }

        Write-Message -Level Verbose -Message "We have more than one server, so query them all and aggregate" -FunctionName Get-DbaAgBackupHistory -ModuleName "dbatools"
        # If -Database is not set, we want to filter on all databases of the availability group
        if (-not $__boundDatabase) { # SOURCE: if (Test-Bound -Not -ParameterName Database) {
            $agDatabase = (Get-DbaAgDatabase -SqlInstance $serverList[0] -AvailabilityGroup $AvailabilityGroup).Name
            $__boundParameters.Add('Database', $agDatabase) # SOURCE: $PSBoundParameters.Add
        }
        $null = $__boundParameters.Remove('SqlInstance') # SOURCE: $PSBoundParameters.Remove
        $null = $__boundParameters.Remove('AvailabilityGroup') # SOURCE: $PSBoundParameters.Remove
        $null = $__boundParameters.Remove('Last') # SOURCE: $PSBoundParameters.Remove
        $AgResults = Get-DbaDbBackupHistory -SqlInstance $serverList @__boundParameters # SOURCE: @PSBoundParameters
        foreach ($agr in $AgResults) {
            $agr.AvailabilityGroupName = $AvailabilityGroup
        }

        if ($Last) {
            Write-Message -Level Verbose -Message "Filtering Ag backups for Last" -FunctionName Get-DbaAgBackupHistory -ModuleName "dbatools"
            $AgResults | Select-DbaBackupInformation -ServerName $AvailabilityGroup
        } elseif ($LastFull) {
            Write-Message -Level Verbose -Message "Filtering Ag backups for LastFull" -FunctionName Get-DbaAgBackupHistory -ModuleName "dbatools"
            Foreach ($AgDb in ( $AgResults.Database | Select-Object -Unique)) {
                $AgResults | Where-Object { $_.Database -eq $AgDb } | Sort-Object -Property $LsnSort | Select-Object -Last 1
            }
        } elseif ($LastDiff) {
            Write-Message -Level Verbose -Message "Filtering Ag backups for LastDiff" -FunctionName Get-DbaAgBackupHistory -ModuleName "dbatools"
            Foreach ($AgDb in ( $AgResults.Database | Select-Object -Unique)) {
                $AgResults | Where-Object { $_.Database -eq $AgDb } | Sort-Object -Property $LsnSort | Select-Object -Last 1
            }
        } elseif ($LastLog) {
            Write-Message -Level Verbose -Message "Filtering Ag backups for LastLog" -FunctionName Get-DbaAgBackupHistory -ModuleName "dbatools"
            Foreach ($AgDb in ( $AgResults.Database | Select-Object -Unique)) {
                $AgResults | Where-Object { $_.Database -eq $AgDb } | Sort-Object -Property $LsnSort | Select-Object -Last 1
            }
        } else {
            Write-Message -Level Verbose -Message "Output Ag backups without filtering" -FunctionName Get-DbaAgBackupHistory -ModuleName "dbatools"
            $AgResults
        }
    }
} $AvailabilityGroup $Last $LastFull $LastDiff $LastLog $LsnSort $EnableException $__boundDatabase $__boundParameters $__state $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
