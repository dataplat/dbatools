#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaInstanceAuditSpecification.ps1 at refs/pins/dbatools-2026-10-22: the connection, then each server audit
// specification of the instance with the instance notes and the default view.
/// <summary>Retrieves server-level audit specifications from SQL Server instances for compliance and security monitoring</summary>
/// <para>
/// Returns all server-level audit specifications configured on SQL Server instances, including their enabled status, associated audit names, and configuration details. This helps DBAs inventory audit configurations for compliance reporting, security assessments, and ensuring proper event monitoring is in place. Server audit specifications define which events are captured by SQL Server Audit at the instance level, such as login attempts, permission changes, and database access patterns.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaInstanceAuditSpecification -SqlInstance localhost
/// </code>
/// <para>
/// Returns all Security Audit Specifications on the local default SQL Server instance
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaInstanceAuditSpecification -SqlInstance localhost, sql2016
/// </code>
/// <para>
/// Returns all Security Audit Specifications for the local and sql2016 SQL Server instances
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Audit, Security, SqlAudit
/// Author: Garry Bargsley (@gbargsley), blog.garrybargsley.com
/// </para>
/// <para>
/// dbatools PowerShell module (https://dbatools.io)
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaInstanceAuditSpecification" />
[Cmdlet(VerbsCommon.Get, "DbaInstanceAuditSpecification")]
[OutputType(typeof(ServerAuditSpecification))]
public sealed class GetDbaInstanceAuditSpecificationCommand : DbaInstanceCmdlet
{
    // PS: Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, ID, Name, AuditName, Enabled, CreateDate, DateLastModified, Guid
    private static readonly string[] DisplaySet =
    {
        "ComputerName", "InstanceName", "SqlInstance", "ID", "Name", "AuditName", "Enabled", "CreateDate", "DateLastModified", "Guid"
    };

    /// <para>
    /// The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
    /// to be executed against multiple SQL Server instances.
    /// </para>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
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

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    /// <summary>Reports the server audit specifications of each instance in this record.</summary>
    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10 }
            //     catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            // Correction azure-unsupported: server audit specifications do not exist in Azure SQL Database, where the pin read
            // a null collection and returned nothing with no message; the port refuses it as -AzureUnsupported does.
            Server? server = ConnectInstance(instance, "Failure", minimumVersion: 10, azureUnsupported: true);
            if (server is null)
            {
                continue;
            }

            // PS: foreach ($auditSpecification in $server.ServerAuditSpecifications) { ... }
            List<ServerAuditSpecification>? specifications = ReadSpecifications(server);
            if (specifications is null)
            {
                continue;
            }

            foreach (ServerAuditSpecification specification in specifications)
            {
                WriteObject(Decorate(specification, server));
            }
        }
    }

    // SMO loads the collection when the foreach enumerates it. The pin has no try around that read: a plain call writes the
    // record and goes on with the next instance, a caller's try catches it, -EnableException stops here.
    private List<ServerAuditSpecification>? ReadSpecifications(Server server)
    {
        List<ServerAuditSpecification> rows = new();
        IEnumerator? enumerator = null;
        ErrorRecord fault;
        try
        {
            ServerAuditSpecificationCollection collection = server.ServerAuditSpecifications;
            enumerator = LanguagePrimitives.GetEnumerator(collection);
            while (enumerator is not null && enumerator.MoveNext())
            {
                rows.Add((ServerAuditSpecification)enumerator.Current);
            }

            return rows;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // The engine's record when the failure carries one (ExceptionInGetEnumerator); otherwise the record a failing
            // MoveNext gives (BadEnumeration, InvalidOperation, the enumerator as target).
            if (failure is IContainsErrorRecord container && container.ErrorRecord is not null)
            {
                fault = new ErrorRecord(container.ErrorRecord, failure);
            }
            else
            {
                RuntimeException enumeration = new(string.Format(CultureInfo.InvariantCulture,
                    "An error occurred while enumerating through a collection: {0}.", failure.Message), failure);
                fault = new ErrorRecord(enumeration, "BadEnumeration", ErrorCategory.InvalidOperation, enumerator);
            }
        }

        SurfaceFault(fault);
        return null;
    }

    // A read in the pin's body, which has no try around it: a plain call writes it and goes on, a caller's try catches it,
    // -EnableException stops here.
    private void SurfaceFault(ErrorRecord fault)
    {
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams a read's statement fault, outside Stop-Function, as in the pin
        }

        StatementFault.Surface(this, fault);
    }

    // PS: Add-Member -Force of ComputerName, InstanceName and SqlInstance, then Select-DefaultView. -Force replaces the notes
    // an earlier call left on the same SMO object.
    private static PSObject Decorate(ServerAuditSpecification specification, Server server)
    {
        PSObject output = PSObject.AsPSObject(specification);
        foreach (string name in new[] { "ComputerName", "InstanceName", "SqlInstance" })
        {
            output.Properties.Remove(name);
        }

        OutputHelper.AddInstanceProperties(output, server);
        OutputHelper.SetDefaultDisplayPropertySet(output, DisplaySet);
        return output;
    }
}
