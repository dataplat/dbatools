#nullable enable
#pragma warning disable CA1416 // Windows-only command: SQL WMI ManagedComputer and the WMI registry provider

using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves the Hide Instance setting from SQL Server registry configuration
/// </summary>
/// <para>
/// Retrieves the Hide Instance setting from the Windows registry for SQL Server instances. This security setting controls whether the instance appears when clients browse the network for available SQL Server instances. When Hide Instance is enabled, the SQL Server instance will not respond to broadcast requests from SQL Server Browser service, making it invisible to network discovery tools. DBAs use this setting as a security hardening measure to reduce the attack surface by preventing unauthorized discovery of SQL Server instances. Note that this requires Windows administrative access to the target server, not SQL Server permissions.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaHideInstance
/// </code>
/// <para>
/// Gets Hide Instance properties on the default (MSSQLSERVER) instance on localhost - requires (and checks for) RunAs admin.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaHideInstance -SqlInstance sql01\SQL2008R2SP2
/// </code>
/// <para>
/// Gets Force Network Encryption for the SQL2008R2SP2 on sql01. Uses Windows Credentials to both login and view the registry.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags:   Instance, Security
/// Author: Tracy Boggiano @TracyBoggiano, databaseuperhero.com
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaHideInstance" />
[Cmdlet(VerbsCommon.Get, "DbaHideInstance")]
public sealed class GetDbaHideInstanceCommand : NetworkSettingReaderCmdlet
{
    /// <para>
    /// The target SQL Server instance or instances. Defaults to localhost.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; } = LocalComputer();

    /// <para>
    /// Allows you to login to the computer (not sql instance) using alternative Windows credentials
    /// </para>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // PS: the scriptblock returns @{ ComputerName = $env:COMPUTERNAME; InstanceName = $args[2]; SqlInstance = $args[1];
    // HideInstance = ($hideinstance -eq $true) }.
    private static readonly string[] ReturnedNames = { "ComputerName", "InstanceName", "SqlInstance", "HideInstance" };

    // The order Windows PowerShell enumerates that literal on the host, measured as for Get-DbaForceNetworkEncryption (whose
    // five-key literal shares these three keys and was measured on the lab hosts by probe 6f29852d); see the item's notes.
    private static readonly string[] HostOrder = { "InstanceName", "SqlInstance", "ComputerName", "HideInstance" };

    protected override void ProcessRecord()
    {
        DbaInstanceParameter[]? targets = SqlInstance;
        if (Interrupted || targets is null)
        {
            return;
        }

        ProcessInstances(targets, Credential);
    }

    // PS: $HideInstance = (Get-ItemProperty -Path $regPath -Name HideInstance).HideInstance
    protected override PSObject ReadSetting(string computerName, ForceEncryptionResolver.Resolution service, object identity, PSCredential credential)
    {
        ForceEncryptionResolver.NetworkValue hidden = ForceEncryptionResolver.ReadNetworkValue(computerName, service.RegRoot, "HideInstance", credential);
        return ReturnedObject(computerName, ReturnedNames,
            new object?[] { hidden.ComputerName, service.InstanceName, identity, EqualsTrue(hidden.Value) }, HostOrder);
    }
}
