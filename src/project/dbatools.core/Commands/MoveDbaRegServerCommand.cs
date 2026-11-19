#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Moves registered servers between CMS groups. Port of public/Move-DbaRegServer.ps1
/// (W3-061), the W3-002/003 RegServer-family template: the ENTIRE process body rides one
/// VERBATIM module hop per record with $Pscmdlet.ShouldProcess routed to the REAL cmdlet
/// (W1-085), bound -WhatIf/-Confirm carried into the hop's own SupportsShouldProcess
/// binding (Copy-family convention) so the nested Get-DbaRegServer/Get-DbaRegServerGroup
/// and private Get-RegServerParent ride with the caller's preference, and Test-Bound reads
/// carried as bound flags. Function-scope mutations persist across records through the
/// __w3061State sentinel: $InputObject grows via += inside the SqlInstance loop (a
/// ReferenceEquals reset detects the per-record pipeline rebind, W1-070) and the stale-able
/// locals carry over exactly as PS function scope carried them. The source's begin-block
/// Stop-Function latch (Test-FunctionInterrupt pattern: Stop-Function writes the interrupt
/// variable into FUNCTION scope, shared by begin/process) cannot ride per-hop scopes, so it
/// is the ONE substitution beyond the template list: the begin validation fires its
/// Stop-Function through a hop for message/stream/EnableException parity, then a C#-side
/// flag reproduces the latch and every ProcessRecord early-returns exactly like the
/// source's `if (Test-FunctionInterrupt) { return }`. No early return exists inside the
/// process body itself, so no dot-source block (the W3-003 shape). Surface pinned by
/// migration/baselines/Move-DbaRegServer.json (implicit positions 0-5, Group alias
/// NewGroup, InputObject RegisteredServer[] pos5 VFP, ConfirmImpact Medium, no OutputType).
/// </summary>
[Cmdlet(VerbsCommon.Move, "DbaRegServer", SupportsShouldProcess = true)]
public sealed class MoveDbaRegServerCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Registered server display names as shown in the CMS tree.</summary>
    [Parameter(Position = 2)]
    public string[]? Name { get; set; }

    /// <summary>Registered server actual instance names (connection strings).</summary>
    [Parameter(Position = 3)]
    public string[]? ServerName { get; set; }

    /// <summary>Destination group (backslash notation for nested groups); root when omitted.</summary>
    [Parameter(Position = 4)]
    [Alias("NewGroup")]
    public string? Group { get; set; }

    /// <summary>Registered server object(s) from Get-DbaRegServer.</summary>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The source's begin-block Stop-Function latch (Test-FunctionInterrupt): set once in
    // BeginProcessing, checked at the top of every ProcessRecord like the source's
    // `if (Test-FunctionInterrupt) { return }`.
    private bool _hopInterrupted;

    // PS function-scope locals persisting across records (the state bag rides the hop
    // and comes back as the sentinel item).
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

        // PS begin: if ((Test-Bound SqlInstance) -and (Test-Bound -Not Name) -and
        // (Test-Bound -Not ServerName)) { Stop-Function "Name or ServerName must be..." }
        if (TestBound(nameof(SqlInstance)) && !TestBound(nameof(Name)) && !TestBound(nameof(ServerName)))
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
            // A begin-level Stop-Function without -Continue always latches the function
            // interrupt when it does not throw (under -EnableException the hop above threw).
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

        // PS: named $InputObject keeps ONE array reference across records (the += growth
        // persists); a piped RegisteredServer re-binds EVERY record it arrives in - even
        // the same instance again (W1-070 + codex W3-002 F1).
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
            if (sentinel is not null && sentinel.ContainsKey("__w3061State"))
            {
                _state = sentinel["__w3061State"] as Hashtable;
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
            SqlInstance, SqlCredential, Name, ServerName, Group, _inputObjectState,
            EnableException.ToBool(), _state, TestBound(nameof(Group)), this,
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

    Stop-Function -Message "Name or ServerName must be specified when using -SqlInstance" -FunctionName Move-DbaRegServer
} $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the ENTIRE process body VERBATIM (no early return, so no dot-source block - the
    // W3-003 shape). Substitutions only: Test-Bound -ParameterName Group -> carried
    // $__boundGroup flag, $Pscmdlet -> $__realCmdlet, the begin latch handled C#-side, and
    // explicit -FunctionName Move-DbaRegServer on Stop-Function (W1-090).
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Name, $ServerName, $Group, $InputObject, $EnableException, $__state, $__boundGroup, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Name, [string[]]$ServerName, [string]$Group, [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer[]]$InputObject, $EnableException, $__state, $__boundGroup, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # restore fn-scope locals mutated by earlier records
    if ($null -ne $__state) {
        $parentserver = $__state.parentserver
        $server = $__state.server
        $movetogroup = $__state.movetogroup
        $regserver = $__state.regserver
        $instance = $__state.instance
    }

    foreach ($instance in $SqlInstance) {
        $InputObject += Get-DbaRegServer -SqlInstance $instance -SqlCredential $SqlCredential -Name $Name -ServerName $ServerName
    }

    foreach ($regserver in $InputObject) {
        $parentserver = Get-RegServerParent -InputObject $regserver

        if ($null -eq $parentserver) {
            Stop-Function -Message "Something went wrong and it's hard to explain, sorry. This basically shouldn't happen." -Continue -FunctionName Move-DbaRegServer
        }

        $server = $regserver.ParentServer

        if (($__boundGroup)) {
            $movetogroup = Get-DbaRegServerGroup -SqlInstance $server -Group $Group

            if (-not $movetogroup) {
                Stop-Function -Message "$Group not found on $server" -Continue -FunctionName Move-DbaRegServer
            }
        } else {
            $movetogroup = Get-DbaRegServerGroup -SqlInstance $server -Id 1
        }

        if ($__realCmdlet.ShouldProcess($regserver.SqlInstance, "Moving $($regserver.Name) to $movetogroup")) {
            try {
                $null = $parentserver.ServerConnection.ExecuteNonQuery($regserver.ScriptMove($movetogroup).GetScript())
                Get-DbaRegServer -SqlInstance $server -Name $regserver.Name -ServerName $regserver.ServerName
                $parentserver.ServerConnection.Disconnect()
            } catch {
                Stop-Function -Message "Failed to move $($regserver.Name) to $Group on $($regserver.SqlInstance)" -ErrorRecord $_ -Continue -FunctionName Move-DbaRegServer
            }
        }
    }
    @{ __w3061State = @{ InputObject = $InputObject; parentserver = $parentserver; server = $server; movetogroup = $movetogroup; regserver = $regserver; instance = $instance } }
} $SqlInstance $SqlCredential $Name $ServerName $Group $InputObject $EnableException $__state $__boundGroup $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
