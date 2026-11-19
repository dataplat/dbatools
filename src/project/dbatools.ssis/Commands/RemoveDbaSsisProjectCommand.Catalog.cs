#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Utility;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// The catalog reads and writes Remove-DbaSsisProject makes, kept apart from the cmdlet's own lifecycle.
/// </summary>
public sealed partial class RemoveDbaSsisProjectCommand : DbaInstanceCmdlet
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
    /// Reads the matching projects in Get-DbaSsisProject's shape before they are removed. A null
    /// folderName searches the whole catalog, which is what makes a name that lives in two folders
    /// come back as two rows instead of silently resolving to whichever the server returned first.
    /// </summary>
    private List<PSObject> ReadProjects(Server server, string? folderName, string projectName)
    {
        string sql = "SELECT p.project_id, p.folder_id, f.name AS folder_name, p.name, p.description," +
                     " p.project_format_version, p.deployed_by_sid, p.deployed_by_name, p.last_deployed_time," +
                     " p.created_time, p.object_version_lsn, p.validation_status, p.last_validation_time" +
                     " FROM [SSISDB].[catalog].[projects] p" +
                     " JOIN [SSISDB].[catalog].[folders] f ON f.folder_id = p.folder_id" +
                     " WHERE p.name = @projectName";
        if (folderName != null)
        {
            sql += " AND f.name = @folderName";
        }
        sql += " ORDER BY f.name";

        using SqlCommand command = new(sql, server.ConnectionContext.SqlConnectionObject);
        command.Parameters.AddWithValue("@projectName", projectName);
        if (folderName != null)
        {
            command.Parameters.AddWithValue("@folderName", folderName);
        }

        SetActiveCommand(command);
        try
        {
            List<PSObject> projects = new();
            using SqlDataReader reader = command.ExecuteReader();
            while (reader.Read())
            {
                projects.Add(BuildProject(server, reader));
            }
            return projects;
        }
        finally
        {
            SetActiveCommand(null);
        }
    }

    private static PSObject BuildProject(Server server, SqlDataReader reader)
    {
        PSObject project = new();
        OutputHelper.AddInstanceProperties(project, server);
        project.Properties.Add(new PSNoteProperty("ProjectId", ValueOrNull(reader["project_id"])));
        project.Properties.Add(new PSNoteProperty("FolderId", ValueOrNull(reader["folder_id"])));
        project.Properties.Add(new PSNoteProperty("FolderName", ValueOrNull(reader["folder_name"])));
        project.Properties.Add(new PSNoteProperty("Name", ValueOrNull(reader["name"])));
        project.Properties.Add(new PSNoteProperty("Description", ValueOrNull(reader["description"])));
        project.Properties.Add(new PSNoteProperty("ProjectFormatVersion", ValueOrNull(reader["project_format_version"])));
        project.Properties.Add(new PSNoteProperty("DeployedBySid", ValueOrNull(reader["deployed_by_sid"])));
        project.Properties.Add(new PSNoteProperty("DeployedByName", ValueOrNull(reader["deployed_by_name"])));
        project.Properties.Add(new PSNoteProperty("LastDeployedTime", ToDbaDateTime(reader["last_deployed_time"])));
        project.Properties.Add(new PSNoteProperty("CreatedTime", ToDbaDateTime(reader["created_time"])));
        project.Properties.Add(new PSNoteProperty("ObjectVersionLsn", ValueOrNull(reader["object_version_lsn"])));
        project.Properties.Add(new PSNoteProperty("ValidationStatus", ValueOrNull(reader["validation_status"])));
        project.Properties.Add(new PSNoteProperty("LastValidationTime", ToDbaDateTime(reader["last_validation_time"])));
        OutputHelper.InsertTypeName(project, "SsisProject");
        return project;
    }

    private bool DeleteProject(ProjectTarget target)
    {
        string instance = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(target.Server);
        if (!ShouldProcess(instance, $"Removing SSIS project {target.Name} from folder {target.FolderName}"))
        {
            return false;
        }

        try
        {
            using SqlCommand command = new("EXEC [SSISDB].[catalog].[delete_project] @folder_name = @folderName, @project_name = @projectName", target.Server.ConnectionContext.SqlConnectionObject);
            command.Parameters.AddWithValue("@folderName", target.FolderName);
            command.Parameters.AddWithValue("@projectName", target.Name);
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
            StopFunction($"Failure removing SSIS project {target.Name} from folder {target.FolderName} on {instance}", target: target.Name, exception: ex, continueLoop: true);
            return false;
        }

        return true;
    }
}
