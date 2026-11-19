#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Modifies settings on an availability group replica.
/// Port of public/Set-DbaAgReplica.ps1; surface pinned by
/// migration/baselines/Set-DbaAgReplica.json.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaAgReplica", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class SetDbaAgReplicaCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server instance or instances hosting the availability group.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The availability group. Singular string, not an array.</summary>
    [Parameter(Position = 2)]
    public string? AvailabilityGroup { get; set; }

    /// <summary>The replica to modify. Singular string, not an array.</summary>
    [Parameter(Position = 3)]
    public string? Replica { get; set; }

    /// <summary>The availability mode.</summary>
    [Parameter(Position = 4)]
    [ValidateSet("AsynchronousCommit", "SynchronousCommit")]
    [PsStringCast]
    public string? AvailabilityMode { get; set; }

    /// <summary>The failover mode.</summary>
    [Parameter(Position = 5)]
    [ValidateSet("Automatic", "Manual", "External")]
    [PsStringCast]
    public string? FailoverMode { get; set; }

    /// <summary>The backup priority.</summary>
    [Parameter(Position = 6)]
    public int BackupPriority { get; set; }

    /// <summary>The connection mode in the primary role.</summary>
    [Parameter(Position = 7)]
    [ValidateSet("AllowAllConnections", "AllowReadWriteConnections")]
    [PsStringCast]
    public string? ConnectionModeInPrimaryRole { get; set; }

    /// <summary>The connection mode in the secondary role. Accepts both the SMO names and the
    /// friendly aliases the source normalises at :207.</summary>
    [Parameter(Position = 8)]
    [ValidateSet("AllowAllConnections", "AllowNoConnections", "AllowReadIntentConnectionsOnly",
        "No", "Read-intent only", "Yes")]
    [PsStringCast]
    public string? ConnectionModeInSecondaryRole { get; set; }

    /// <summary>The seeding mode.</summary>
    [Parameter(Position = 9)]
    [ValidateSet("Automatic", "Manual")]
    [PsStringCast]
    public string? SeedingMode { get; set; }

    /// <summary>The session timeout in seconds.</summary>
    [Parameter(Position = 10)]
    public int SessionTimeout { get; set; }

    /// <summary>The endpoint URL.</summary>
    [Parameter(Position = 11)]
    public string? EndpointUrl { get; set; }

    /// <summary>The read-only routing connection URL.</summary>
    [Parameter(Position = 12)]
    public string? ReadonlyRoutingConnectionUrl { get; set; }

    /// <summary>The read-only routing list - a flat list, or nested for load-balanced routing.</summary>
    [Parameter(Position = 13)]
    public object[]? ReadOnlyRoutingList { get; set; }

    /// <summary>A replica object piped from Get-DbaAgReplica. SINGULAR, not an array.</summary>
    [Parameter(ValueFromPipeline = true, Position = 14)]
    public Microsoft.SqlServer.Management.Smo.AvailabilityReplica? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        base.BeginProcessing();

        // C1 transplant condition: loud fail before any record if the engine field is gone.
        PromptStateTransplant.AssertResolvable("Set-DbaAgReplica");

        // SEPARATE BEGIN HOP - and this was CORRECTED at port time. My claim note argued that,
        // unlike W4-049, this row's begin is side-effect-only and could be folded into the process
        // top. That was wrong. The begin runs `Add-Type -AssemblyName System.Collections` when
        // -ReadOnlyRoutingList is bound, and the PROCESS body DEPENDS on it: :270/:275/:281
        // construct System.Collections.Generic.List[...] to build the argument for
        // SetLoadBalancedReadOnlyRoutingList at :287. So the begin is a PRECONDITION, the same
        // structural situation as W4-049 even though nothing is carried by value.
        //
        // Folding would re-run Add-Type per piped record. That is idempotent so it would not
        // break, but it is an observable call-count divergence the source does not have, and the
        // W4-049 precedent already rejects folding when the begin does real work.
        //
        // NOTE the sentinel carries NO begin state by value here - there is no $primaryServer
        // equivalent - so this hop harvests only the W3-082 prompt state.
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            ReadOnlyRoutingList,
            EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w4057State"))
            {
                _state = sentinel["__w4057State"] as Hashtable;
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

        // WHOLE-RECORD hop, 307-line source - the largest in this satellite.
        //
        // NO PARAMETER CARRY, and the interesting one is the CONVERGING case:
        // $ConnectionModeInSecondaryRole is assigned at :208 under a VALUE guard
        // (`if ($ConnectionModeInSecondaryRole)`), which RULE 2 would normally call STICKY and
        // carry. But the assignment is a NORMALISING SWITCH whose default arm returns the value
        // UNCHANGED (No -> AllowNoConnections, "Read-intent only" ->
        // AllowReadIntentConnectionsOnly, Yes -> AllowAllConnections, default -> itself), so
        // re-application is IDEMPOTENT. In the source, record 2 sees record 1's already-normalised
        // value and the switch returns it unchanged; in the hop, record 2 normalises the fresh
        // bound value to the same result. Both converge, so a carry would be a NO-OP - the exact
        // third-bullet case in the detector's own RULE 2 text. Pinned by a probe scenario rather
        // than left as reasoning: two piped records with -ConnectionModeInSecondaryRole No must
        // both yield AllowNoConnections in both worlds.
        //
        // $InputObject at :218 is the VFP parameter, RE-BOUND every record - no carry. Note it is
        // SINGULAR ([AvailabilityReplica], not an array) while the source does `$InputObject +=`
        // on it; that quirk rides verbatim rather than being tidied.
        //
        // BOTH DETECTORS RUN per the DEF-012 sub-class ruling: the leak detector reports no
        // non-parameter read-before-assign candidates, and because that is only the source-order
        // check, the nested if/else blocks were read by hand for the per-BRANCH shape that hid
        // $ag on W4-055. $agreplica and $server are assigned by the foreach and its first
        // statement before any read; $rorl, $serverList and $isLoadBalanced are assigned before
        // use within the same block.
        //
        // W3-082 PROMPT-STATE TRANSPLANT over the single inner gate at :223.
        // [DEF-001] closed via InvokeScopedStreaming (ab7492c). Streaming changes -WhatIf transcript
        // capture (documented observability change, not behaviour); the parity runner strips the
        // transcript gate-message. Fleet-confirmed non-blocker (C's streamed ShouldProcess wave, MSTest 487/487).
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w4057State"))
            {
                _state = sentinel["__w4057State"] as Hashtable;
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
            SqlInstance, SqlCredential, AvailabilityGroup, Replica, AvailabilityMode, FailoverMode,
            BackupPriority, ConnectionModeInPrimaryRole, ConnectionModeInSecondaryRole, SeedingMode,
            SessionTimeout, EndpointUrl, ReadonlyRoutingConnectionUrl, ReadOnlyRoutingList,
            InputObject, EnableException.ToBool(),
            TestBound(nameof(SqlInstance)), TestBound(nameof(InputObject)),
            _state,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source BEGIN block VERBATIM (lines 190-192), CRLF-preserved. No substitutions are
    // needed - it contains no Stop-Function and no Test-Bound. The tail harvests only prompt
    // state; nothing from begin is read by value in process.
    private const string BeginScript = """
param($ReadOnlyRoutingList, $EnableException, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([object[]]$ReadOnlyRoutingList, $EnableException, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        if ($ReadOnlyRoutingList) {
            $null = Add-Type -AssemblyName System.Collections
        }
    }

    @{ __w4057State = @{ shouldProcessContinueStatus = $null } }
} $ReadOnlyRoutingList $EnableException $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the source PROCESS block VERBATIM (lines 195-305), CRLF-preserved and byte-proven,
    // after appending four -FunctionName arguments and reversing the single Test-Bound rewrite
    // (SOURCE comment). Every explanatory comment in the routing-list section rides untouched.
    // Bracketing the body: only the W3-082 prompt-state transplant - no parameter carry, because
    // the one candidate converges (see ProcessRecord).
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $AvailabilityGroup, $Replica, $AvailabilityMode, $FailoverMode, $BackupPriority, $ConnectionModeInPrimaryRole, $ConnectionModeInSecondaryRole, $SeedingMode, $SessionTimeout, $EndpointUrl, $ReadonlyRoutingConnectionUrl, $ReadOnlyRoutingList, $InputObject, $EnableException, $__boundSqlInstance, $__boundInputObject, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string]$AvailabilityGroup, [string]$Replica, [string]$AvailabilityMode, [string]$FailoverMode, [int]$BackupPriority, [string]$ConnectionModeInPrimaryRole, [string]$ConnectionModeInSecondaryRole, [string]$SeedingMode, [int]$SessionTimeout, [string]$EndpointUrl, [string]$ReadonlyRoutingConnectionUrl, [object[]]$ReadOnlyRoutingList, [Microsoft.SqlServer.Management.Smo.AvailabilityReplica]$InputObject, $EnableException, $__boundSqlInstance, $__boundInputObject, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # cross-record engine-state restore: the ShouldProcess Yes/No-to-All answer spans the
    # pipeline in the source (one CommandRuntime); the transplant field name is identical
    # on PS 5.1 and PS 7 (W3-082 mechanism, empirically verified). NO parameter carry on this
    # row - the one candidate, $ConnectionModeInSecondaryRole, is normalised by a switch whose
    # default arm returns the value unchanged, so re-application converges and a carry would be
    # a no-op (RULE 2 third bullet). $InputObject is the VFP parameter, re-bound every record.
    $__spField = $Pscmdlet.CommandRuntime.GetType().GetField("lastShouldProcessContinueStatus", [System.Reflection.BindingFlags]"NonPublic,Instance")
    if ($null -eq $__spField) {
        throw "Set-DbaAgReplica: prompt-state transplant field lastShouldProcessContinueStatus not resolvable on this engine (C1 assert)."
    }
    if ($null -ne $__state -and $null -ne $__state.shouldProcessContinueStatus) {
        $__spField.SetValue($Pscmdlet.CommandRuntime, [Enum]::Parse($__spField.FieldType, $__state.shouldProcessContinueStatus))
    }

    . {
        if (-not ($__boundSqlInstance -or $__boundInputObject)) { # SOURCE: if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -FunctionName Set-DbaAgReplica
            return
        }

        if (-not $InputObject) {
            if (-not $AvailabilityGroup -or -not $Replica) {
                Stop-Function -Message "You must specify an AvailabilityGroup and replica or pipe in an availabilty group to continue." -FunctionName Set-DbaAgReplica
                return
            }
        }

        if ($ConnectionModeInSecondaryRole) {
            $ConnectionModeInSecondaryRole =
            switch ($ConnectionModeInSecondaryRole) {
                "No" { "AllowNoConnections" }
                "Read-intent only" { "AllowReadIntentConnectionsOnly" }
                "Yes" { "AllowAllConnections" }
                default { $ConnectionModeInSecondaryRole }
            }
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaAgReplica -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup -Replica $Replica
        }

        foreach ($agreplica in $InputObject) {
            $server = $agreplica.Parent.Parent
            if ($Pscmdlet.ShouldProcess($server.Name, "Modifying replica for $($agreplica.Name) named $Name")) {
                try {
                    if ($EndpointUrl) {
                        $agreplica.EndpointUrl = $EndpointUrl
                    }

                    if ($FailoverMode) {
                        $agreplica.FailoverMode = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaFailoverMode]::$FailoverMode
                    }

                    if ($AvailabilityMode) {
                        $agreplica.AvailabilityMode = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaAvailabilityMode]::$AvailabilityMode
                    }

                    if ($ConnectionModeInPrimaryRole) {
                        $agreplica.ConnectionModeInPrimaryRole = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaConnectionModeInPrimaryRole]::$ConnectionModeInPrimaryRole
                    }

                    if ($ConnectionModeInSecondaryRole) {
                        $agreplica.ConnectionModeInSecondaryRole = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaConnectionModeInSecondaryRole]::$ConnectionModeInSecondaryRole
                    }

                    if ($BackupPriority) {
                        $agreplica.BackupPriority = $BackupPriority
                    }

                    if ($ReadonlyRoutingConnectionUrl) {
                        $agreplica.ReadonlyRoutingConnectionUrl = $ReadonlyRoutingConnectionUrl
                    }

                    if ($SeedingMode) {
                        $agreplica.SeedingMode = $SeedingMode
                    }

                    if ($ReadOnlyRoutingList) {
                        # Detect if this is a simple ordered list or a load-balanced (nested) list
                        # Simple list: @('Server1', 'Server2') - routes in order
                        # Load-balanced list: @(,('Server1', 'Server2')) or @(('Server1'),('Server2','Server3')) - load balances within groups
                        $isLoadBalanced = $false

                        # Check if the first element is an array/list (indicates load-balanced routing)
                        if ($ReadOnlyRoutingList.Count -gt 0 -and $ReadOnlyRoutingList[0] -is [System.Array]) {
                            $isLoadBalanced = $true
                        }

                        # Always use SetLoadBalancedReadOnlyRoutingList as it's available in all SMO versions
                        # For simple ordered lists, convert each server to its own group to maintain order
                        $rorl = New-Object System.Collections.Generic.List[System.Collections.Generic.IList[string]]

                        if ($isLoadBalanced) {
                            # Already nested - use as-is for load-balanced routing
                            foreach ($rolist in $ReadOnlyRoutingList) {
                                $null = $rorl.Add([System.Collections.Generic.List[string]] $rolist)
                            }
                        } else {
                            # Simple ordered list - wrap each server in its own list to maintain priority order
                            # @('Server1', 'Server2') becomes @(@('Server1'), @('Server2'))
                            foreach ($server in $ReadOnlyRoutingList) {
                                $serverList = New-Object System.Collections.Generic.List[string]
                                $null = $serverList.Add([string]$server)
                                $null = $rorl.Add($serverList)
                            }
                        }

                        $null = $agreplica.SetLoadBalancedReadOnlyRoutingList($rorl)
                    }

                    if ($SessionTimeout) {
                        if ($SessionTimeout -lt 10) {
                            $Message = "We recommend that you keep the time-out period at 10 seconds or greater. Setting the value to less than 10 seconds creates the possibility of a heavily loaded system missing pings and falsely declaring failure. Please see sqlps.io/agrec for more information."
                            Write-Message -Message $Message -Level Warning -FunctionName Set-DbaAgReplica -ModuleName "dbatools"
                        }
                        $agreplica.SessionTimeout = $SessionTimeout
                    }

                    $agreplica.Alter()
                    $agreplica

                } catch {
                    Stop-Function -Message "Failed to modify replica $($agreplica.Name) in availability group $($agreplica.Parent.Name)" -ErrorRecord $_ -Continue -FunctionName Set-DbaAgReplica
                }
            }
        }
    }

    @{ __w4057State = @{ shouldProcessContinueStatus = $(if ($null -ne $__spField) { "$($__spField.GetValue($Pscmdlet.CommandRuntime))" } else { $null }) } }
} $SqlInstance $SqlCredential $AvailabilityGroup $Replica $AvailabilityMode $FailoverMode $BackupPriority $ConnectionModeInPrimaryRole $ConnectionModeInSecondaryRole $SeedingMode $SessionTimeout $EndpointUrl $ReadonlyRoutingConnectionUrl $ReadOnlyRoutingList $InputObject $EnableException $__boundSqlInstance $__boundInputObject $__state $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
