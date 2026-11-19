#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>Retrieves CLR assemblies registered in SQL Server databases for security auditing and inventory management.</summary>
[Cmdlet(VerbsCommon.Get, "DbaDbAssembly")]
public sealed class GetDbaDbAssemblyCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to search.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>The assembly name(s) to filter by.</summary>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? Name { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // The source retains the last enumerated assembly as its catch target within this record.
        SqlAssembly? currentAssembly = null;
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = ConnectInstance(instance);
            if (server is null)
                continue;

            // Pinned help documents wildcards for -Database (not for -Name), which the source's
            // literal -in never honoured; a real database name of this instance stays literal.
            WildcardNameMatcher databaseMatcher = NativeDatabaseSelection.CreateNameMatcher(Database, true,
                NativeDatabaseSelection.DatabaseNames(server));
            List<Microsoft.SqlServer.Management.Smo.Database> databases = new();
            foreach (Microsoft.SqlServer.Management.Smo.Database database in server.Databases)
            {
                if (!database.IsAccessible)
                    continue;
                if (TestBound(nameof(Database)) && !databaseMatcher.Matches(database.Name))
                    continue;
                databases.Add(database);
            }

            foreach (Microsoft.SqlServer.Management.Smo.Database database in databases)
            {
                try
                {
                    foreach (SqlAssembly assembly in database.Assemblies)
                    {
                        if (TestBound(nameof(Name)) && !NativeDatabaseSelection.ContainsName(Name, assembly.Name))
                            continue;
                        currentAssembly = assembly;
                        PSObject output = PSObject.AsPSObject(assembly);
                        foreach (string property in new[] { "ComputerName", "InstanceName", "SqlInstance", "Database", "DatabaseId", "SecurityLevel" })
                            output.Properties.Remove(property);
                        OutputHelper.AddInstanceProperties(output, assembly.Parent.Parent);
                        output.Properties.Add(new PSNoteProperty("Database", database.Name));
                        output.Properties.Add(new PSNoteProperty("DatabaseId", database.ID));
                        OutputHelper.AddAliasProperty(output, "SecurityLevel", "AssemblySecurityLevel");
                        OutputHelper.SetDefaultDisplayPropertySet(output,
                            "ComputerName", "InstanceName", "SqlInstance", "Database", "ID", "Name", "Owner",
                            "SecurityLevel", "CreateDate", "IsSystemObject", "Version");
                        WriteObject(output);
                    }
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception exception)
                {
                    ErrorRecord record = exception is IContainsErrorRecord recorded
                        ? recorded.ErrorRecord
                        : new ErrorRecord(exception, "dbatools_Get-DbaDbAssembly", ErrorCategory.NotSpecified, currentAssembly);
                    StopFunction("Issue pulling assembly information", target: currentAssembly,
                        errorRecord: record, continueLoop: true);
                }
            }
        }
    }
}
