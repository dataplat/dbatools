#nullable enable

using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Enables the Hide Instance setting to prevent SQL Server Browser service from advertising the instance.
/// </summary>
[Cmdlet(VerbsLifecycle.Enable, "DbaHideInstance", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low, DefaultParameterSetName = "Default")]
public sealed class EnableDbaHideInstanceCommand : HideInstanceCmdlet
{
    protected override bool EnableHiding => true;
}
