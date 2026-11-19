#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Configuration;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Exceptions;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

// Retrieves the DML triggers attached to tables and views directly through SMO. The -SqlInstance
// path reproduces the Get-DbaDbTable and Get-DbaDbView reads the source delegated to, including
// their database selection, messages and parent decorations.
/// <summary>Retrieves triggers attached to tables and views across SQL Server databases.</summary>
[Cmdlet(VerbsCommon.Get, "DbaDbObjectTrigger")]
public sealed class GetDbaDbObjectTriggerCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to search.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Which object type(s) to search for triggers.</summary>
    [Parameter(Position = 4)]
    [ValidateSet("All", "Table", "View")]
    [PsStringCast]
    public string Type { get; set; } = "All";

    /// <summary>Table or view object(s) piped in.</summary>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public object[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private const string TableFunction = "Get-DbaDbTable";
    private const string ViewFunction = "Get-DbaDbView";

    // Correction: the source re-read every command-line instance on each piped record.
    private bool instancesRead;

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        List<object?> objects = new();
        if (InputObject is not null && InputObject.Length > 0)
        {
            foreach (object? item in InputObject)
            {
                if (Unwrap(item) is not TableViewBase)
                {
                    StopFunction(String.Format(CultureInfo.InvariantCulture, "InputObject {0} is not of type Table or View.", ToText(item)),
                        continueLoop: true);
                    continue;
                }
            }
            // Correction: -Type also filters piped objects; All keeps every piped object as the source does.
            foreach (object? item in InputObject)
            {
                if (MatchesType(item))
                    objects.Add(item);
            }
        }

        if (!instancesRead)
        {
            instancesRead = true;
            // Correction: each listed instance is read once, not once per listed instance.
            foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
            {
                if (Interrupted)
                    return;
                if (TypeIs("All") || TypeIs("Table"))
                    ReadTables(instance, objects);
                if (TypeIs("All") || TypeIs("View"))
                    ReadViews(instance, objects);
            }
        }

        foreach (object? item in objects)
        {
            if (Interrupted)
                return;
            try
            {
                WriteTriggers(item);
            }
            catch (Exception error) when (error is not PipelineStoppedException)
            {
                StopFunction("Failure", errorRecord: ScriptRecord(error), continueLoop: true);
            }
        }
    }

    private void WriteTriggers(object? item)
    {
        object? triggers = Unwrap(item) is TableViewBase owner ? owner.Triggers : ReadMember(item, "Triggers");
        if (triggers is null)
            return;
        // foreach over a value PowerShell does not enumerate runs once with the value itself.
        IEnumerator? enumerator = LanguagePrimitives.GetEnumerator(triggers);
        if (enumerator is null)
        {
            WriteTrigger(triggers);
            return;
        }
        while (enumerator.MoveNext())
        {
            if (Interrupted)
                return;
            WriteTrigger(enumerator.Current);
        }
    }

    private void WriteTrigger(object? trigger)
    {
        if (trigger is null)
            return;
        object? parent = ReadMember(trigger, "Parent");
        object? computerName = ReadMember(parent, "ComputerName");
        object? instanceName = ReadMember(parent, "InstanceName");
        object? sqlInstance = ReadMember(parent, "SqlInstance");
        PSObject output = PSObject.AsPSObject(trigger);
        // Add-Member -Force copies the values the parent carries, which need not come from a server.
        output.Properties.Remove("ComputerName");
        output.Properties.Add(new PSNoteProperty("ComputerName", computerName)); // style-ok: cs-output-props copied from the trigger's parent as the source does; OutputHelper needs a server
        output.Properties.Remove("InstanceName");
        output.Properties.Add(new PSNoteProperty("InstanceName", instanceName)); // style-ok: cs-output-props copied from the trigger's parent as the source does; OutputHelper needs a server
        output.Properties.Remove("SqlInstance");
        output.Properties.Add(new PSNoteProperty("SqlInstance", sqlInstance)); // style-ok: cs-output-props copied from the trigger's parent as the source does; OutputHelper needs a server
        OutputHelper.SetDefaultDisplayPropertySet(output,
            "ComputerName", "InstanceName", "SqlInstance", "Name", "Parent", "IsEnabled", "DateLastModified");
        WriteObject(output);
    }

    // Get-DbaDbTable -SqlInstance <instance> -SqlCredential -Database -ExcludeDatabase.
    private void ReadTables(DbaInstanceParameter instance, List<object?> objects)
    {
        string[]? include = ToStringArray(Database);
        string[]? exclude = ToStringArray(ExcludeDatabase);
        // An explicitly requested database is honored even when it is a system database.
        bool excludeSystem = !LanguagePrimitives.IsTrue(include);
        // Pinned help documents wildcards for -Database and -ExcludeDatabase, which the nested readers'
        // literal Get-DbaDatabase matching never honoured; both opt in to the shared wildcard union.
        List<SmoDatabase> databases = NativeDatabaseSelection.GatherMatching(this, new[] { instance }, SqlCredential,
            include, true, exclude, true, server => SetActiveConnection(server.ConnectionContext), () => Interrupted);

        foreach (SmoDatabase database in databases)
        {
            if (Interrupted)
                return;
            if (excludeSystem && database.IsSystemObject)
                continue;
            if (!database.IsAccessible)
                continue;

            Server server = database.Parent;
            NestedMessage(TableFunction, MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Processing {0}", database));
            bool azure = server.DatabaseEngineType == DatabaseEngineType.SqlAzureDatabase;
            int major = server.VersionMajor;

            if (ConfigFlag("commands.get-dbadbtable.clearandinitialize"))
            {
                List<string> properties = new() { "Schema", "Name", "RowCount", "HasClusteredIndex" };
                if (!azure)
                {
                    properties.Add("IndexSpaceUsed");
                    properties.Add("DataSpaceUsed");
                }
                AddVersionProperties(properties, major);
                try
                {
                    database.Tables.ClearAndInitialize(String.Empty, properties);
                }
                catch (Exception error)
                {
                    NestedMessage(TableFunction, MessageLevel.Verbose, "ClearAndInitialize failed: " + MethodFailure(error));
                }
            }

            List<string> display = new() { "ComputerName", "InstanceName", "SqlInstance", "Database", "Schema", "Name" };
            if (!azure)
            {
                display.Add("IndexSpaceUsed");
                display.Add("DataSpaceUsed");
            }
            display.Add("RowCount");
            display.Add("HasClusteredIndex");
            AddVersionProperties(display, major);
            display.Add("FullTextIndex");

            foreach (object? table in Enumerate(database.Tables))
            {
                if (Interrupted)
                    return;
                if (table is null)
                    continue;
                objects.Add(Decorate(table, server, database, display.ToArray()));
            }
        }
    }

    // Get-DbaDbView -SqlInstance <instance> -SqlCredential -Database -ExcludeDatabase.
    private void ReadViews(DbaInstanceParameter instance, List<object?> objects)
    {
        // The documented -Database and -ExcludeDatabase wildcards apply to the view read as well.
        List<SmoDatabase> databases = NativeDatabaseSelection.GatherMatching(this, new[] { instance }, SqlCredential,
            ToStringArray(Database), true, ToStringArray(ExcludeDatabase), true,
            server => SetActiveConnection(server.ConnectionContext), () => Interrupted);
        string[] display = { "ComputerName", "InstanceName", "SqlInstance", "Database", "Schema", "CreateDate", "DateLastModified", "Name" };

        foreach (SmoDatabase database in databases)
        {
            if (Interrupted)
                return;
            NestedMessage(ViewFunction, MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "processing {0}", database));
            try
            {
                database.Views.ClearAndInitialize(String.Empty, new[] { "Name", "Schema", "IsSystemObject", "CreateDate", "DateLastModified" });
            }
            catch (Exception error)
            {
                NestedMessage(ViewFunction, MessageLevel.Verbose, "ClearAndInitialize failed: " + MethodFailure(error));
            }

            ViewCollection views = database.Views;
            if (!database.IsAccessible)
            {
                NestedMessage(ViewFunction, MessageLevel.Warning, String.Format(CultureInfo.InvariantCulture, "Database {0} is not accessible. Skipping", database));
                continue;
            }
            Server server = database.Parent;
            if (!LanguagePrimitives.IsTrue(views))
            {
                NestedMessage(ViewFunction, MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                    "No views exist in the {0} database on {1}", database, SmoServerExtensions.GetDomainInstanceName(server)), database);
                continue;
            }

            foreach (object? view in Enumerate(views))
            {
                if (Interrupted)
                    return;
                if (view is null)
                    continue;
                objects.Add(Decorate(view, server, database, display));
            }
        }
    }

    private static PSObject Decorate(object smoObject, Server server, SmoDatabase database, string[] display)
    {
        PSObject decorated = PSObject.AsPSObject(smoObject);
        foreach (string name in new[] { "ComputerName", "InstanceName", "SqlInstance", "Database" })
            decorated.Properties.Remove(name);
        OutputHelper.AddInstanceProperties(decorated, server);
        decorated.Properties.Add(new PSNoteProperty("Database", database.Name));
        OutputHelper.SetDefaultDisplayPropertySet(decorated, display);
        return decorated;
    }

    // The gathered collections are enumerated by foreach statements in Get-DbaDbTable and Get-DbaDbView.
    private List<object?> Enumerate(object collection)
    {
        List<object?> items = new();
        try
        {
            IEnumerator? enumerator = LanguagePrimitives.GetEnumerator(collection);
            if (enumerator is null)
            {
                items.Add(collection);
                return items;
            }
            while (enumerator.MoveNext())
                items.Add(enumerator.Current);
        }
        catch (Exception error) when (error is not PipelineStoppedException)
        {
            // caller-try: terminate -- continuing would silently drop this database's objects and their triggers
            ThrowTerminatingError(ScriptRecord(error)); // style-ok: cs-raw-streams engine statement fault inside the delegated reader, outside Stop-Function
        }
        return items;
    }

    private static void AddVersionProperties(List<string> properties, int major)
    {
        if (major >= 9)
            properties.Add("IsPartitioned");
        if (major >= 10)
            properties.Add("ChangeTrackingEnabled");
        if (major >= 11)
            properties.Add("IsFileTable");
        if (major >= 12)
            properties.Add("IsMemoryOptimized");
        if (major >= 14)
        {
            properties.Add("IsNode");
            properties.Add("IsEdge");
        }
    }

    private bool TypeIs(string value)
    {
        return String.Equals(Type, value, StringComparison.OrdinalIgnoreCase);
    }

    private bool MatchesType(object? item)
    {
        if (TypeIs("Table"))
            return Unwrap(item) is Table;
        if (TypeIs("View"))
            return Unwrap(item) is View;
        return true;
    }

    // The nested readers write with their own function name and their own unset EnableException.
    private void NestedMessage(string functionName, MessageLevel level, string message, object? target = null)
    {
        MessageService.Write(this, new MessageService.MessageRequest
        {
            FunctionName = functionName, ModuleName = "dbatools", Level = level, Message = message,
            Target = target, EnableException = false,
            File = MyInvocation.ScriptName, Line = MyInvocation.ScriptLineNumber
        });
    }

    // Get-DbatoolsConfigValue followed by an if test.
    private static bool ConfigFlag(string fullName)
    {
        if (!ConfigurationHost.Configurations.TryGetValue(fullName.ToLowerInvariant(), out Config? config) || config is null)
            return false;
        object? value = config.Value;
        string? text = (value is PSObject wrapped ? wrapped.BaseObject : value)?.ToString();
        if (String.Equals(text, "Mandatory", StringComparison.OrdinalIgnoreCase))
            return true;
        if (String.Equals(text, "Optional", StringComparison.OrdinalIgnoreCase))
            return false;
        return LanguagePrimitives.IsTrue(value);
    }

    // The object arrays bind to the nested readers' string-array database parameters.
    private static string[]? ToStringArray(object[]? values)
    {
        if (values is null)
            return null;
        return (string[])LanguagePrimitives.ConvertTo(values, typeof(string[]), CultureInfo.InvariantCulture);
    }

    // The PowerShell dot operator in non-strict mode: dictionary keys first, then members, null when absent.
    private static object? ReadMember(object? item, string name)
    {
        if (item is null)
            return null;
        if (Unwrap(item) is IDictionary dictionary && dictionary.Contains(name))
            return dictionary[name];
        PSObject wrapped = PSObject.AsPSObject(item);
        PSPropertyInfo? property = wrapped.Properties[name];
        if (property is null)
            return null;
        PSPropertyInfo? resolved = property;
        HashSet<string> visited = new(StringComparer.OrdinalIgnoreCase);
        while (resolved is PSAliasProperty alias && visited.Add(alias.Name))
            resolved = wrapped.Properties[alias.ReferencedMemberName];
        if (resolved is PSScriptProperty)
            throw new NativeMetadataException(String.Format(CultureInfo.InvariantCulture,
                "Native metadata property {0} resolves to script property {1}. Supply a note or native CLR property instead.",
                name, resolved.Name));
        return property.Value;
    }

    // The ErrorRecord a script catch block receives for this exception.
    private static ErrorRecord ScriptRecord(Exception error)
    {
        if (error is IContainsErrorRecord container && container.ErrorRecord is not null)
            return new ErrorRecord(container.ErrorRecord, error);
        return new ErrorRecord(error, error.GetType().FullName, ErrorCategory.OperationStopped, null);
    }

    // "$_" for a failed method call in a catch block.
    private static string MethodFailure(Exception error)
    {
        return String.Format(CultureInfo.InvariantCulture,
            "Exception calling \"ClearAndInitialize\" with \"2\" argument(s): \"{0}\"", error.Message);
    }

    private static object? Unwrap(object? item)
    {
        return item is PSObject wrapped ? wrapped.BaseObject : item;
    }

    // String expansion of "$object" in the source message.
    private static string ToText(object? item)
    {
        if (item is null)
            return String.Empty;
        return (string)LanguagePrimitives.ConvertTo(item, typeof(string), CultureInfo.InvariantCulture);
    }
}
