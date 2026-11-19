#nullable enable

using System;
using System.Management.Automation;
using Dataplat.Dbatools.Utility;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// The catalog reads and writes Remove-DbaSsisFolder makes, kept apart from the cmdlet's own lifecycle.
/// </summary>
public sealed partial class RemoveDbaSsisFolderCommand : DbaInstanceCmdlet
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
    /// Reads the folder in Get-DbaSsisFolder's shape before it is removed. Null means no such
    /// folder, which is how the caller tells "absent" from "present but empty description".
    /// </summary>
    private PSObject? ReadFolder(Server server, string folderName)
    {
        using SqlCommand command = new("SELECT folder_id, name, description, created_by_sid, created_by_name, created_time FROM [SSISDB].[catalog].[folders] WHERE name = @folderName", server.ConnectionContext.SqlConnectionObject);
        command.Parameters.AddWithValue("@folderName", folderName);
        SetActiveCommand(command);
        try
        {
            using SqlDataReader reader = command.ExecuteReader();
            if (!reader.Read())
            {
                return null;
            }

            PSObject folder = new();
            OutputHelper.AddInstanceProperties(folder, server);
            folder.Properties.Add(new PSNoteProperty("FolderId", ValueOrNull(reader["folder_id"])));
            folder.Properties.Add(new PSNoteProperty("Name", ValueOrNull(reader["name"])));
            folder.Properties.Add(new PSNoteProperty("Description", ValueOrNull(reader["description"])));
            folder.Properties.Add(new PSNoteProperty("CreatedBySid", ValueOrNull(reader["created_by_sid"])));
            folder.Properties.Add(new PSNoteProperty("CreatedByName", ValueOrNull(reader["created_by_name"])));
            folder.Properties.Add(new PSNoteProperty("CreatedTime", ToDbaDateTime(reader["created_time"])));
            OutputHelper.InsertTypeName(folder, "SsisFolder");
            return folder;
        }
        finally
        {
            SetActiveCommand(null);
        }
    }

    private bool DeleteFolder(FolderTarget target)
    {
        string instance = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(target.Server);
        if (!ShouldProcess(instance, $"Removing SSIS folder {target.Name}"))
        {
            return false;
        }

        try
        {
            using SqlCommand command = new("EXEC [SSISDB].[catalog].[delete_folder] @folder_name = @folderName", target.Server.ConnectionContext.SqlConnectionObject);
            command.Parameters.AddWithValue("@folderName", target.Name);
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
            // Whether a folder that still holds projects or environments can go is the server's
            // rule and it is version-dependent, so its error travels out as written instead of
            // being pre-empted by a count this command would have to invent.
            StopFunction($"Failure removing SSIS folder {target.Name} on {instance}", target: target.Name, exception: ex, continueLoop: true);
            return false;
        }

        return true;
    }
}
