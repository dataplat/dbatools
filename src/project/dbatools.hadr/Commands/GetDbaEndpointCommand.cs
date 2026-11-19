#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using System.Net;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using ConnectionFailureException = Microsoft.SqlServer.Management.Common.ConnectionFailureException;
using SmoEndpoint = Microsoft.SqlServer.Management.Smo.Endpoint;
using SqlException = Microsoft.Data.SqlClient.SqlException;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaEndpoint.ps1 at refs/pins/dbatools-2026-10-22: the connection, the -Endpoint and -Type filters, the Fqdn the
// listener gives, and the notes and default view on each endpoint. Measured: evidence/pin-endpoint-20261104.txt.
/// <summary>Retrieves SQL Server endpoints with network connectivity details for troubleshooting and documentation.</summary>
/// <para>
/// Retrieves all SQL Server endpoints including DatabaseMirroring, ServiceBroker, Soap, and TSql types with their network configuration details. This function provides essential information for troubleshooting connectivity issues, documenting high availability setups, and performing security audits. It automatically resolves DNS names and constructs connection strings (FQDN format) for endpoints that have TCP listeners, making it easier to validate network accessibility and plan firewall configurations.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaEndpoint -SqlInstance localhost
/// </code>
/// <para>
/// Returns all endpoints on the local default SQL Server instance
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaEndpoint -SqlInstance localhost, sql2016
/// </code>
/// <para>
/// Returns all endpoints for the local and sql2016 SQL Server instances
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Endpoint
/// Author: Garry Bargsley (@gbargsley), blog.garrybargsley.com
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaEndpoint" />
[Cmdlet(VerbsCommon.Get, "DbaEndpoint")]
[OutputType(typeof(SmoEndpoint))]
public sealed class GetDbaEndpointCommand : DbaInstanceCmdlet
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
    /// Specifies one or more endpoint names to retrieve instead of returning all endpoints. Accepts exact endpoint names and supports multiple values.
    /// Use this when you need to examine specific endpoints like 'Mirroring' or 'AlwaysOn_health' rather than scanning all configured endpoints.
    /// </para>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Endpoint { get; set; }

    /// <para>
    /// Filters endpoints by their functional type. Valid options: DatabaseMirroring, ServiceBroker, Soap, and TSql.
    /// Use this to focus on specific endpoint categories, such as 'DatabaseMirroring' for Always On AG troubleshooting or 'ServiceBroker' for message queuing configurations.
    /// </para>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    [ValidateSet("DatabaseMirroring", "ServiceBroker", "Soap", "TSql")]
    public string[]? Type { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    /// <summary>Reports the endpoints of each instance in this record.</summary>
    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = ConnectInstance(instance, "Failure", 9);
            if (server is null)
                continue;

            WriteEndpoints(server);
        }
    }

    private void WriteEndpoints(Server server)
    {
        // PS: $endpoints = $endpoints | Where-Object ... reads the whole collection. Where that read faults, nothing is assigned, so the
        // next statement reads the collection again and faults again: one record for each, measured on Azure SQL Database.
        IEnumerable endpoints;
        try
        {
            endpoints = server.Endpoints;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // The pin's $endpoints would keep the previous instance's list here, and stamp it with this server's names. Not reached on Azure SQL Database, where this read succeeds.
            SurfaceFault(StatementFault.Record(failure, failure.GetType().Name));
            return;
        }

        if (LanguagePrimitives.IsTrue(Endpoint))
            endpoints = ReadEndpoints(endpoints, row => MatchesAny(row.Name, Endpoint!)) ?? endpoints;
        if (LanguagePrimitives.IsTrue(Type))
            endpoints = ReadEndpoints(endpoints, row => MatchesAny(row.EndpointType.ToString(), Type!)) ?? endpoints;

        List<SmoEndpoint>? rows = ReadEndpoints(endpoints, null);
        if (rows is null)
            return;

        foreach (SmoEndpoint row in rows)
        {
            WriteMessage(MessageLevel.Verbose, "Getting endpoint " + row.Name + " on " + server.Name);
            WriteObject(Decorate(row, server));
        }
    }

    // SMO loads the collection when it is enumerated, so Azure SQL Database, which has no endpoints to read, faults here. The pin has no try
    // around these reads: a plain call writes the record and goes on, a caller's try catches it, -EnableException stops here.
    private List<SmoEndpoint>? ReadEndpoints(IEnumerable endpoints, Predicate<SmoEndpoint>? keep)
    {
        List<SmoEndpoint> rows = new();
        IEnumerator? enumerator = null;
        ErrorRecord fault;
        try
        {
            enumerator = LanguagePrimitives.GetEnumerator(endpoints);
            while (enumerator is not null && enumerator.MoveNext())
            {
                SmoEndpoint row = (SmoEndpoint)enumerator.Current;
                if (keep is null || keep(row))
                    rows.Add(row);
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
                RuntimeException enumeration = new(String.Format(CultureInfo.InvariantCulture,
                    "An error occurred while enumerating through a collection: {0}.", failure.Message), failure);
                fault = new ErrorRecord(enumeration, "BadEnumeration", ErrorCategory.InvalidOperation, enumerator);
            }
        }

        SurfaceFault(fault);
        return null;
    }

    // A read in the pin's body, which has no try around it: a plain call writes it and goes on, a caller's try catches it, -EnableException stops here.
    private void SurfaceFault(ErrorRecord fault)
    {
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams a read's statement fault, outside Stop-Function, as in the pin
        }

        StatementFault.Surface(this, fault);
    }

    private PSObject Decorate(SmoEndpoint row, Server server)
    {
        bool reported = false;
        object? tcp = ListenerMember(ListenerMember(row, "Protocol", row.Name, ref reported), "Tcp", row.Name, ref reported);
        object? listenerAddress = ListenerMember(tcp, "ListenerIPAddress", row.Name, ref reported);
        object? listenerPort = ListenerMember(tcp, "ListenerPort", row.Name, ref reported);
        bool listens = LanguagePrimitives.IsTrue(listenerPort);
        string? fqdn = listens ? "TCP://" + Text(ResolveHost(listenerAddress, server)) + ":" + Text(listenerPort) : null;

        // PS: Add-Member -Force replaces the notes an earlier call left on the same object.
        PSObject output = PSObject.AsPSObject(row);
        foreach (string name in new[] { "ComputerName", "InstanceName", "SqlInstance", "Fqdn", "IPAddress", "Port" })
            output.Properties.Remove(name);
        OutputHelper.AddInstanceProperties(output, server);
        output.Properties.Add(new PSNoteProperty("Fqdn", fqdn));
        output.Properties.Add(new PSNoteProperty("IPAddress", listenerAddress));
        output.Properties.Add(new PSNoteProperty("Port", listenerPort));

        if (listens)
        {
            OutputHelper.SetDefaultDisplayPropertySet(output,
                "ComputerName", "InstanceName", "SqlInstance", "ID", "Name", "IPAddress", "Port", "EndpointState", "EndpointType", "Owner", "IsAdminEndpoint", "Fqdn", "IsSystemObject");
        }
        else
        {
            OutputHelper.SetDefaultDisplayPropertySet(output,
                "ComputerName", "InstanceName", "SqlInstance", "ID", "Name", "EndpointState", "EndpointType", "Owner", "IsAdminEndpoint", "Fqdn", "IsSystemObject");
        }
        return output;
    }

    // PS: the host part of the Fqdn. A listener bound to one address names that address, one bound to all names the machine.
    private static object? ResolveHost(object? listenerAddress, Server server)
    {
        if (!IPAddress.Any.Equals(listenerAddress))
            return listenerAddress;

        object? netName = Member(server, "NetName");
        if (String.Equals(Text(Member(server, "HostPlatform")), "Linux", StringComparison.OrdinalIgnoreCase) && LanguagePrimitives.IsTrue(netName))
            return netName;

        string computerName = SmoServerExtensions.GetComputerName(server);
        if (computerName.Contains("."))
            return computerName;

        try
        {
            return Dns.GetHostEntry(computerName).HostName;
        }
        catch (Exception entryFailure) when (entryFailure is not PipelineStoppedException)
        {
            try
            {
                // As in the pin, several addresses join with spaces in the text. Not reached in the lab: both lookups resolve the same name.
                return Dns.GetHostAddresses(computerName);
            }
            catch (Exception addressFailure) when (addressFailure is not PipelineStoppedException)
            {
                return computerName;
            }
        }
    }

    // PS: $x.name in the pin's reads: nothing for a null, a missing property or one that fails to read. Non-TCP endpoints give no listener this way, with no error.
    private static object? Member(object? instance, string name)
    {
        if (instance is null)
            return null;

        try
        {
            return PSObject.AsPSObject(instance).Properties[name]?.Value;
        }
        catch (GetValueException)
        {
            return null;
        }
    }

    // PS: $end.Protocol.Tcp.ListenerPort and the like read as nothing, with no record, wherever the read fails. Kept for a non-TCP
    // endpoint (PropertyNotSetException) and for a read refused on an open connection, such as a home database that denies CONNECT
    // (SqlException 916, severity 14), as measured. Corrected for a connection that is lost and cannot come back, where the pin's rows
    // go out as if they had no listener and the user is not told (corrections.json, listener-read-fault): one record for each row, the
    // row still goes out. Measured on the pin, both editions: evidence/listener-fault-pin-*-20261104.txt, listener-fault2-*-20261104.txt.
    private object? ListenerMember(object? instance, string name, string endpointName, ref bool reported)
    {
        if (instance is null)
            return null;

        ErrorRecord fault;
        try
        {
            return PSObject.AsPSObject(instance).Properties[name]?.Value;
        }
        catch (GetValueException failure)
        {
            if (reported || !ConnectionLost(failure))
                return null;
            reported = true;
            fault = new ErrorRecord(failure, "ListenerReadFailed", ErrorCategory.ConnectionError, endpointName);
        }

        SurfaceFault(fault);
        return null;
    }

    // What the measure tells apart. The first read after the loss: a transport error of severity 20 or more, which closes the
    // connection (SqlException 10054, class 20), or SqlClient's failed recovery of the idle connection, a SqlException (number 0,
    // class 11) whose inner exception is the reconnect's failed login (evidence/listener-fault3-*-20261104.txt). Later reads: SMO's
    // reconnect fails (ConnectionFailureException). A read refused on an open connection (916, class 14) holds no inner SqlException,
    // and a session SMO can open again reads with no fault. The nested-SqlException rule is inferred from those probes, on connections
    // that do not pool; SqlClient does not document it (corrections.json, listener-read-limits).
    private static bool ConnectionLost(Exception failure)
    {
        for (Exception? cause = failure; cause is not null; cause = cause.InnerException)
        {
            if (cause is ConnectionFailureException)
                return true;
            if (cause is SqlException server && (server.Class >= 20 || server.InnerException is SqlException))
                return true;
        }
        return false;
    }

    private static string? Text(object? value)
    {
        return LanguagePrimitives.ConvertTo<string>(value);
    }

    // PS: Where-Object Name -In $values, a whole value without regard to case.
    private static bool MatchesAny(string value, string[] values)
    {
        return Array.Exists(values, item => LanguagePrimitives.Equals(value, item, true, CultureInfo.InvariantCulture));
    }
}
