#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using XeSession = Microsoft.SqlServer.Management.XEvent.Session;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes Extended Events sessions from one or more SQL Server instances (by name, all non-system, or by
/// piped session object).
/// </summary>
/// <remarks>
/// The session resolution, the -Session/-AllSessions filtering, the Drop, and the result projection all run
/// the original dbatools PowerShell body VERBATIM inside the dbatools module scope rather than being
/// reimplemented in C#, so the engine decides the observable details.
///
/// The source begin block ONLY defines the nested helper Remove-XESessions, so per the begin-defined-nested-
/// function rule this is ported PROCESS-ONLY with that definition PREPENDED into the process hop (redefined
/// per record - identical, harmless).
///
/// SHOULDPROCESS: the ShouldProcess call lives INSIDE Remove-XESessions, which carries its OWN
/// [CmdletBinding(SupportsShouldProcess)] (default ConfirmImpact = Medium). It is kept VERBATIM (its own
/// $Pscmdlet) and NOT routed to $__realCmdlet - routing to the outer cmdlet (ConfirmImpact High) would
/// change the confirm-impact evaluated. Instead the process hop scriptblock is itself
/// [CmdletBinding(SupportsShouldProcess)] and -WhatIf/-Confirm are forwarded to it, so the nested function
/// inherits $WhatIfPreference/$ConfirmPreference exactly as it does from the outer function in the source.
/// The outer cmdlet's ConfirmImpact = High is a surface facet only (the outer never calls ShouldProcess).
///
/// The sole Stop-Function (Drop failure, inside the nested helper) is -Continue and carries no -FunctionName,
/// so it infers "Remove-XESessions" from the call stack in BOTH source and hop - kept verbatim (no
/// -FunctionName added). Nothing reads Test-FunctionInterrupt, so there is no interrupt and no Interrupted
/// guard. $InputObject is only READ (never accumulated), so no cross-record carry.
///
/// Three parameter sets: Session (default), All, Object. Each removed session is emitted before a later Drop
/// may fail under -EnableException (DEF-001), so the process hop uses InvokeScopedStreaming. Surface pinned
/// by migration/baselines/Remove-DbaXESession.json.
/// </remarks>
[Cmdlet(VerbsCommon.Remove, "DbaXESession", DefaultParameterSetName = "Session", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaXESessionCommand : DbaBaseCmdlet
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

    /// <summary>The name(s) of the Extended Events session(s) to remove.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Session")]
    [Alias("Sessions", "Name")]
    public object[]? Session { get; set; }

    /// <summary>Remove all non-system Extended Events sessions.</summary>
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
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block's nested Remove-XESessions function prepended VERBATIM, then the process block
    // VERBATIM. No edits: the nested ShouldProcess uses its own $Pscmdlet (Medium), and the nested
    // Stop-Function infers "Remove-XESessions" (no -FunctionName). The process hop scriptblock is
    // SupportsShouldProcess so the nested function inherits the forwarded WhatIf/Confirm preferences.
    private const string ProcessScript = """
param($InputObject, $SqlInstance, $SqlCredential, $Session, $AllSessions, $EnableException, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Microsoft.SqlServer.Management.XEvent.Session[]]$InputObject, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [object[]]$Session, $AllSessions, $EnableException)
    function Remove-XESessions {
        [CmdletBinding(SupportsShouldProcess)]
        param ([Microsoft.SqlServer.Management.XEvent.Session[]]$xeSessions)

        foreach ($xe in $xeSessions) {
            $instance = $xe.Parent.Name
            $session = $xe.Name

            if ($Pscmdlet.ShouldProcess("$instance", "Removing XEvent Session $session")) {
                try {
                    $xe.Drop()
                    [PSCustomObject]@{
                        ComputerName = $xe.Parent.ComputerName
                        InstanceName = $xe.Parent.ServiceName
                        SqlInstance  = $xe.Parent.DomainInstanceName
                        Session      = $session
                        Status       = "Removed"
                    }
                } catch {
                    Stop-Function -Message "Could not remove XEvent Session on $instance" -Target $session -ErrorRecord $_ -Continue
                }
            }
        }
    }

    if ($InputObject) {
        # avoid the collection issue
        $sessions = Get-DbaXESession -SqlInstance $InputObject.Parent -Session $InputObject.Name
        foreach ($item in $sessions) {
            Remove-XESessions $item
        }
    } else {
        foreach ($instance in $SqlInstance) {
            $xeSessions = Get-DbaXESession -SqlInstance $instance -SqlCredential $SqlCredential

            # Filter xeSessions based on parameters
            if ($Session) {
                $xeSessions = $xeSessions | Where-Object { $_.Name -in $Session }
            } elseif ($AllSessions) {
                $systemSessions = @('AlwaysOn_health', 'system_health', 'telemetry_xevents')
                $xeSessions = $xeSessions | Where-Object { $_.Name -notin $systemSessions }
            }

            Remove-XESessions $xeSessions
        }
    }
} $InputObject $SqlInstance $SqlCredential $Session $AllSessions $EnableException @__commonParameters 3>&1 2>&1
""";
}
