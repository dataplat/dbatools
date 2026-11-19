#nullable enable

using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Configures SQL Server to require encrypted connections from all clients by modifying the Windows registry
/// </summary>
[Cmdlet(VerbsLifecycle.Enable, "DbaForceNetworkEncryption", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low, DefaultParameterSetName = "Default")]
[OutputType(typeof(PSObject))]
public sealed class EnableDbaForceNetworkEncryptionCommand : ForceNetworkEncryptionCmdlet
{
    protected override bool EnableEncryption => true;
}
