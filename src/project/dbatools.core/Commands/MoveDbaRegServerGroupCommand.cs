#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Moves registered server groups within the CMS hierarchy. Port of
/// public/Move-DbaRegServerGroup.ps1 (W3-062), the W3-061 Move-family shape verbatim: whole
/// process body one module hop per record, $Pscmdlet.ShouldProcess routed to the REAL cmdlet
/// (W1-085), WhatIf/Confirm/Verbose/Debug carriers, __w3062State sentinel carrying the
/// $InputObject += growth (W1-070 rebind reset) and the stale-able locals. The begin-block
/// Stop-Function latch (Test-FunctionInterrupt) is reproduced C#-side exactly as in
/// MoveDbaRegServerCommand (the latch variable lives in FUNCTION scope, unreachable per-hop).
/// [PsStringCast] rides the MANDATORY -NewGroup so an explicit null converts to "" at bind
/// time before the mandatory/validation checks, matching the script binder (W1-032 class -
/// the same skew lane A retrofitted at library@d1f16ab). SOURCE QUIRKS PRESERVED VERBATIM:
/// the "Found ..." Verbose fires BEFORE the null-group check (missing group logs
/// "Found  on ..." first), and the catch message interpolates $regserver - a variable this
/// function never defines - so the failure text renders with EMPTY name/instance tokens.
/// Private Get-RegServerParent and Get-RegServerGroupReverseParse ride the hop. Surface
/// pinned by migration/baselines/Move-DbaRegServerGroup.json (implicit positions 0-4,
/// NewGroup mandatory pos3, InputObject ServerGroup[] pos4 VFP, ConfirmImpact Medium).
/// </summary>
[Cmdlet(VerbsCommon.Move, "DbaRegServerGroup", SupportsShouldProcess = true)]
public sealed class MoveDbaRegServerGroupCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The group(s) to move (backslash notation for nested paths).</summary>
    [Parameter(Position = 2)]
    public string[]? Group { get; set; }

    /// <summary>Destination group path; "Default" targets the CMS root.</summary>
    [Parameter(Mandatory = true, Position = 3)]
    [PsStringCast]
    public string NewGroup { get; set; } = null!;

    /// <summary>Server group object(s) from Get-DbaRegServerGroup.</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public Microsoft.SqlServer.Management.RegisteredServers.ServerGroup[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The source's begin-block Stop-Function latch (Test-FunctionInterrupt) - see
    // MoveDbaRegServerCommand for the substitution rationale.
    private bool _hopInterrupted;

    // PS function-scope locals persisting across records.
    private Hashtable? _state;
    private object? _inputObjectState;
    private object? _lastBoundInputObject;
    private bool _bindInitialized;
    private bool _inputObjectNamedBound;

    protected override void BeginProcessing()
    {
        // Pipeline bindings are absent at begin time, so this pins whether InputObject was
        // NAMED-bound - the discriminator for the per-record rebind reset (codex W3-002 F1
        // class, swept family-wide: the same array INSTANCE piped twice defeats a pure
        // ReferenceEquals check).
        _inputObjectNamedBound = TestBound(nameof(InputObject));

        // PS begin: if ((Test-Bound SqlInstance) -and (Test-Bound -Not Group)) { Stop-Function "Group must be..." }
        if (TestBound(nameof(SqlInstance)) && !TestBound(nameof(Group)))
        {
            foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
                EnableException.ToBool(),
                NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
            {
                if (item?.BaseObject is ErrorRecord nestedError)
                {
                    NestedCommand.RemoveDuplicateError(this, nestedError);
                    WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                }
                else
                {
                    WriteObject(item);
                }
            }
            // Begin-level Stop-Function without -Continue always latches when it does not
            // throw (under -EnableException the hop above threw).
            _hopInterrupted = true;
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // PS: if (Test-FunctionInterrupt) { return } - the begin-block latch.
        if (_hopInterrupted)
            return;

        // W1-070: named $InputObject keeps ONE array reference across records; a piped
        // ServerGroup re-binds EVERY record it arrives in - even the same instance again
        // (codex W3-002 F1).
        if ((!_inputObjectNamedBound && TestBound(nameof(InputObject))) ||
            !ReferenceEquals(InputObject, _lastBoundInputObject) || !_bindInitialized)
        {
            _inputObjectState = InputObject;
            _lastBoundInputObject = InputObject;
            _bindInitialized = true;
        }

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w3062State"))
            {
                _state = sentinel["__w3062State"] as Hashtable;
                if (_state is not null)
                {
                    _inputObjectState = _state["InputObject"];
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
            SqlInstance, SqlCredential, Group, NewGroup, _inputObjectState,
            EnableException.ToBool(), _state, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin-block Stop-Function verbatim (message byte-exact); the C# caller
    // reproduces the function-scope latch (see _hopInterrupted).
    private const string BeginScript = """
param($EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    Stop-Function -Message "Group must be specified when using -SqlInstance" -FunctionName Move-DbaRegServerGroup
} $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the ENTIRE process body VERBATIM (no early return beyond the C#-handled latch).
    // Substitutions only: $Pscmdlet -> $__realCmdlet and explicit -FunctionName
    // Move-DbaRegServerGroup on Stop-Function/Write-Message (W1-090). The $regserver
    // interpolations in the catch are the SOURCE's own undefined-variable quirk - verbatim.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Group, $NewGroup, $InputObject, $EnableException, $__state, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Group, [string]$NewGroup, [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup[]]$InputObject, $EnableException, $__state, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # restore fn-scope locals mutated by earlier records
    if ($null -ne $__state) {
        $parentserver = $__state.parentserver
        $server = $__state.server
        $groupobject = $__state.groupobject
        $newname = $__state.newname
        $regservergroup = $__state.regservergroup
        $instance = $__state.instance
    }

    foreach ($instance in $SqlInstance) {
        $InputObject += Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $Group
    }

    foreach ($regservergroup in $InputObject) {
        $parentserver = Get-RegServerParent -InputObject $regservergroup

        if ($null -eq $parentserver) {
            Stop-Function -Message "Something went wrong and it's hard to explain, sorry. This basically shouldn't happen." -Continue -FunctionName Move-DbaRegServerGroup
        }

        $server = $regservergroup.ParentServer

        if ($NewGroup -eq 'Default') {
            $groupobject = Get-DbaRegServerGroup -SqlInstance $server -Id 1
        } else {
            $groupobject = Get-DbaRegServerGroup -SqlInstance $server -Group $NewGroup
        }

        Write-Message -Level Verbose -Message "Found $($groupobject.Name) on $($parentserver.ServerConnection.ServerName)" -FunctionName Move-DbaRegServerGroup -ModuleName "dbatools"

        if (-not $groupobject) {
            Stop-Function -Message "Group '$NewGroup' not found on $server" -Continue -FunctionName Move-DbaRegServerGroup
        }

        if ($__realCmdlet.ShouldProcess($regservergroup.SqlInstance, "Moving $($regservergroup.Name) to $($groupobject.Name)")) {
            try {
                Write-Message -Level Verbose -Message "Parsing $groupobject" -FunctionName Move-DbaRegServerGroup -ModuleName "dbatools"
                $newname = Get-RegServerGroupReverseParse $groupobject
                $newname = "$newname\$($regservergroup.Name)"
                Write-Message -Level Verbose -Message "Executing $($regservergroup.ScriptMove($groupobject).GetScript())" -FunctionName Move-DbaRegServerGroup -ModuleName "dbatools"
                $null = $parentserver.ServerConnection.ExecuteNonQuery($regservergroup.ScriptMove($groupobject).GetScript())
                Get-DbaRegServerGroup -SqlInstance $server -Group $newname
                $parentserver.ServerConnection.Disconnect()
            } catch {
                Stop-Function -Message "Failed to move $($regserver.Name) to $NewGroup on $($regserver.SqlInstance)" -ErrorRecord $_ -Continue -FunctionName Move-DbaRegServerGroup
            }
        }
    }
    @{ __w3062State = @{ InputObject = $InputObject; parentserver = $parentserver; server = $server; groupobject = $groupobject; newname = $newname; regservergroup = $regservergroup; instance = $instance } }
} $SqlInstance $SqlCredential $Group $NewGroup $InputObject $EnableException $__state $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
