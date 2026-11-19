#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Management.Smo.Agent;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves SQL Server Agent proxy accounts and their associated credentials from target instances.
/// </summary>
/// <para>
/// Retrieves SQL Server Agent proxy accounts which allow job steps to execute under different security contexts than the SQL Agent service account.
/// This function is essential for security auditing, compliance reporting, and troubleshooting job step execution permissions.
/// Returns detailed information including proxy names, associated credentials, descriptions, and enabled status across multiple SQL Server instances.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentProxy -SqlInstance ServerA,ServerB\instanceB
/// </code>
/// <para>
/// Returns all SQL Agent proxies on serverA and serverB\instanceB
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; 'serverA','serverB\instanceB' | Get-DbaAgentProxy
/// </code>
/// <para>
/// Returns all SQL Agent proxies  on serverA and serverB\instanceB
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Agent, Proxy
/// Author: Chrissy LeMaire (@cl), netnerds.net
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaAgentProxy" />
[Cmdlet(VerbsCommon.Get, "DbaAgentProxy")]
[OutputType(typeof(ProxyAccount))]
public sealed class GetDbaAgentProxyCommand : DbaInstanceCmdlet
{
    /// <para>
    /// The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.
    /// </para>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <para>
    /// Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
    /// </para>
    /// <para>
    /// Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
    /// </para>
    /// <para>
    /// For MFA support, please use Connect-DbaInstance.
    /// </para>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <para>
    /// Specifies which SQL Agent proxy accounts to retrieve by name. Supports wildcards for pattern matching.
    /// Use this to filter results when you only need specific proxy accounts instead of all proxies on the instance.
    /// Common when auditing specific service accounts or troubleshooting particular job step failures.
    /// </para>
    [Parameter(Position = 2)]
    public string[]? Proxy { get; set; }

    /// <para>
    /// Specifies which SQL Agent proxy accounts to exclude from results by name. Supports wildcards for pattern matching.
    /// Useful when you want to review all proxies except certain ones, such as excluding system or test proxies from security audits.
    /// Can be combined with the Proxy parameter for fine-grained filtering.
    /// </para>
    [Parameter(Position = 3)]
    public string[]? ExcludeProxy { get; set; }

    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = ConnectInstance(instance, azureUnsupported: true);
            if (server is null)
                continue;

            WriteMessage(MessageLevel.Verbose, String.Format("Getting Edition from {0}", server));
            WriteMessage(MessageLevel.Verbose, String.Format("{0} is a {1}", server, server.Edition));
            if (server.Edition.StartsWith("Express", StringComparison.OrdinalIgnoreCase))
            {
                StopFunction(String.Format("There is no SQL Agent on {0}, it's a {1}", server, server.Edition), continueLoop: true);
                continue;
            }

            ProxyAccountCollection proxies = server.JobServer.ProxyAccounts;
            if (TestBound(nameof(Proxy)) || TestBound(nameof(ExcludeProxy)))
            {
                foreach (ProxyAccount proxy in FilterProxies(proxies))
                    WriteProxy(proxy, server);
            }
            else
            {
                foreach (ProxyAccount proxy in proxies)
                    WriteProxy(proxy, server);
            }
        }
    }

    private List<ProxyAccount> FilterProxies(ProxyAccountCollection proxies)
    {
        List<ProxyAccount> selected = new();
        if (TestBound(nameof(Proxy)))
        {
            // Materialize all pattern matches before output, preserving the pin's order and duplicates.
            foreach (string pattern in Proxy ?? Array.Empty<string>())
            {
                WildcardPattern include = new(pattern ?? String.Empty, WildcardOptions.IgnoreCase);
                foreach (ProxyAccount proxy in proxies)
                {
                    if (include.IsMatch(proxy.Name))
                        selected.Add(proxy);
                }
            }
        }
        else
        {
            foreach (ProxyAccount proxy in proxies)
                selected.Add(proxy);
        }

        if (TestBound(nameof(ExcludeProxy)))
        {
            foreach (string pattern in ExcludeProxy ?? Array.Empty<string>())
            {
                WildcardPattern exclude = new(pattern ?? String.Empty, WildcardOptions.IgnoreCase);
                selected.RemoveAll(proxy => exclude.IsMatch(proxy.Name));
            }
        }
        return selected;
    }

    private void WriteProxy(ProxyAccount proxy, Server server)
    {
        PSObject output = PSObject.AsPSObject(proxy);
        // Cached SMO objects can already carry decorations from an earlier invocation.
        output.Properties.Remove("ComputerName");
        output.Properties.Remove("InstanceName");
        output.Properties.Remove("SqlInstance");
        OutputHelper.AddInstanceProperties(output, server);
        OutputHelper.SetDefaultDisplayPropertySet(output,
            "ComputerName", "SqlInstance", "InstanceName", "Name", "ID", "CredentialID",
            "CredentialIdentity", "CredentialName", "Description", "IsEnabled");
        WriteObject(output);
    }
}
