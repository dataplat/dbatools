#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Utility;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// The catalog reads and writes Remove-DbaSsisEnvironment makes, kept apart from the cmdlet's own lifecycle.
/// </summary>
public sealed partial class RemoveDbaSsisEnvironmentCommand : DbaInstanceCmdlet
{
    /// <summary>
    /// Presence is asked of the instance rather than of SMO's Databases collection: enumerating
    /// every database to answer a one-name question drags in whatever state the other databases
    /// are in, and a single-user database is enough to poison the shared connection.
    /// </summary>
    private bool CatalogExists(Server server)
    {
        using SqlCommand presence = new("SELECT DB_ID('SSISDB')", server.ConnectionContext.SqlConnectionObject);
        SetActiveCommand(presence);
        try
        {
            object? result = presence.ExecuteScalar();
            return result != null && result is not DBNull;
        }
        finally
        {
            SetActiveCommand(null);
        }
    }

    /// <summary>
    /// Reads the matching environments in Get-DbaSsisEnvironment's shape before they are removed. A
    /// null folderName searches the whole catalog, which is what makes a name that lives in two
    /// folders come back as two rows instead of silently resolving to whichever the server returned
    /// first.
    /// </summary>
    private List<PSObject> ReadEnvironments(Server server, string? folderName, string environmentName)
    {
        string sql = "SELECT e.environment_id, e.folder_id, f.name AS folder_name, e.name, e.description," +
                     " e.created_by_sid, e.created_by_name, e.created_time" +
                     " FROM [SSISDB].[catalog].[environments] e" +
                     " JOIN [SSISDB].[catalog].[folders] f ON f.folder_id = e.folder_id" +
                     " WHERE e.name = @environmentName";
        if (folderName != null)
        {
            sql += " AND f.name = @folderName";
        }
        sql += " ORDER BY f.name";

        using SqlCommand command = new(sql, server.ConnectionContext.SqlConnectionObject);
        command.Parameters.AddWithValue("@environmentName", environmentName);
        if (folderName != null)
        {
            command.Parameters.AddWithValue("@folderName", folderName);
        }

        SetActiveCommand(command);
        try
        {
            List<PSObject> environments = new();
            using SqlDataReader reader = command.ExecuteReader();
            while (reader.Read())
            {
                environments.Add(BuildEnvironment(server, reader));
            }
            return environments;
        }
        finally
        {
            SetActiveCommand(null);
        }
    }

    private static PSObject BuildEnvironment(Server server, SqlDataReader reader)
    {
        PSObject environment = new();
        OutputHelper.AddInstanceProperties(environment, server);
        environment.Properties.Add(new PSNoteProperty("EnvironmentId", ValueOrNull(reader["environment_id"])));
        environment.Properties.Add(new PSNoteProperty("FolderId", ValueOrNull(reader["folder_id"])));
        environment.Properties.Add(new PSNoteProperty("FolderName", ValueOrNull(reader["folder_name"])));
        environment.Properties.Add(new PSNoteProperty("Name", ValueOrNull(reader["name"])));
        environment.Properties.Add(new PSNoteProperty("Description", ValueOrNull(reader["description"])));
        environment.Properties.Add(new PSNoteProperty("CreatedBySid", ValueOrNull(reader["created_by_sid"])));
        environment.Properties.Add(new PSNoteProperty("CreatedByName", ValueOrNull(reader["created_by_name"])));
        environment.Properties.Add(new PSNoteProperty("CreatedTime", ToDbaDateTime(reader["created_time"])));
        OutputHelper.InsertTypeName(environment, "SsisEnvironment");
        return environment;
    }

    private bool DeleteEnvironment(EnvironmentTarget target)
    {
        string instance = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(target.Server);
        if (!ShouldProcess(instance, $"Removing SSIS environment {target.Name} from folder {target.FolderName}"))
        {
            return false;
        }

        try
        {
            using SqlCommand command = new("EXEC [SSISDB].[catalog].[delete_environment] @folder_name = @folderName, @environment_name = @environmentName", target.Server.ConnectionContext.SqlConnectionObject);
            command.Parameters.AddWithValue("@folderName", target.FolderName);
            command.Parameters.AddWithValue("@environmentName", target.Name);
            SetActiveCommand(command);
            try
            {
                command.ExecuteNonQuery();
            }
            finally
            {
                SetActiveCommand(null);
            }
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            StopFunction($"Failure removing SSIS environment {target.Name} from folder {target.FolderName} on {instance}", target: target.Name, exception: ex, continueLoop: true);
            return false;
        }

        return true;
    }
}
