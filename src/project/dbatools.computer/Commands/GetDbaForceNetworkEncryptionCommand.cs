#nullable enable
#pragma warning disable CA1416 // Windows-only command: SQL WMI ManagedComputer and the WMI registry provider

using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves Force Network Encryption configuration from SQL Server's network settings
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaForceNetworkEncryption")]
public sealed class GetDbaForceNetworkEncryptionCommand : NetworkSettingReaderCmdlet
{
    /// <summary>The target SQL Server instance or instances. Defaults to localhost.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; } = LocalComputer();

    /// <summary>Allows you to login to the computer (not sql instance) using alternative Windows credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // PS: the scriptblock returns @{ ComputerName = $env:COMPUTERNAME; InstanceName = $args[2]; SqlInstance = $args[1];
    // ForceEncryption = ($forceencryption -eq $true); CertificateThumbprint = $cert }.
    private static readonly string[] ReturnedNames = { "ComputerName", "InstanceName", "SqlInstance", "ForceEncryption", "CertificateThumbprint" };

    // The host's order is measured (probe 6f29852d: a Windows PowerShell literal and its remote copy both enumerate
    // InstanceName, SqlInstance, ComputerName, CertificateThumbprint, ForceEncryption).
    private static readonly string[] HostOrder = { "InstanceName", "SqlInstance", "ComputerName", "CertificateThumbprint", "ForceEncryption" };

    protected override void ProcessRecord()
    {
        DbaInstanceParameter[]? targets = SqlInstance;
        if (Interrupted || targets is null)
        {
            return;
        }

        ProcessInstances(targets, Credential);
    }

    // PS: $cert = (Get-ItemProperty -Path $regPath -Name Certificate).Certificate
    //     $forceencryption = (Get-ItemProperty -Path $regPath -Name ForceEncryption).ForceEncryption
    protected override PSObject ReadSetting(string computerName, ForceEncryptionResolver.Resolution service, object identity, PSCredential credential)
    {
        ForceEncryptionResolver.NetworkValues values = ForceEncryptionResolver.ReadNetworkValues(computerName, service.RegRoot, credential);
        return ReturnedObject(computerName, ReturnedNames,
            new object?[] { values.ComputerName, service.InstanceName, identity, EqualsTrue(values.ForceEncryption), values.Certificate }, HostOrder);
    }
}
