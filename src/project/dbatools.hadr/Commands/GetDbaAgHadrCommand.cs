#nullable enable

using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves the High Availability Disaster Recovery (HADR) service status for SQL Server instances.
/// </summary>
/// <para>
/// Checks whether Availability Groups are enabled at the service level on SQL Server instances. This is a prerequisite for creating and managing Availability Groups, as HADR must be enabled before you can configure any AG functionality. Returns the computer name, instance name, and the current HADR enabled status (true/false) for each specified instance, making it useful for environment audits and troubleshooting AG setup issues.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgHadr -SqlInstance sql2016
/// </code>
/// <para>
/// Returns a status of the Hadr setting for sql2016 SQL Server instance.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: AG, HA
/// Author: Shawn Melton (@wsmelton), wsmelton.github.io
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaAgHadr" />
[Cmdlet(VerbsCommon.Get, "DbaAgHadr")]
public sealed class GetDbaAgHadrCommand : DbaInstanceCmdlet
{
    /// <para>
    /// The target SQL Server instance or instances.
    /// </para>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
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
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        if (SqlInstance is null)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { Connect-DbaInstance } catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            // Upstream correction azure-unsupported: Always On availability groups do not exist in Azure SQL Database, so the
            // connection refuses it as Connect-DbaInstance -AzureUnsupported does instead of reporting an HADR state.
            Server? server = ConnectInstance(instance, "Failure", azureUnsupported: true);
            if (server is null)
                continue;

            // PS: Add-Member -Force (ComputerName, InstanceName, SqlInstance) on the server itself, then Select-DefaultView.
            PSObject wrapped = PSObject.AsPSObject(server);
            ReplaceNoteProperty(wrapped, "ComputerName", SmoServerExtensions.GetComputerName(server));
            ReplaceNoteProperty(wrapped, "InstanceName", server.ServiceName);
            ReplaceNoteProperty(wrapped, "SqlInstance", SmoServerExtensions.GetDomainInstanceName(server));
            OutputHelper.SetDefaultDisplayPropertySet(wrapped, "ComputerName", "InstanceName", "SqlInstance", "IsHadrEnabled");
            WriteObject(wrapped);
        }
    }

    // Add-Member -Force replaces an existing member of the same name; a reused server already carries these notes.
    private static void ReplaceNoteProperty(PSObject wrapped, string name, object? value)
    {
        if (wrapped.Properties[name] is PSNoteProperty)
            wrapped.Properties.Remove(name);
        wrapped.Properties.Add(new PSNoteProperty(name, value));
    }
}
