#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Joins a secondary replica to an existing availability group.
/// Port of public/Join-DbaAvailabilityGroup.ps1; surface pinned by
/// migration/baselines/Join-DbaAvailabilityGroup.json.
/// </summary>
[Cmdlet(VerbsCommon.Join, "DbaAvailabilityGroup", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class JoinDbaAvailabilityGroupCommand : DbaBaseCmdlet
{
    /// <summary>The secondary SQL Server instance or instances joining the group.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The availability groups to join.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? AvailabilityGroup { get; set; }

    /// <summary>The cluster type of the availability group.</summary>
    [Parameter(Position = 3)]
    [ValidateSet("External", "Wsfc", "None")]
    [PsStringCast]
    public string? ClusterType { get; set; }

    /// <summary>Availability group objects piped from Get-DbaAvailabilityGroup.</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        base.BeginProcessing();

        // C1 transplant condition: loud fail before any record if the engine field is gone.
        PromptStateTransplant.AssertResolvable("Join-DbaAvailabilityGroup");
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // WHOLE-RECORD hop. The source has NO begin block; its process block mutates TWO
        // PARAMETERS in place - `$AvailabilityGroup += $InputObject.Name` and the sticky
        // `$ClusterType` derivation - and PowerShell parameters are function-scope, so in
        // the source those mutations PERSIST across piped records: record 2 sees record 1's
        // accumulated group list (and therefore re-joins the earlier group) and never
        // derives its own ClusterType. Probe-confirmed with positive and negative controls
        // (migration/tools/Probe-W4042ParamAccumulation.ps1). A per-record hop hands each
        // record FRESH parameters, so both quirks would silently vanish - they ride the
        // __w4042State sentinel and are reproduced bug-for-bug, not fixed. The same
        // sentinel carries the W3-082 prompt-state transplant (Class-2 signature: VFP
        // InputObject + per-record ProcessRecord + inner-$Pscmdlet gate + source gate at
        // function scope in process{}). The loop-less validation returns exit the record
        // via the dot-block frame; the in-loop sites are -Continue. Test-Bound scope-walks
        // the caller, so its multi-name call becomes two carried bound flags.
        // [DEF-001] closed via InvokeScopedStreaming (ab7492c). Streaming changes -WhatIf transcript
        // capture (documented observability change, not behaviour); the parity runner strips the
        // transcript gate-message. Fleet-confirmed non-blocker (C's streamed ShouldProcess wave, MSTest 487/487).
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w4042State"))
            {
                _state = sentinel["__w4042State"] as Hashtable;
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
            SqlInstance, SqlCredential, AvailabilityGroup, ClusterType, InputObject,
            EnableException.ToBool(),
            TestBound(nameof(SqlInstance)), TestBound(nameof(InputObject)), _state,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source process block VERBATIM, CRLF-preserved and cmp-proven byte-exact
    // after stripping four -FunctionName appends and reversing the multi-name Test-Bound
    // rewrite (SOURCE comment). The ShouldProcess gate uses the inner block's own
    // $Pscmdlet; the dot-block preserves the source's two early returns. Bracketing the
    // body: the carried parameter mutations ($AvailabilityGroup accumulation, sticky
    // $ClusterType) are seeded BEFORE the body so it observes the source's cross-record
    // state, and the W3-082 prompt-state transplant is injected before any gate; the tail
    // harvests all three into the sentinel.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $AvailabilityGroup, $ClusterType, $InputObject, $EnableException, $__boundSqlInstance, $__boundInputObject, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$AvailabilityGroup, [string]$ClusterType, [Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]]$InputObject, $EnableException, $__boundSqlInstance, $__boundInputObject, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # cross-record PARAMETER state: the source mutates these two params in process{} and
    # parameters are fn-scope, so a later piped record observes the earlier record's values
    # (accumulated group list, sticky cluster type). Seed them before the body runs.
    if ($null -ne $__state) {
        if ($null -ne $__state.availabilityGroup) { $AvailabilityGroup = $__state.availabilityGroup }
        if ($null -ne $__state.clusterType) { $ClusterType = $__state.clusterType }
    }

    # cross-record engine-state restore: the ShouldProcess Yes/No-to-All answer spans the
    # pipeline in the source (one CommandRuntime); the transplant field name is identical
    # on PS 5.1 and PS 7 (W3-082 mechanism, empirically verified)
    $__spField = $Pscmdlet.CommandRuntime.GetType().GetField("lastShouldProcessContinueStatus", [System.Reflection.BindingFlags]"NonPublic,Instance")
    if ($null -eq $__spField) {
        throw "Join-DbaAvailabilityGroup: prompt-state transplant field lastShouldProcessContinueStatus not resolvable on this engine (C1 assert)."
    }
    if ($null -ne $__state -and $null -ne $__state.shouldProcessContinueStatus) {
        $__spField.SetValue($Pscmdlet.CommandRuntime, [Enum]::Parse($__spField.FieldType, $__state.shouldProcessContinueStatus))
    }

    . {
        if (-not ($__boundSqlInstance -or $__boundInputObject)) { # SOURCE: if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -FunctionName Join-DbaAvailabilityGroup
            return
        }

        if ($InputObject) {
            $AvailabilityGroup += $InputObject.Name
            if (-not $ClusterType) {
                $tempclustertype = ($InputObject | Select-Object -First 1).ClusterType
                if ($tempclustertype) {
                    $ClusterType = $tempclustertype
                }
            }
        }

        if (-not $AvailabilityGroup) {
            Stop-Function -Message "No availability group to add" -FunctionName Join-DbaAvailabilityGroup
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Join-DbaAvailabilityGroup
            }

            foreach ($ag in $AvailabilityGroup) {
                if ($Pscmdlet.ShouldProcess($server.Name, "Joining $ag")) {
                    try {
                        if ($ClusterType -and $server.VersionMajor -ge 14) {
                            $server.Query("ALTER AVAILABILITY GROUP [$ag] JOIN WITH (CLUSTER_TYPE = $ClusterType)")
                        } else {
                            $server.JoinAvailabilityGroup($ag)
                        }
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -FunctionName Join-DbaAvailabilityGroup
                    }
                }
            }
        }
    }

    @{ __w4042State = @{ availabilityGroup = $AvailabilityGroup; clusterType = $ClusterType; shouldProcessContinueStatus = $(if ($null -ne $__spField) { "$($__spField.GetValue($Pscmdlet.CommandRuntime))" } else { $null }) } }
} $SqlInstance $SqlCredential $AvailabilityGroup $ClusterType $InputObject $EnableException $__boundSqlInstance $__boundInputObject $__state $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}