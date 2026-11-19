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
/// The catalog reads and writes Set-DbaSsisEnvironment makes, kept apart from the cmdlet's own lifecycle.
/// </summary>
public sealed partial class SetDbaSsisEnvironmentCommand : DbaInstanceCmdlet
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

    private bool EnvironmentExists(Server server, string folderName, string environmentName)
    {
        using SqlCommand command = new("SELECT COUNT(*) FROM [SSISDB].[catalog].[environments] e JOIN [SSISDB].[catalog].[folders] f ON f.folder_id = e.folder_id WHERE f.name = @folderName AND e.name = @environmentName", server.ConnectionContext.SqlConnectionObject);
        command.Parameters.AddWithValue("@folderName", folderName);
        command.Parameters.AddWithValue("@environmentName", environmentName);
        SetActiveCommand(command);
        try
        {
            return Convert.ToInt32(command.ExecuteScalar(), CultureInfo.InvariantCulture) > 0;
        }
        finally
        {
            SetActiveCommand(null);
        }
    }

    /// <summary>
    /// The folder and environment names a selection resolves to, read from the catalog views rather
    /// than assumed from what the caller typed. The folder comes back joined because every catalog
    /// procedure that touches an environment takes the folder name, never the id - and an
    /// environment name is only unique within its folder.
    /// </summary>
    private List<string[]> ResolveEnvironments(Server server, string[]? folderNames, string[]? environmentNames)
    {
        List<KeyValuePair<string, object>> queryParameters = new();
        StringBuilder sql = new();
        sql.Append("SELECT f.name AS folder_name, e.name AS environment_name");
        sql.Append(" FROM [SSISDB].[catalog].[environments] e");
        sql.Append(" JOIN [SSISDB].[catalog].[folders] f ON f.folder_id = e.folder_id");
        bool hasFilter = AppendNameFilter(sql, queryParameters, "f.name", folderNames, "folder", true);
        AppendNameFilter(sql, queryParameters, "e.name", environmentNames, "environment", !hasFilter);
        sql.Append(" ORDER BY f.name, e.name");

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
                    Convert.ToString(reader["environment_name"], CultureInfo.InvariantCulture) ?? String.Empty
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
    /// Bound-parameter presence, not string emptiness: set_environment_property accepts "" and that
    /// is how a description is cleared, so "not supplied" and "supplied empty" are different asks.
    /// DESCRIPTION is the only property name the proc accepts - its body branches on that one value
    /// and raises for anything else - which is why this is a -Description parameter and not a
    /// generic property/value pair.
    /// </summary>
    private bool ApplyDescription(EnvironmentTarget target)
    {
        if (!TestBound(nameof(Description)))
        {
            return true;
        }

        string instance = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(target.Server);
        if (!ShouldProcess(instance, $"Setting description on SSIS environment {target.Name} in folder {target.FolderName}"))
        {
            return false;
        }

        try
        {
            using SqlCommand command = new("EXEC [SSISDB].[catalog].[set_environment_property] @folder_name = @folderName, @environment_name = @environmentName, @property_name = @propertyName, @property_value = @propertyValue", target.Server.ConnectionContext.SqlConnectionObject);
            command.Parameters.AddWithValue("@folderName", target.FolderName);
            command.Parameters.AddWithValue("@environmentName", target.Name);
            command.Parameters.AddWithValue("@propertyName", "DESCRIPTION");
            command.Parameters.AddWithValue("@propertyValue", Description ?? String.Empty);
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
            StopFunction($"Failure setting the description on SSIS environment {target.Name} in folder {target.FolderName} on {instance}", target: target.Name, exception: ex, continueLoop: true);
            return false;
        }

        return true;
    }

    private bool ApplyRename(EnvironmentTarget target)
    {
        if (!TestBound(nameof(NewName)))
        {
            return true;
        }

        string instance = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(target.Server);
        if (!ShouldProcess(instance, $"Renaming SSIS environment {target.Name} to {NewName}"))
        {
            return false;
        }

        try
        {
            using SqlCommand command = new("EXEC [SSISDB].[catalog].[rename_environment] @folder_name = @folderName, @environment_name = @environmentName, @new_environment_name = @newName", target.Server.ConnectionContext.SqlConnectionObject);
            command.Parameters.AddWithValue("@folderName", target.FolderName);
            command.Parameters.AddWithValue("@environmentName", target.Name);
            command.Parameters.AddWithValue("@newName", NewName!);
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
            StopFunction($"Failure renaming SSIS environment {target.Name} to {NewName} on {instance}", target: target.Name, exception: ex, continueLoop: true);
            return false;
        }

        // Everything after this point looks the environment up under the name it now has.
        target.Name = NewName!;
        return true;
    }

    private bool ApplyMove(EnvironmentTarget target)
    {
        if (!TestBound(nameof(MoveToFolder)))
        {
            return true;
        }

        string instance = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(target.Server);
        if (!ShouldProcess(instance, $"Moving SSIS environment {target.Name} to folder {MoveToFolder}"))
        {
            return false;
        }

        try
        {
            using SqlCommand command = new("EXEC [SSISDB].[catalog].[move_environment] @source_folder = @sourceFolder, @environment_name = @environmentName, @destination_folder = @destinationFolder", target.Server.ConnectionContext.SqlConnectionObject);
            command.Parameters.AddWithValue("@sourceFolder", target.FolderName);
            command.Parameters.AddWithValue("@environmentName", target.Name);
            command.Parameters.AddWithValue("@destinationFolder", MoveToFolder!);
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
            StopFunction($"Failure moving SSIS environment {target.Name} from folder {target.FolderName} to folder {MoveToFolder} on {instance}", target: target.Name, exception: ex, continueLoop: true);
            return false;
        }

        target.FolderName = MoveToFolder!;
        return true;
    }

    /// <summary>
    /// Re-read rather than re-report: the caller gets what the catalog holds, which is how a rename
    /// plus a move shows the final name in the final folder, and how Get -&gt; Set -&gt; Get composes.
    /// </summary>
    private void EmitEnvironment(EnvironmentTarget target)
    {
        using SqlCommand command = new("SELECT e.environment_id, e.folder_id, f.name AS folder_name, e.name, e.description, e.created_by_sid, e.created_by_name, e.created_time FROM [SSISDB].[catalog].[environments] e JOIN [SSISDB].[catalog].[folders] f ON f.folder_id = e.folder_id WHERE f.name = @folderName AND e.name = @environmentName", target.Server.ConnectionContext.SqlConnectionObject);
        command.Parameters.AddWithValue("@folderName", target.FolderName);
        command.Parameters.AddWithValue("@environmentName", target.Name);
        SetActiveCommand(command);
        try
        {
            using SqlDataReader reader = command.ExecuteReader();
            while (reader.Read())
            {
                PSObject environment = new();
                OutputHelper.AddInstanceProperties(environment, target.Server);
                environment.Properties.Add(new PSNoteProperty("EnvironmentId", ValueOrNull(reader["environment_id"])));
                environment.Properties.Add(new PSNoteProperty("FolderId", ValueOrNull(reader["folder_id"])));
                environment.Properties.Add(new PSNoteProperty("FolderName", ValueOrNull(reader["folder_name"])));
                environment.Properties.Add(new PSNoteProperty("Name", ValueOrNull(reader["name"])));
                environment.Properties.Add(new PSNoteProperty("Description", ValueOrNull(reader["description"])));
                environment.Properties.Add(new PSNoteProperty("CreatedBySid", ValueOrNull(reader["created_by_sid"])));
                environment.Properties.Add(new PSNoteProperty("CreatedByName", ValueOrNull(reader["created_by_name"])));
                environment.Properties.Add(new PSNoteProperty("CreatedTime", ToDbaDateTime(reader["created_time"])));
                OutputHelper.InsertTypeName(environment, "SsisEnvironment");
                OutputHelper.SetDefaultDisplayPropertySet(environment, "ComputerName", "InstanceName", "SqlInstance", "FolderName", "Name", "Description", "CreatedByName", "CreatedTime");
                WriteObject(environment);
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
