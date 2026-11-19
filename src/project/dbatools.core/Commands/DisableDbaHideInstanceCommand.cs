#nullable enable

using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Makes SQL Server instances visible to network discovery by disabling the Hide Instance registry setting.
/// </summary>
[Cmdlet(VerbsLifecycle.Disable, "DbaHideInstance", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low, DefaultParameterSetName = "Default")]
public sealed class DisableDbaHideInstanceCommand : HideInstanceCmdlet
{
    protected override bool EnableHiding => false;
}
