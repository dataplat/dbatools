#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates server groups in CMS or Local Server Groups. Port of
/// public/Add-DbaRegServerGroup.ps1 (W3-003). The ENTIRE process body rides one VERBATIM
/// module hop per record with $Pscmdlet.ShouldProcess routed to the REAL cmdlet (W1-085),
/// Test-Bound -ParameterName Group carried as a flag, and bound -WhatIf/-Confirm carried
/// into the hop's own SupportsShouldProcess binding (the Copy-family convention).
/// Cross-record fn-scope persistence rides the __w3003State sentinel bag: $InputObject +=
/// growth with the ReferenceEquals pipeline-rebind reset (W1-070), and the -Group PARAMETER
/// SHADOWED by the split-segment loop variable (`foreach ($group in $groupList)` assigns
/// the same case-insensitive variable, so a later record's nested
/// Get-DbaRegServerGroup -Group $Group reads the PRIOR record's last segment - preserved),
/// plus the stale-able locals ($reggroup, $currentInstance, $target, $newGroup, $groupList,
/// $instance). Nested Get-DbaRegServerGroup and the PRIVATE
/// Get-RegServerGroupReverseParse ride the hop verbatim in module scope. Surface pinned by
/// migration/baselines/Add-DbaRegServerGroup.json (implicit positions 0-5, Name mandatory
/// pos2, InputObject ServerGroup[] pos5 VFP, ConfirmImpact Medium, no OutputType).
/// </summary>
[Cmdlet(VerbsCommon.Add, "DbaRegServerGroup", SupportsShouldProcess = true)]
public sealed class AddDbaRegServerGroupCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance hosting the CMS.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The name for the new server group; backslash notation creates nested hierarchies.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    [PsStringCast]
    public string Name { get; set; } = null!;

    /// <summary>Additional details about the server group.</summary>
    [Parameter(Position = 3)]
    public string? Description { get; set; }

    /// <summary>The parent group path for the new group.</summary>
    [Parameter(Position = 4)]
    public string? Group { get; set; }

    /// <summary>Server group object(s) from Get-DbaRegServerGroup.</summary>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public Microsoft.SqlServer.Management.RegisteredServers.ServerGroup[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // PS function-scope locals persisting across records (the state bag rides the hop
    // and comes back as the sentinel item).
    private Hashtable? _state;
    private object? _inputObjectState;
    private object? _lastBoundInputObject;
    private object? _groupState;
    private bool _bindInitialized;
    private bool _inputObjectNamedBound;

    protected override void BeginProcessing()
    {
        // Named-at-begin discriminator for the per-record rebind reset (codex W3-002 F1
        // class swept to this sibling: same-instance repipes defeat pure ReferenceEquals).
        _inputObjectNamedBound = TestBound("InputObject");
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // PS: named $InputObject keeps ONE array reference across records (the += growth
        // persists); a piped ServerGroup re-binds EVERY record it arrives in (W1-070).
        if ((!_inputObjectNamedBound && TestBound("InputObject")) ||
            !ReferenceEquals(InputObject, _lastBoundInputObject) || !_bindInitialized)
        {
            _inputObjectState = InputObject;
            _lastBoundInputObject = InputObject;
        }

        if (!_bindInitialized)
        {
            // PS: unbound [string] reads "" (W1-087). $Group is subsequently SHADOWED by
            // the split-segment loop; the sentinel carries the mutated value forward.
            _groupState = Group ?? "";
            _bindInitialized = true;
        }

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w3003State"))
            {
                _state = sentinel["__w3003State"] as Hashtable;
                if (_state is not null)
                {
                    _inputObjectState = _state["InputObject"];
                    _groupState = _state["Group"];
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
            SqlInstance, SqlCredential, Name, Description ?? "", _groupState,
            _inputObjectState, EnableException.ToBool(), _state, TestBound("Group"), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the ENTIRE process body VERBATIM plus the trailing state sentinel. Substitutions
    // only: Test-Bound -ParameterName Group -> carried $__boundGroup, $Pscmdlet ->
    // $__realCmdlet, and explicit -FunctionName Add-DbaRegServerGroup on
    // Stop-Function/Write-Message (W1-090).
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Name, $Description, $Group, $InputObject, $EnableException, $__state, $__boundGroup, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
# WarningAction is deliberately NOT forwarded into the hop (codex W3-005 r1-r3 arc):
# forwarding suppressing values empties the caller's -WarningVariable, and forwarding Stop
# terminates inside the hop BEFORE the warning reaches the host stream (same capture loss).
# All values ride the host's own machinery at the 3>&1 replay, preserving WarningVariable
# and display parity for every value; the at-emission vs at-replay TIMING difference is the
# recorded InvokeScoped buffered-output SYSTEMIC (integrator-owned architecture item).
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string]$Name, [string]$Description, [string]$Group, [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup[]]$InputObject, $EnableException, $__state, $__boundGroup, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # restore fn-scope locals mutated by earlier records
    if ($null -ne $__state) {
        $reggroup = $__state.reggroup
        $currentInstance = $__state.currentInstance
        $target = $__state.target
        $newGroup = $__state.newGroup
        $groupList = $__state.groupList
        $instance = $__state.instance
    }

    foreach ($instance in $SqlInstance) {
        if (($__boundGroup)) {
            $InputObject += Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $Group
        } else {
            $InputObject += Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Id 1
        }
    }

    if (-not $SqlInstance -and -not $InputObject) {
        if (($__boundGroup)) {
            $InputObject += Get-DbaRegServerGroup -Group $Group
        } else {
            $InputObject += Get-DbaRegServerGroup -Id 1
        }
    }

    foreach ($reggroup in $InputObject) {
        if ($reggroup.Source -eq "Azure Data Studio") {
            Stop-Function -Message "You cannot use dbatools to remove or add registered server groups in Azure Data Studio" -Continue -FunctionName Add-DbaRegServerGroup
        }

        $currentInstance = $reggroup.ParentServer

        if ($reggroup.ID) {
            $target = $reggroup.Parent
        } else {
            $target = "Local Registered Server Groups"
        }

        if ($__realCmdlet.ShouldProcess($target, "Adding $Name")) {
            try {
                $groupList = $Name -split '\\'
                foreach ($group in $groupList) {
                    if ($null -eq $reggroup.ServerGroups[$group]) {
                        $newGroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($reggroup, $group)
                        $newGroup.create()
                        $reggroup.refresh()
                    } else {
                        Write-Message -Level Verbose -Message "Group $group already exists. Will continue." -FunctionName Add-DbaRegServerGroup -ModuleName "dbatools"
                        $newGroup = $reggroup.ServerGroups[$group]
                    }
                    $reggroup = $reggroup.ServerGroups[$group]
                }
                $newgroup.Description = $Description
                $newgroup.Alter()

                Get-DbaRegServerGroup -SqlInstance $currentInstance -Group (Get-RegServerGroupReverseParse -object $newgroup)
                if ($currentInstance.ConnectionContext) {
                    $currentInstance.ConnectionContext.Disconnect()
                }
            } catch {
                Stop-Function -Message "Failed to add $reggroup" -ErrorRecord $_ -Continue -FunctionName Add-DbaRegServerGroup
            }
        }
    }

    @{ __w3003State = @{ InputObject = $InputObject; Group = $Group; reggroup = $reggroup; currentInstance = $currentInstance; target = $target; newGroup = $newGroup; groupList = $groupList; instance = $instance } }
} $SqlInstance $SqlCredential $Name $Description $Group $InputObject $EnableException $__state $__boundGroup $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
