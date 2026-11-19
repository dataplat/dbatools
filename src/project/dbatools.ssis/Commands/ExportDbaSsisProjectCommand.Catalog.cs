#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Utility;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// The catalog reads Export-DbaSsisProject makes, kept apart from the cmdlet's own lifecycle.
/// </summary>
public sealed partial class ExportDbaSsisProjectCommand : DbaInstanceCmdlet
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
    /// The folder and project names a selection resolves to, read from the catalog views rather
    /// than assumed from what the caller typed - a project that is not there has to be reported as
    /// missing before any file is opened for it.
    /// </summary>
    private List<string[]> ResolveProjects(Server server, string[]? folderNames, string[]? projectNames)
    {
        List<KeyValuePair<string, object>> queryParameters = new();
        StringBuilder sql = new();
        sql.Append("SELECT f.name AS folder_name, p.name AS project_name");
        sql.Append(" FROM [SSISDB].[catalog].[projects] p");
        sql.Append(" JOIN [SSISDB].[catalog].[folders] f ON f.folder_id = p.folder_id");
        bool hasFilter = AppendNameFilter(sql, queryParameters, "f.name", folderNames, "folder", true);
        AppendNameFilter(sql, queryParameters, "p.name", projectNames, "project", !hasFilter);
        sql.Append(" ORDER BY f.name, p.name");

        List<string[]> resolved = new();
        using SqlCommand command = new(sql.ToString(), server.ConnectionContext.SqlConnectionObject);
        foreach (KeyValuePair<string, object> parameter in queryParameters)
        {
            command.Parameters.AddWithValue(parameter.Key, parameter.Value);
        }

        SetActiveCommand(command);
        try
        {
            using SqlDataReader reader = command.ExecuteReader();
            while (reader.Read())
            {
                resolved.Add(new[]
                {
                    Convert.ToString(reader["folder_name"], CultureInfo.InvariantCulture) ?? String.Empty,
                    Convert.ToString(reader["project_name"], CultureInfo.InvariantCulture) ?? String.Empty
                });
            }
        }
        finally
        {
            SetActiveCommand(null);
        }

        return resolved;
    }

    private static bool AppendNameFilter(StringBuilder sql, List<KeyValuePair<string, object>> queryParameters, string column, string[]? names, string parameterPrefix, bool first)
    {
        if (!FilterHelper.IsActive(names))
        {
            return false;
        }

        sql.Append(first ? " WHERE " : " AND ");
        sql.Append(column).Append(" IN (");
        int ordinal = 0;
        foreach (string name in names!)
        {
            ordinal++;
            string parameterName = parameterPrefix + ordinal.ToString(CultureInfo.InvariantCulture);
            if (ordinal > 1)
            {
                sql.Append(", ");
            }
            sql.Append('@').Append(parameterName);
            queryParameters.Add(new KeyValuePair<string, object>(parameterName, name));
        }
        sql.Append(')');
        return true;
    }

    /// <summary>
    /// catalog.get_project hands the deployed .ispac back as a single varbinary column in a result
    /// set - there is no output parameter - and raises rather than returning empty when the project
    /// is not there.
    /// </summary>
    private byte[]? ReadProjectStream(ProjectTarget target)
    {
        using SqlCommand command = new("EXEC [SSISDB].[catalog].[get_project] @folder_name = @folderName, @project_name = @projectName", target.Server.ConnectionContext.SqlConnectionObject);
        command.Parameters.AddWithValue("@folderName", target.FolderName);
        command.Parameters.AddWithValue("@projectName", target.ProjectName);
        // A project stream is whatever the build produced, and reassembling a large one routinely
        // outlives SqlCommand's 30 second default; the connection's budget is the caller's.
        command.CommandTimeout = target.Server.ConnectionContext.StatementTimeout;

        SetActiveCommand(command);
        try
        {
            object? result = command.ExecuteScalar();
            return result as byte[];
        }
        finally
        {
            SetActiveCommand(null);
        }
    }

    /// <summary>
    /// The exported project is re-read and decorated exactly like Get-DbaSsisProject, with the file
    /// that was written and its size attached, so a pipeline can verify what landed where instead of
    /// trusting that the export happened.
    /// </summary>
    private void EmitProject(ProjectTarget target, string destination, long bytes)
    {
        using SqlCommand command = new("SELECT projects.project_id, projects.folder_id, folders.name AS folder_name, projects.name, projects.description, projects.project_format_version, projects.deployed_by_sid, projects.deployed_by_name, projects.last_deployed_time, projects.created_time, projects.object_version_lsn, projects.validation_status, projects.last_validation_time FROM [SSISDB].[catalog].[projects] projects JOIN [SSISDB].[catalog].[folders] folders ON folders.folder_id = projects.folder_id WHERE folders.name = @folderName AND projects.name = @projectName", target.Server.ConnectionContext.SqlConnectionObject);
        command.Parameters.AddWithValue("@folderName", target.FolderName);
        command.Parameters.AddWithValue("@projectName", target.ProjectName);

        SetActiveCommand(command);
        try
        {
            using SqlDataReader reader = command.ExecuteReader();
            while (reader.Read())
            {
                PSObject project = new();
                OutputHelper.AddInstanceProperties(project, target.Server);
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
                project.Properties.Add(new PSNoteProperty("FilePath", destination));
                project.Properties.Add(new PSNoteProperty("Bytes", bytes));
                OutputHelper.InsertTypeName(project, "SsisProject");
                OutputHelper.SetDefaultDisplayPropertySet(project, "ComputerName", "InstanceName", "SqlInstance", "FolderName", "Name", "FilePath", "Bytes");
                WriteObject(project);
            }
        }
        finally
        {
            SetActiveCommand(null);
        }
    }

    private static object? ValueOrNull(object raw)
    {
        return raw is DBNull ? null : raw;
    }

    private static object? ToDbaDateTime(object raw)
    {
        if (raw is DateTimeOffset offsetValue)
        {
            return new DbaDateTime(offsetValue.DateTime);
        }
        if (raw is DateTime dateTimeValue)
        {
            return new DbaDateTime(dateTimeValue);
        }
        return null;
    }
}
