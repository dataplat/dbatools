#nullable enable

using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Disables Force Network Encryption setting in SQL Server Configuration Manager
/// </summary>
[Cmdlet(VerbsLifecycle.Disable, "DbaForceNetworkEncryption", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
[OutputType(typeof(PSObject))]
public sealed class DisableDbaForceNetworkEncryptionCommand : ForceNetworkEncryptionCmdlet
{
    protected override bool EnableEncryption => false;
}
