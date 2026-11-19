#nullable enable

using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves Extended Protection authentication settings from SQL Server network configuration.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaExtendedProtection", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low, DefaultParameterSetName = "Default")]
public sealed class GetDbaExtendedProtectionCommand : ExtendedProtectionCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; } = LocalComputer();

    /// <summary>
    /// Specifies alternative Windows credentials for connecting to the target computer to read registry values. This is for Windows computer access, not SQL Server authentication.
    /// Required when your current Windows account lacks administrative privileges on the target server or when connecting across domains.
    /// </summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <inheritdoc />
    protected override DbaInstanceParameter[]? Targets => SqlInstance;

    /// <inheritdoc />
    protected override PSCredential? WindowsCredential => Credential;

    /// <inheritdoc />
    protected override string ConfirmAction => "Connecting to {0} to modify the ExtendedProtection value in {1} for {2}";

    /// <inheritdoc />
    protected override ExtendedProtectionRegistry.Settings Apply(string computerName, string regRoot)
    {
        return ExtendedProtectionRegistry.Read(computerName, regRoot, Credential);
    }
}
