#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Configuration;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;
using SmoPartitionScheme = Microsoft.SqlServer.Management.Smo.PartitionScheme;

namespace Dataplat.Dbatools.Commands;

/// <summary>Retrieves partition schemes from SQL Server databases for table partitioning management.</summary>
[Cmdlet(VerbsCommon.Get, "DbaDbPartitionScheme")]
public sealed class GetDbaDbPartitionSchemeCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to search.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Filter to the specified partition scheme(s) by name.</summary>
    [Parameter(Position = 4)]
    [Alias("Name")]
    [PsStringArrayCast]
    public string[]? PartitionScheme { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = ConnectInstance(instance);
            if (server == null)
                continue;

            // Upstream buffers the accessible database selection before reading any schemes.
            List<SmoDatabase> selected = new();
            foreach (SmoDatabase database in server.Databases)
            {
                if (database.IsAccessible &&
                    (!LanguagePrimitives.IsTrue(Database) || NativeDatabaseSelection.ContainsInOperand(Database, database.Name)) &&
                    (!LanguagePrimitives.IsTrue(ExcludeDatabase) || !NativeDatabaseSelection.ContainsInOperand(ExcludeDatabase, database.Name)))
                    selected.Add(database);
            }
            foreach (SmoDatabase database in selected)
                WriteSchemes(database, instance);
        }
    }

    private void WriteSchemes(SmoDatabase database, DbaInstanceParameter instance)
    {
        if (!database.IsAccessible)
        {
            WriteMessage(MessageLevel.Warning, String.Format("Database {0} is not accessible. Skipping.", database));
            return;
        }
        List<SmoPartitionScheme> matches = new();
        foreach (SmoPartitionScheme scheme in database.PartitionSchemes)
        {
            if (!LanguagePrimitives.IsTrue(PartitionScheme) || NativeDatabaseSelection.ContainsName(PartitionScheme, scheme.Name))
                matches.Add(scheme);
        }
        // The unfiltered SMO collection is truthy even when empty; only a filtered
        // empty pipeline result reaches the upstream verbose message.
        if (matches.Count == 0 && LanguagePrimitives.IsTrue(PartitionScheme))
        {
            WriteMessage(MessageLevel.Verbose, String.Format("No Partition Schemes exist in the {0} database on {1}", database, instance), database);
            return;
        }

        foreach (SmoPartitionScheme scheme in matches)
        {
            PSObject output = PSObject.AsPSObject(scheme);
            foreach (string property in new[] { "ComputerName", "InstanceName", "SqlInstance", "Database" })
                output.Properties.Remove(property);
            OutputHelper.AddInstanceProperties(output, database.Parent);
            output.Properties.Add(new PSNoteProperty("Database", database.Name));
            OutputHelper.SetDefaultDisplayPropertySet(output,
                "ComputerName", "InstanceName", "SqlInstance", "Database", "Name", "PartitionFunction");
            WriteObject(output);
        }
    }

    protected override void EndProcessing()
    {
        const string alias = "Get-DbaDatabasePartitionScheme";
        if (Interrupted || !String.Equals(MyInvocation.InvocationName, alias, StringComparison.OrdinalIgnoreCase))
            return;

        const string name = "get-dbadbpartitionscheme.deprecated.alias.get-dbadatabasepartitionscheme";
        const string key = "messageonce." + name;
        bool alreadyWritten = ConfigurationHost.Configurations.TryGetValue(key, out var previous) && (bool)previous.Value;
        MessageService.Write(this, new MessageService.MessageRequest
        {
            FunctionName = "Get-DbaDbPartitionScheme", Level = MessageLevel.Warning,
            Message = String.Format("Using the alias {0} is deprecated. This alias will be removed in version 1.0.0 or before, use Get-DbaDbPartitionScheme instead. Invoke-DbatoolsRenameHelper can also help rename commands within your scripts.", alias),
            EnableException = false, SuppressWarningDisplay = alreadyWritten,
            File = MyInvocation.ScriptName, Line = MyInvocation.ScriptLineNumber
        });
        if (!alreadyWritten && !MessageHost.DisableVerbosity)
        {
            ConfigurationHost.Configurations[key] = new Config
            {
                Module = "messageonce", Name = name, Hidden = true, Value = true,
                Description = "Locking setting that disables further display of the specified message"
            };
        }
    }
}
