#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaLinkedServer.ps1 at refs/pins/dbatools-2026-10-22: the SMO linked servers of each instance, decorated with
// the instance and their logins' impersonation and remote user, one object per linked server.
/// <summary>Retrieves linked server configurations and connection details from SQL Server instances.</summary>
/// <para>
/// Pulls complete linked server information from one or more SQL Server instances, including remote server names, authentication methods, and security settings. This helps DBAs audit cross-server connections for compliance reporting, troubleshoot connectivity issues, and document distributed database architectures. Returns details about the remote server, product type, impersonation settings, and login mappings for each configured linked server.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaLinkedServer -SqlInstance DEV01
/// </code>
/// <para>
/// Returns all linked servers for the SQL Server instance DEV01
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaRegServer -SqlInstance DEV01 -Group SQLDEV | Get-DbaLinkedServer | Out-GridView
/// </code>
/// <para>
/// Returns all linked servers for a group of servers from SQL Server Central Management Server (CMS). Send output to GridView.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: LinkedServer, Linked
/// Author: Stephen Bennett, sqlnotesfromtheunderground.wordpress.com
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaLinkedServer" />
[Cmdlet(VerbsCommon.Get, "DbaLinkedServer", DefaultParameterSetName = "Default")]
public sealed class GetDbaLinkedServerCommand : DbaInstanceCmdlet
{
    // PS: the members the loop adds with Add-Member -Force, and the aliases Select-DefaultView adds the same way.
    private static readonly string[] AddedMembers = { "ComputerName", "InstanceName", "SqlInstance", "Impersonate", "RemoteUser", "RemoteServer", "Publisher" };

    /// <para>
    /// The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
    /// to be executed against multiple SQL Server instances.
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
    /// Specifies one or more linked server names to retrieve information for. Accepts an array of server names for filtering results.
    /// Use this when you need details on specific linked servers instead of all configured linked servers on the instance.
    /// </para>
    [Parameter(Position = 2)]
    public object[]? LinkedServer { get; set; }

    /// <para>
    /// Specifies one or more linked server names to exclude from the results. Accepts an array of server names to filter out.
    /// Use this when you want to skip specific linked servers, such as excluding test or deprecated connections from your inventory.
    /// </para>
    [Parameter(Position = 3)]
    public object[]? ExcludeLinkedServer { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential }
            //     catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            // Correction azure-unsupported: the pin connects without -AzureUnsupported and lists nothing for Azure SQL Database, where
            // linked servers do not exist; the port refuses it as Connect-DbaInstance -AzureUnsupported does.
            Server? server = ConnectInstance(instance, "Failure", azureUnsupported: true);
            if (server is null)
                continue;

            // PS: $lservers = $server.LinkedServers, then Name -in $LinkedServer and Name -notin $ExcludeLinkedServer when given.
            LinkedServerCollection? linkedServers = ReadLinkedServers(server);
            if (linkedServers is null)
                continue;

            bool include = LanguagePrimitives.IsTrue(LinkedServer);
            bool exclude = LanguagePrimitives.IsTrue(ExcludeLinkedServer);
            List<Microsoft.SqlServer.Management.Smo.LinkedServer> selected = new();
            foreach (Microsoft.SqlServer.Management.Smo.LinkedServer linked in linkedServers)
            {
                if (include && !ContainsName(LinkedServer!, linked.Name))
                    continue;
                if (exclude && ContainsName(ExcludeLinkedServer!, linked.Name))
                    continue;
                selected.Add(linked);
            }

            foreach (Microsoft.SqlServer.Management.Smo.LinkedServer linked in selected)
                WriteObject(Decorate(linked, server));
        }
    }

    // PS: $server.LinkedServers as the dot reads it: a fault of the SMO getter gives $null with no error (on Azure SQL Database,
    // where the getter throws UnsupportedVersionException: item evidence pin-azure-linkedserver and pin-azure-lsgetter, 2026-11-06,
    // both editions). Azure SQL Database is refused at the connection now; this keeps the dot read for any other getter fault.
    // Only the getter is read here; it opens no connection.
    private static LinkedServerCollection? ReadLinkedServers(Server server)
    {
        try
        {
            return server.LinkedServers;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            return null;
        }
    }

    // PS: the Add-Member -Force calls and Select-DefaultView of the loop. The members live on the SMO object itself, as the pin's do.
    private static PSObject Decorate(Microsoft.SqlServer.Management.Smo.LinkedServer linked, Server server)
    {
        PSObject output = PSObject.AsPSObject(linked);
        // PS: $ls.LinkedServerLogins.Impersonate and .RemoteUser.
        object? impersonate = EnumerateMember(linked, login => login.Impersonate);
        object? remoteUser = EnumerateMember(linked, login => login.RemoteUser);

        foreach (string member in AddedMembers)
            output.Properties.Remove(member);
        OutputHelper.AddInstanceProperties(output, server);
        output.Properties.Add(new PSNoteProperty("Impersonate", impersonate));
        output.Properties.Add(new PSNoteProperty("RemoteUser", remoteUser));
        OutputHelper.AddAliasProperty(output, "RemoteServer", "DataSource");
        OutputHelper.AddAliasProperty(output, "Publisher", "DistPublisher");
        OutputHelper.SetDefaultDisplayPropertySet(output,
            "ComputerName", "InstanceName", "SqlInstance", "Name", "RemoteServer", "ProductName", "Impersonate", "RemoteUser",
            "Publisher", "Distributor", "DateLastModified");
        return output;
    }

    // PS: member-access enumeration of a property over the logins collection: no login gives $null, one gives its value, more give an array.
    private static object? EnumerateMember(Microsoft.SqlServer.Management.Smo.LinkedServer linked, Func<LinkedServerLogin, object?> read)
    {
        List<object?> values = new();
        foreach (LinkedServerLogin login in linked.LinkedServerLogins)
            values.Add(read(login));
        if (values.Count == 0)
            return null;
        if (values.Count == 1)
            return values[0];
        return values.ToArray();
    }

    // PS: $_.Name -in $values: each value is the left operand of -eq, so the name converts to the value's type, ignoring case.
    // The shared NativeDatabaseSelection.ContainsInOperand is internal to dbatools.database, which dbatools.core cannot reach.
    private static bool ContainsName(object[] values, string name) // style-ok: cs-local-contains-name the shared NativeDatabaseSelection helper is internal to dbatools.database
    {
        foreach (object value in values)
        {
            if (LanguagePrimitives.Equals(value, name, true, CultureInfo.InvariantCulture))
                return true;
        }
        return false;
    }
}
