#nullable enable

using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaAgListener.ps1 at refs/pins/dbatools-2026-10-22. The nested
// Get-DbaAvailabilityGroup call is absorbed by the shared AvailabilityGroupReaderCmdlet base:
// its connect, HADR check, group filter and group decoration run there. The pinned call passes
// -EnableException:$EnableException, so the nested Stop-Function keeps the caller's switch
// (forwardEnableException) and throws under -EnableException.
/// <summary>Retrieves availability group listener configurations including IP addresses and port numbers.</summary>
/// <para>Retrieves availability group listener configurations from SQL Server instances, providing essential network details needed for client connections and troubleshooting. This function returns listener names, port numbers, IP configurations, and associated availability groups, which is crucial for validating listener setup and diagnosing connection issues. Use this when you need to document your AG infrastructure, verify listener configurations after setup, or troubleshoot client connectivity problems.</para>
/// <list type="alertSet">
///   <item>
///     <term></term>
///     <description>
///       <para>Tags: AG, HA</para>
///       <para>Author: Viorel Ciucu (@viorelciucu)</para>
///       <para>Website: https://dbatools.io</para>
///       <para>Copyright: (c) 2018 by dbatools, licensed under MIT</para>
///       <para>License: MIT https://opensource.org/licenses/MIT</para>
///     </description>
///   </item>
/// </list>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>Get-DbaAgListener -SqlInstance sql2017a</code>
///   <para>Returns all listeners found on sql2017a</para>
/// </example>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>Get-DbaAgListener -SqlInstance sql2017a -AvailabilityGroup AG-a</code>
///   <para>Returns all listeners found on sql2017a on sql2017a for the availability group AG-a</para>
/// </example>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>Get-DbaAvailabilityGroup -SqlInstance sql2017a -AvailabilityGroup OPP | Get-DbaAgListener</code>
///   <para>Returns all listeners found on sql2017a on sql2017a for the availability group OPP</para>
/// </example>
/// <seealso href="https://dbatools.io/Get-DbaAgListener"/>
[Cmdlet(VerbsCommon.Get, "DbaAgListener")]
[OutputType(typeof(AvailabilityGroupListener))]
public sealed class GetDbaAgListenerCommand : AvailabilityGroupReaderCmdlet
{
    // Positions follow the pinned function's automatic positional binding: every
    // non-switch parameter in declaration order.

    /// <para>The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.</para>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <para>Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).</para>
    /// <para>Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.</para>
    /// <para>For MFA support, please use Connect-DbaInstance.</para>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <para>Specifies which availability groups to include when retrieving listener information. Supports wildcards for pattern matching.</para>
    /// <para>Use this when you only need listener details for specific availability groups rather than all groups on the instance.</para>
    [Parameter(Position = 2)]
    public string[]? AvailabilityGroup { get; set; }

    /// <para>Specifies which availability group listeners to return by name. Accepts multiple listener names for filtering results.</para>
    /// <para>Use this when you need to examine specific listeners during troubleshooting or when documenting particular AG configurations.</para>
    [Parameter(Position = 3)]
    public string[]? Listener { get; set; }

    /// <para>Accepts availability group objects from Get-DbaAvailabilityGroup for pipeline operations.</para>
    /// <para>Use this when chaining commands to get listener details for specific availability groups you've already retrieved.</para>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public AvailabilityGroup[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet.

    protected override void ProcessRecord()
    {
        // The pinned process block has no Test-FunctionInterrupt check, so a stop in an earlier
        // record does not end later ones.
        if (!TestBound(nameof(SqlInstance), nameof(InputObject)))
        {
            StopFunction("You must supply either -SqlInstance or an Input Object");
            return;
        }

        // PS: $InputObject += Get-DbaAvailabilityGroup ... -EnableException:$EnableException - per record, the bound
        // groups first. Under -EnableException a failed lookup throws before the assignment, so nothing is output.
        List<AvailabilityGroup> groups = new List<AvailabilityGroup>();
        if (InputObject is not null)
        {
            groups.AddRange(InputObject);
        }
        if (SqlInstance is not null && LanguagePrimitives.IsTrue(SqlInstance))
        {
            // Correction azure-unsupported: Azure SQL Database is refused as Connect-DbaInstance
            // -AzureUnsupported does; availability groups and their listeners do not exist there.
            // The nested lookup's own Connect-DbaInstance gives its warning and record first, as in the pin
            // (probe errvar-pin-port-20261117, both editions).
            // Correction availabilitygroup-wildcards: the help documents -AvailabilityGroup wildcards, but the
            // nested Where-Object Name -in compares exactly; the shared matcher keeps exact names and adds wildcards.
            groups.AddRange(GetAvailabilityGroups(SqlInstance, SqlCredential, AvailabilityGroup, azureUnsupported: true, forwardEnableException: true, wildcardNames: true, nestedConnectRecord: true));
        }

        // PS: $agListeners = $InputObject.AvailabilityGroupListeners
        //     if (Test-Bound -ParameterName Listener) { $agListeners = $agListeners | Where-Object { $Listener -contains $_.Name } }
        bool filtered = TestBound(nameof(Listener));
        foreach (AvailabilityGroup? group in groups)
        {
            if (group is null)
            {
                continue;
            }
            foreach (AvailabilityGroupListener agListener in group.AvailabilityGroupListeners)
            {
                // A bound $null -Listener contains no name, so it passes nothing.
                if (filtered && (Listener is null || !ContainsName(Listener, agListener.Name)))
                {
                    continue;
                }

                // PS: $server = $agListener.Parent.Parent; Add-Member -Force ComputerName, InstanceName, SqlInstance,
                //     AvailabilityGroup; Select-DefaultView -Property $defaults
                AvailabilityGroup ag = agListener.Parent;
                Server server = ag.Parent;
                PSObject wrapped = PSObject.AsPSObject(agListener);
                foreach (string name in new[] { "ComputerName", "InstanceName", "SqlInstance", "AvailabilityGroup" })
                {
                    wrapped.Properties.Remove(name);
                }
                OutputHelper.AddInstanceProperties(wrapped, server);
                wrapped.Properties.Add(new PSNoteProperty("AvailabilityGroup", ag.Name));
                OutputHelper.SetDefaultDisplayPropertySet(wrapped,
                    "ComputerName", "InstanceName", "SqlInstance", "AvailabilityGroup", "Name", "PortNumber", "ClusterIPConfiguration");
                WriteObject(wrapped);
            }
        }
    }
}
