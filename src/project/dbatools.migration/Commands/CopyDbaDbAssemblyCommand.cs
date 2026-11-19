#nullable enable

using System;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Copies CLR assemblies from source databases to destination SQL Server instances
/// </summary>
[Cmdlet(VerbsCommon.Copy, "DbaDbAssembly", DefaultParameterSetName = "Default",
    SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaDbAssemblyCommand : DbaBaseCmdlet
{
    /// <summary>The source SQL Server instance. Requires sysadmin and SQL Server 2005 or higher.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter Source { get; set; } = null!;

    /// <summary>Alternative credential for the source instance.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <summary>The destination SQL Server instances.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    public DbaInstanceParameter[] Destination { get; set; } = null!;

    /// <summary>Alternative credential for destination instances.</summary>
    [Parameter(Position = 3)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>Only copy these assemblies, named DatabaseName.AssemblyName.</summary>
    [Parameter(Position = 4)]
    public object[]? Assembly { get; set; }

    /// <summary>Skip these assemblies, named DatabaseName.AssemblyName.</summary>
    [Parameter(Position = 5)]
    public object[]? ExcludeAssembly { get; set; }

    /// <summary>Drop and recreate assemblies that already exist on the destination.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.
    private Server? _sourceServer;
    private readonly List<SqlAssembly> _sourceAssemblies = new();

    protected override void BeginProcessing()
    {
        try
        {
            _sourceServer = ConnectServer(Source, SourceSqlCredential);
        }
        catch (PipelineStoppedException) { throw; }
        catch (Exception ex)
        {
            StopFunction("Failure", target: Source, exception: ex, category: ErrorCategory.ConnectionError);
            return;
        }

        foreach (SmoDatabase database in _sourceServer.Databases)
        {
            if (!database.IsAccessible)
                continue;
            WriteMessage(MessageLevel.Verbose, String.Format("Processing {0} on source", database));
            try
            {
                foreach (SqlAssembly assembly in database.Assemblies)
                {
                    if (!assembly.IsSystemObject)
                        _sourceAssemblies.Add(assembly);
                }
            }
            catch (PipelineStoppedException) { throw; }
            catch (Exception)
            {
                // The pinned source tolerates SMO assembly enumeration failures.
            }
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted || _sourceServer is null)
            return;
        foreach (DbaInstanceParameter destination in Destination)
        {
            Server destinationServer;
            try
            {
                destinationServer = ConnectServer(destination, DestinationSqlCredential);
            }
            catch (PipelineStoppedException) { throw; }
            catch (Exception ex)
            {
                StopFunction("Failure", target: destination, exception: ex,
                    category: ErrorCategory.ConnectionError, continueLoop: true);
                continue;
            }

            foreach (SmoDatabase database in destinationServer.Databases)
            {
                WriteMessage(MessageLevel.VeryVerbose, String.Format("Processing {0} on destination", database));
                try
                {
                    foreach (SqlAssembly assembly in database.Assemblies)
                    {
                        // The pinned destination inventory is not subsequently used.
                        _ = assembly.IsSystemObject;
                    }
                }
                catch (PipelineStoppedException) { throw; }
                catch (Exception)
                {
                    // The pinned source tolerates SMO assembly enumeration failures.
                }
            }

            foreach (SqlAssembly assembly in _sourceAssemblies)
            {
                if (Stopping)
                    return;
                CopyAssembly(assembly, destination, destinationServer);
            }
        }
    }

    private Server ConnectServer(DbaInstanceParameter instance, PSCredential? credential)
    {
        WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
        SmoConnectionRequest request = new()
        {
            Instance = instance,
            SqlCredential = credential,
            MinimumVersion = 9,
            AzureUnsupported = true,
            BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            {
                "SqlInstance", "SqlCredential", "MinimumVersion", "AzureUnsupported"
            },
            MessageCallback = (level, message) => WriteAttributedMessage("Connect-DbaInstance", level, message)
        };
        Server server = ConnectionService.GetServer(request);
        SetActiveConnection(server.ConnectionContext);
        WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "We are finished with this instance");
        return server;
    }

    private bool ConfirmAction(DbaInstanceParameter destination, string action)
    {
        if (!Force)
            return ShouldProcess(destination.ToString(), action);
        object? previous = SessionState.PSVariable.GetValue("ConfirmPreference");
        try
        {
            SessionState.PSVariable.Set("ConfirmPreference", ConfirmImpact.None);
            return ShouldProcess(destination.ToString(), action);
        }
        finally
        {
            SessionState.PSVariable.Set("ConfirmPreference", previous);
        }
    }

    private void CopyAssembly(SqlAssembly assembly, DbaInstanceParameter destination, Server destinationServer)
    {
        string assemblyName = assembly.Name;
        SmoDatabase sourceDatabase = assembly.Parent;
        string databaseName = sourceDatabase.Name;
        SmoDatabase? destinationDatabase = destinationServer.Databases[databaseName];
        DbaDateTime timestamp = new(DateTime.Now);
        WriteMessage(MessageLevel.VeryVerbose, String.Format("Processing {0} on {1}", assemblyName, databaseName));
        if (destinationDatabase is null)
        {
            string message = String.Format("Destination database {0} does not exist. Skipping {1}.", databaseName, assemblyName);
            if (ConfirmAction(destination, message))
            {
                WriteMessage(MessageLevel.Verbose, message);
                WriteStatus(assembly, destinationServer, null, "Skipped", "Destination database does not exist", timestamp);
            }
            return;
        }

        string qualifiedName = String.Format("{0}.{1}", databaseName, assemblyName);
        if ((TestBound(nameof(Assembly)) && !MatchesSelection(Assembly, qualifiedName)) ||
            MatchesSelection(ExcludeAssembly, qualifiedName))
            return;

        SqlAssembly? existing = destinationDatabase.Assemblies[assemblyName];
        // The skip decision must precede any database trust change.
        if (existing is not null && !Force)
        {
            string message = String.Format("Assembly {0} exists at destination in the {1} database. Use -Force to drop and migrate.", assemblyName, databaseName);
            if (ConfirmAction(destination, message))
            {
                WriteMessage(MessageLevel.Verbose, message);
                WriteStatus(assembly, destinationServer, destinationDatabase, "Skipped", "Already exists on destination", timestamp);
            }
            return;
        }

        if (String.Equals(assembly.AssemblySecurityLevel.ToString(), "External", StringComparison.OrdinalIgnoreCase) &&
            !destinationDatabase.Trustworthy && sourceDatabase.Trustworthy)
        {
            if (ConfirmAction(destination, String.Format("Setting {0} to External", databaseName)))
            {
                WriteMessage(MessageLevel.Verbose, String.Format("Setting {0} Security Level to External on {1}.", databaseName, destination));
                string sql = String.Format("ALTER DATABASE {0} SET TRUSTWORTHY ON", QuoteIdentifier(databaseName));
                try
                {
                    WriteMessage(MessageLevel.Debug, sql);
                    destinationServer.ConnectionContext.ExecuteNonQuery(sql);
                    destinationDatabase.Refresh();
                }
                catch (PipelineStoppedException) { throw; }
                catch (Exception ex)
                {
                    WriteStatus(assembly, destinationServer, destinationDatabase, "Failed to set security level to external", ex.Message, timestamp);
                    WriteMessage(MessageLevel.Verbose, String.Format("Failed to set security level to external for {0} on {1} | {2}", databaseName, destination, ex.Message));
                    return;
                }
            }
        }

        if (existing is not null && ConfirmAction(destination,
            String.Format("Dropping assembly {0} on {1} on {2}", assemblyName, destinationDatabase.Name, destinationServer.Name)))
        {
            try
            {
                WriteMessage(MessageLevel.Verbose, String.Format("Dropping assembly {0}.", assemblyName));
                string dependencySql = String.Format(CultureInfo.InvariantCulture,
                    "SELECT 1 FROM sys.assembly_references WHERE assembly_id = {0} OR referenced_assembly_id = {0}", existing.ID);
                using (DataSet dependencies = destinationDatabase.ExecuteWithResults(dependencySql))
                {
                    if (dependencies.Tables.Count > 0 && dependencies.Tables[0].Rows.Count > 0)
                    {
                        WriteMessage(MessageLevel.Verbose, "This won't work if there are dependencies.");
                        throw new InvalidOperationException(String.Format("{0} has dependencies but this command does not yet support dependent objects", assemblyName));
                    }
                }
                existing.Drop();
            }
            catch (PipelineStoppedException) { throw; }
            catch (Exception ex)
            {
                WriteStatus(assembly, destinationServer, destinationDatabase, "Failed", ex.Message, timestamp);
                WriteMessage(MessageLevel.Verbose, String.Format("Failed to drop assembly {0} for {1} on {2} | {3}", assemblyName, databaseName, destination, ex.Message));
                return;
            }
        }

        if (!ConfirmAction(destination, String.Format("Creating assembly {0}", assemblyName)))
            return;
        try
        {
            WriteMessage(MessageLevel.Verbose, String.Format("Copying assembly {0} from database.", assemblyName));
            StringCollection sql = assembly.Script();
            string[] batches = new string[sql.Count];
            sql.CopyTo(batches, 0);
            WriteMessage(MessageLevel.Debug, String.Join(" ", batches));
            destinationDatabase.ExecuteNonQuery(sql);
            WriteStatus(assembly, destinationServer, destinationDatabase, "Successful", null, timestamp);
        }
        catch (PipelineStoppedException) { throw; }
        catch (Exception ex)
        {
            // The pinned create failure stores an ErrorRecord; the earlier catches store text.
            ErrorRecord error = new(ex, ex.GetType().FullName!, ErrorCategory.NotSpecified, assemblyName);
            WriteStatus(assembly, destinationServer, destinationDatabase, "Failed", error, timestamp);
            WriteMessage(MessageLevel.Verbose, String.Format("Failed to create assembly {0} for {1} on {2} | {3}", assemblyName, databaseName, destination, ex.Message));
        }
    }

    private static bool MatchesSelection(object[]? selection, string name)
    {
        if (selection is null)
            return false;
        foreach (object item in selection)
        {
            if (LanguagePrimitives.Equals(item, name, true, CultureInfo.InvariantCulture))
                return true;
        }
        return false;
    }

    private static string QuoteIdentifier(string value) => String.Format("[{0}]", value.Replace("]", "]]"));

    private void WriteStatus(SqlAssembly assembly, Server destinationServer, SmoDatabase? destinationDatabase,
        string status, object? notes, DbaDateTime timestamp)
    {
        SmoDatabase sourceDatabase = assembly.Parent;
        PSObject output = new();
        output.Properties.Add(new PSNoteProperty("SourceServer", _sourceServer!.Name));
        output.Properties.Add(new PSNoteProperty("SourceDatabase", sourceDatabase.Name));
        output.Properties.Add(new PSNoteProperty("SourceDatabaseID", sourceDatabase.ID));
        output.Properties.Add(new PSNoteProperty("DestinationServer", destinationServer.Name));
        output.Properties.Add(new PSNoteProperty("DestinationDatabase", destinationDatabase));
        output.Properties.Add(new PSNoteProperty("DestinationDatabaseID", destinationDatabase is null ? null : (object)destinationDatabase.ID));
        output.Properties.Add(new PSNoteProperty("type", "Database Assembly"));
        output.Properties.Add(new PSNoteProperty("Name", assembly.Name));
        output.Properties.Add(new PSNoteProperty("Status", status));
        output.Properties.Add(new PSNoteProperty("Notes", notes));
        output.Properties.Add(new PSNoteProperty("DateTime", timestamp));
        OutputHelper.SetDefaultDisplayPropertySet(output, "DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes");
        OutputHelper.InsertTypeName(output, "MigrationObject");
        WriteObject(output);
    }
}
