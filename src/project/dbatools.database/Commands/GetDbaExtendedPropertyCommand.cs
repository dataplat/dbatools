#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

// Retrieves extended property objects from SQL Server objects directly through SMO. Port of
// public/Get-DbaExtendedProperty.ps1.
/// <summary>Retrieves custom metadata and documentation stored as extended properties on SQL Server objects</summary>
[Cmdlet(VerbsCommon.Get, "DbaExtendedProperty")]
public sealed class GetDbaExtendedPropertyCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to gather extended properties from (when -SqlInstance is used).</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>Filter to the specified extended property/properties by name.</summary>
    [Parameter(Position = 3)]
    [Alias("Property")]
    public string[]? Name { get; set; }

    /// <summary>Object(s) piped in whose extended properties are returned.</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public PSObject[]? InputObject { get; set; }

    private const string ServerNameSql = "SELECT @@SERVERNAME AS servername";

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // PS: if ($SqlInstance) { $InputObject = Get-DbaDatabase ... | Where-Object IsAccessible }
        // Upstream correction (wrong data): that assignment replaces the piped objects with the gathered
        // databases, so an object given through -InputObject alongside -SqlInstance was silently dropped.
        // The given objects are now kept, followed by this record's accessible gathered databases.
        List<object?> objects = new();
        if (InputObject is not null)
            objects.AddRange(InputObject);
        if (LanguagePrimitives.IsTrue(SqlInstance))
        {
            foreach (SmoDatabase gathered in NativeDatabaseSelection.Gather(this, SqlInstance, SqlCredential, Database, null,
                server => SetActiveConnection(server.ConnectionContext), () => Interrupted))
            {
                if (gathered.IsAccessible)
                    objects.Add(gathered);
            }
        }

        foreach (object? item in objects)
        {
            if (Interrupted)
                return;
            PSObject? source = item is null ? null : PSObject.AsPSObject(item);
            object? props = ReadProperty(source, "ExtendedProperties");
            if (props is null)
            {
                // The pinned message names an $instance that the function never defines, so the
                // string expansion reads it up-scope.
                WriteMessage(MessageLevel.Verbose, String.Format("No extended properties exist in the {0} on {1}", source,
                    LanguagePrimitives.ConvertTo(ReadUnassigned("instance"), typeof(string), CultureInfo.InvariantCulture)), source);
                continue;
            }

            List<object?> selected = new();
            foreach (object? prop in Enumerate(props))
            {
                // PS: Where-Object Name -in $Name
                if (LanguagePrimitives.IsTrue(Name) && !NativeDatabaseSelection.ContainsName(Name, ReadProperty(prop, "Name") as string ?? ""))
                    continue;
                selected.Add(prop);
            }

            // Upstream correction (wrong data): the source assigns $server only while rebuilding missing
            // instance names, so a property of an object that already carries them reported $null, a
            // caller's $global:server or an earlier object's server as its Server connection. Every
            // object's properties now carry that object's own connection parent (Get-ConnectionParent).
            object? connectionParent = null;
            // The input object is generic, so the instance names are rebuilt when any is missing.
            object? computerName = ReadProperty(source, "ComputerName");
            object? instanceName = ReadProperty(source, "InstanceName");
            object? sqlName = ReadProperty(source, "SqlInstance");
            if (!LanguagePrimitives.IsTrue(computerName) || !LanguagePrimitives.IsTrue(instanceName) || !LanguagePrimitives.IsTrue(sqlName))
            {
                connectionParent = ConnectionParent(source);
                // PS: $servername = $server.Query(...).servername. A failed call writes its record and the pin goes on
                // with the statements below. Upstream correction (wrong data, no-left-over-server-name): the pin's
                // $servername then still holds the previous object's server name, which labelled this object's
                // properties with another server; here the names the query could not supply stay null.
                object? serverName = QueryServerName(connectionParent, out _);
                // PS: each cast is its own statement; a failed one writes its record and leaves the name as it was.
                if (!LanguagePrimitives.IsTrue(computerName))
                {
                    DbaInstanceParameter? parsed = ConvertServerName(serverName, out bool castFaulted);
                    if (!castFaulted)
                        computerName = parsed?.ComputerName;
                }
                if (!LanguagePrimitives.IsTrue(instanceName))
                {
                    DbaInstanceParameter? parsed = ConvertServerName(serverName, out bool castFaulted);
                    if (!castFaulted)
                        instanceName = parsed?.InstanceName;
                }
                if (!LanguagePrimitives.IsTrue(sqlName))
                    sqlName = serverName;
            }
            else if (selected.Count > 0)
            {
                connectionParent = ConnectionParent(source);
            }

            foreach (object? prop in selected)
            {
                if (prop is null)
                    continue;
                PSObject output = PSObject.AsPSObject(prop);
                // Add-Member -Force replaces notes left on the same SMO object by an earlier call.
                foreach (string property in new[] { "ComputerName", "InstanceName", "SqlInstance", "ParentName", "Type", "Server" })
                    output.Properties.Remove(property);
                output.Properties.Add(new PSNoteProperty("ComputerName", computerName)); // style-ok: cs-output-props the source rebuilds these values from the generic input object
                output.Properties.Add(new PSNoteProperty("InstanceName", instanceName)); // style-ok: cs-output-props the source rebuilds these values from the generic input object
                output.Properties.Add(new PSNoteProperty("SqlInstance", sqlName)); // style-ok: cs-output-props the source rebuilds these values from the generic input object
                output.Properties.Add(new PSNoteProperty("ParentName", ReadProperty(source, "Name")));
                output.Properties.Add(new PSNoteProperty("Type", source!.BaseObject.GetType().Name));
                output.Properties.Add(new PSNoteProperty("Server", connectionParent));
                OutputHelper.SetDefaultDisplayPropertySet(output,
                    "ComputerName", "InstanceName", "SqlInstance", "ParentName", "Type", "Name", "Value");
                WriteObject(output);
            }
        }
    }

    /// <summary>
    /// PS: $object.Name with non-strict semantics: a missing member reads as null, and so does a member whose getter
    /// throws: the engine's member access drops the getter's exception, writes no record and gives null, with or without
    /// a caller try (the native test measures that statement on each leg).
    /// </summary>
    private static object? ReadProperty(object? item, string name)
    {
        if (item is null)
            return null;
        PSPropertyInfo? property = PSObject.AsPSObject(item).Properties[name];
        if (property is null)
            return null;
        try
        {
            return property.Value;
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception)
        {
            return null;
        }
    }

    // Keep-going section, point 3, with the StatementFault section: -EnableException stops here with the record, where
    // the pin writes it and goes on; -ErrorAction Stop has the effect PowerShell gives WriteError.
    private void ReportFault(ErrorRecord fault)
    {
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams a statement fault of the pin, outside Stop-Function
        }

        // A plain call goes on; under a caller try the record stops the command, as the fault stops the pin's statement.
        StatementFault.Surface(this, fault);
    }

    /// <summary>
    /// PS: reading a variable the function never assigned. The lookup leaves the function scope
    /// for the dbatools module scope, which does not define $instance, and then the global scope;
    /// a caller's own local scopes are not on that chain. So a caller's $global:instance is what
    /// the source's message reads, and an absent one reads null.
    /// </summary>
    private object? ReadUnassigned(string name)
    {
        return SessionState.PSVariable.GetValue("global:" + name);
    }

    /// <summary>The foreach and pipeline enumeration of the property collection.</summary>
    private static IEnumerable<object?> Enumerate(object value)
    {
        IEnumerable? enumerable = LanguagePrimitives.GetEnumerable(value);
        if (enumerable is null)
        {
            yield return value;
            yield break;
        }
        foreach (object? item in enumerable)
            yield return item;
    }

    /// <summary>
    /// private/functions/Get-ConnectionParent.ps1 without -Database: climbs Parent until an object
    /// carries a ConnectionContext, giving up (and returning nothing) after ten levels.
    /// </summary>
    private object? ConnectionParent(object? input)
    {
        object? current = input;
        int parentCount = 0;
        while (true)
        {
            object? parent = ReadProperty(current, "Parent");
            if (parent is not null)
                current = parent;
            if (ReadProperty(current, "ConnectionContext") is not null)
                break;
            if (parentCount++ > 10)
                break;
        }
        return parentCount < 10 ? current : null;
    }

    /// <summary>
    /// PS: $server.Query("SELECT @@SERVERNAME AS servername").servername through the Server.Query script
    /// method of xml/dbatools.Types.ps1xml without -Database: the first table of the caller's connection, or
    /// a thrown string of the failure's concatenated exception messages that the method binder wraps. Each failure is a
    /// statement fault of the pin: the record is surfaced, faulted is set and the caller goes on.
    /// </summary>
    private object? QueryServerName(object? server, out bool faulted)
    {
        faulted = true;
        if (server is null)
        {
            ReportFault(TerminatingRecord(new RuntimeException("You cannot call a method on a null-valued expression."),
                "InvokeMethodOnNull", ErrorCategory.InvalidOperation, null));
            return null;
        }
        object baseServer = server is PSObject wrapped ? wrapped.BaseObject : server;
        if (baseServer is not Server smoServer)
        {
            ReportFault(TerminatingRecord(new RuntimeException(String.Format(
                "Method invocation failed because [{0}] does not contain a method named 'Query'.", baseServer.GetType().FullName)),
                "MethodNotFound", ErrorCategory.InvalidOperation, null));
            return null;
        }

        DataSet results;
        try
        {
            results = smoServer.ConnectionContext.ExecuteWithResults(ServerNameSql);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ReportFault(QueryFaultRecord(failure));
            return null;
        }
        faulted = false;
        DataTable? table = results.Tables.Count > 0 ? results.Tables[0] : null;
        if (table is null || table.Rows.Count == 0)
            return null;
        if (table.Rows.Count == 1)
            return table.Rows[0]["servername"];
        object?[] values = new object?[table.Rows.Count];
        for (int n = 0; n < values.Length; n++)
            values[n] = table.Rows[n]["servername"];
        return values;
    }

    /// <summary>PS: [DbaInstanceParameter]$servername. A null name converts to null; a value the conversion refuses is a
    /// statement fault, surfaced with faulted set.</summary>
    private DbaInstanceParameter? ConvertServerName(object? serverName, out bool faulted)
    {
        faulted = false;
        try
        {
            return (DbaInstanceParameter?)LanguagePrimitives.ConvertTo(serverName, typeof(DbaInstanceParameter), CultureInfo.InvariantCulture);
        }
        catch (PSInvalidCastException failure)
        {
            faulted = true;
            ReportFault(TerminatingRecord(failure, "InvalidCastConstructorException", ErrorCategory.InvalidArgument, serverName));
            return null;
        }
    }

    /// <summary>
    /// The record a failed Server.Query call raises: its catch concatenates the messages of the failure's
    /// exception chain without separators and throws that string, which the method binder reports as the
    /// ScriptMethodRuntimeException of 'Exception calling "Query" with "1" argument(s)'.
    /// </summary>
    private static ErrorRecord QueryFaultRecord(Exception failure)
    {
        string message = String.Empty;
        Exception current = failure;
        while (current.InnerException != null)
        {
            message += current.Message;
            current = current.InnerException;
        }
        message += current.Message;
        MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
            "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", message), new RuntimeException(message, failure));
        return new ErrorRecord(call, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
    }

    /// <summary>The ErrorRecord each statement fault site surfaces.</summary>
    private static ErrorRecord TerminatingRecord(Exception failure, string errorId, ErrorCategory category, object? target)
    {
        // An engine fault such as PSInvalidCastException already carries its own record.
        return failure is PSInvalidCastException
            ? new ErrorRecord(((IContainsErrorRecord)failure).ErrorRecord, failure)
            : new ErrorRecord(failure, errorId, category, target);
    }
}
