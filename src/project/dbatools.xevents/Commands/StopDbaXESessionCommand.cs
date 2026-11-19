#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using XeSession = Microsoft.SqlServer.Management.XEvent.Session;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Stops running Extended Events sessions on one or more SQL Server instances (by name, all non-system, or
/// by piped session object).
/// </summary>
/// <remarks>
/// The session resolution, the -Session/-AllSessions filtering, the Stop, and the re-query all run the
/// original dbatools PowerShell body VERBATIM inside the dbatools module scope rather than being
/// reimplemented in C#, so the engine decides the observable details.
///
/// The source begin block ONLY defines the nested helper Stop-XESessions, so it is ported PROCESS-ONLY with
/// that definition PREPENDED into the process hop (redefined per record - harmless).
///
/// SHOULDPROCESS is in THREE places, handled two ways:
///  - The TWO process-block ShouldProcess calls use the OUTER $Pscmdlet, routed to $__realCmdlet (this,
///    ConfirmImpact Medium) so the "Yes to All" state persists across pipeline records (the outer cmdlet is
///    one instance; a fresh nested $PSCmdlet per record would reset it).
///  - The ShouldProcess INSIDE Stop-XESessions uses the nested function's OWN $Pscmdlet (its own
///    [CmdletBinding(SupportsShouldProcess)], also Medium) and is kept VERBATIM - its Yes-to-All is per
///    Stop-XESessions call in both source and hop.
/// The process hop scriptblock is [CmdletBinding(SupportsShouldProcess)] so the nested function inherits the
/// forwarded WhatIf/Confirm preferences. The nested Write-Message/Stop-Function carry no -FunctionName, so
/// they infer "Stop-XESessions" from the call stack in both source and hop (kept verbatim).
///
/// Nothing reads Test-FunctionInterrupt (the one Stop-Function is -Continue), so no interrupt/Interrupted
/// guard. $InputObject is only READ, so no cross-record carry. Three parameter sets: Session (default), All,
/// Object. Each re-queried session is emitted before a later Stop may fail under -EnableException (DEF-001),
/// so the process hop uses InvokeScopedStreaming. Surface pinned by
/// migration/baselines/Stop-DbaXESession.json.
/// </remarks>
[Cmdlet(VerbsLifecycle.Stop, "DbaXESession", DefaultParameterSetName = "Session", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class StopDbaXESessionCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 1, ParameterSetName = "Session")]
    [Parameter(Mandatory = true, Position = 1, ParameterSetName = "All")]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(ParameterSetName = "Session")]
    [Parameter(ParameterSetName = "All")]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The name(s) of the Extended Events session(s) to stop.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Session")]
    [Alias("Sessions")]
    public object[]? Session { get; set; }

    /// <summary>Stop all non-system Extended Events sessions.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "All")]
    public SwitchParameter AllSessions { get; set; }

    /// <summary>Extended Events Session objects piped in (e.g. from Get-DbaXESession).</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, ParameterSetName = "Object")]
    public XeSession[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare (no set named), which
    // reflects as __AllParameterSets and matches the inherited [Parameter]; no per-set override needed.

    protected override void ProcessRecord()
    {
        NestedCommand.InvokeScopedStreaming(this, item =>
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
        }, ProcessScript,
            InputObject, SqlInstance, SqlCredential, Session, AllSessions.ToBool(), EnableException.ToBool(),
            this, NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the nested Stop-XESessions function prepended VERBATIM (its ShouldProcess uses the nested $Pscmdlet;
    // Write-Message/Stop-Function keep verbatim call-stack attribution), then the process block VERBATIM apart
    // from the two outer $Pscmdlet.ShouldProcess -> $__realCmdlet.ShouldProcess.
    private const string ProcessScript = """
param($InputObject, $SqlInstance, $SqlCredential, $Session, $AllSessions, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Microsoft.SqlServer.Management.XEvent.Session[]]$InputObject, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [object[]]$Session, $AllSessions, $EnableException, $__realCmdlet)
    function Stop-XESessions {
        [CmdletBinding(SupportsShouldProcess)]
        param ([Microsoft.SqlServer.Management.XEvent.Session[]]$xeSessions)

        foreach ($xe in $xeSessions) {
            $instance = $xe.Parent.Name
            $session = $xe.Name
            if ($xe.isRunning) {
                Write-Message -Level Verbose -Message "Stopping XEvent Session $session on $instance."
                if ($Pscmdlet.ShouldProcess("$instance", "Stopping XEvent Session $session")) {
                    try {
                        $xe.Stop()
                    } catch {
                        Stop-Function -Message "Could not stop XEvent Session on $instance" -Target $session -ErrorRecord $_ -Continue
                    }
                }
            } else {
                Write-Message -Level Warning -Message "$session on $instance is already stopped"
            }
            Get-DbaXESession -SqlInstance $xe.Parent -Session $session
        }
    }

    if ($InputObject) {
        if ($__realCmdlet.ShouldProcess("Configuring XEvent Sessions to stop")) {
            Stop-XESessions $InputObject
        }
    } else {
        foreach ($instance in $SqlInstance) {
            $xeSessions = Get-DbaXESession -SqlInstance $instance -SqlCredential $SqlCredential

            # Filter xesessions based on parameters
            if ($Session) {
                $xeSessions = $xeSessions | Where-Object { $_.Name -in $Session }
            } elseif ($AllSessions) {
                $systemSessions = @('AlwaysOn_health', 'system_health', 'telemetry_xevents')
                $xeSessions = $xeSessions | Where-Object { $_.Name -notin $systemSessions }
            }

            if ($__realCmdlet.ShouldProcess("$instance", "Configuring XEvent Session $xeSessions to Stop")) {
                Stop-XESessions $xeSessions
            }
        }
    }
} $InputObject $SqlInstance $SqlCredential $Session $AllSessions $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
