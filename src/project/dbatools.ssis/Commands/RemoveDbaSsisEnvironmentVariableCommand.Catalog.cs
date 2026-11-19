#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Utility;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// The catalog reads and writes Remove-DbaSsisEnvironmentVariable makes, kept apart from the cmdlet's own lifecycle.
/// </summary>
public sealed partial class RemoveDbaSsisEnvironmentVariableCommand : DbaInstanceCmdlet
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
    /// Reads the matching variables in the shape Get-DbaSsisEnvironmentVariable emits, before they
    /// are removed. A null folderName or environmentName widens the search, which is what makes a
    /// name that lives in two environments come back as two rows instead of silently resolving to
    /// whichever the server returned first.
    /// </summary>
    /// <remarks>
    /// The read is against internal.environment_variables because catalog.environment_variables
    /// hides the row's own value column behind the caller's permissions; the encrypted
    /// sensitive_value column is deliberately not selected, so a secret is never carried out even
    /// as ciphertext. Value is the stored column, which the catalog leaves null for a sensitive
    /// variable.
    /// </remarks>
    private List<PSObject> ReadVariables(Server server, string? folderName, string? environmentName, string variableName)
    {
        string sql = "SELECT f.name AS folder_name, e.name AS environment_name, v.variable_id, v.name," +
                     " v.description, v.type, v.sensitive, v.base_data_type, v.value" +
                     " FROM [SSISDB].[internal].[environment_variables] v" +
                     " JOIN [SSISDB].[catalog].[environments] e ON e.environment_id = v.environment_id" +
                     " JOIN [SSISDB].[catalog].[folders] f ON f.folder_id = e.folder_id" +
                     " WHERE v.name = @variableName";
        if (folderName != null)
        {
            sql += " AND f.name = @folderName";
        }
        if (environmentName != null)
        {
            sql += " AND e.name = @environmentName";
        }
        sql += " ORDER BY f.name, e.name";

        using SqlCommand command = new(sql, server.ConnectionContext.SqlConnectionObject);
        command.Parameters.AddWithValue("@variableName", variableName);
        if (folderName != null)
        {
            command.Parameters.AddWithValue("@folderName", folderName);
        }
        if (environmentName != null)
        {
            command.Parameters.AddWithValue("@environmentName", environmentName);
        }

        SetActiveCommand(command);
        try
        {
            List<PSObject> variables = new();
            using SqlDataReader reader = command.ExecuteReader();
            while (reader.Read())
            {
                variables.Add(BuildVariable(server, reader));
            }
            return variables;
        }
        finally
        {
            SetActiveCommand(null);
        }
    }

    private static PSObject BuildVariable(Server server, SqlDataReader reader)
    {
        PSObject variable = new();
        OutputHelper.AddInstanceProperties(variable, server);
        variable.Properties.Add(new PSNoteProperty("Folder", ValueOrNull(reader["folder_name"])));
        variable.Properties.Add(new PSNoteProperty("Environment", ValueOrNull(reader["environment_name"])));
        variable.Properties.Add(new PSNoteProperty("Id", ValueOrNull(reader["variable_id"])));
        variable.Properties.Add(new PSNoteProperty("Name", ValueOrNull(reader["name"])));
        variable.Properties.Add(new PSNoteProperty("Description", ValueOrNull(reader["description"])));
        variable.Properties.Add(new PSNoteProperty("Type", ValueOrNull(reader["type"])));
        variable.Properties.Add(new PSNoteProperty("IsSensitive", ValueOrNull(reader["sensitive"])));
        variable.Properties.Add(new PSNoteProperty("BaseDataType", ValueOrNull(reader["base_data_type"])));
        variable.Properties.Add(new PSNoteProperty("Value", ValueOrNull(reader["value"])));
        return variable;
    }

    private bool DeleteVariable(VariableTarget target)
    {
        string instance = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(target.Server);
        if (!ShouldProcess(instance, $"Removing SSIS environment variable {target.Name} from environment {target.EnvironmentName} of folder {target.FolderName}"))
        {
            return false;
        }

        try
        {
            using SqlCommand command = new("EXEC [SSISDB].[catalog].[delete_environment_variable] @folder_name = @folderName, @environment_name = @environmentName, @variable_name = @variableName", target.Server.ConnectionContext.SqlConnectionObject);
            command.Parameters.AddWithValue("@folderName", target.FolderName);
            command.Parameters.AddWithValue("@environmentName", target.EnvironmentName);
            command.Parameters.AddWithValue("@variableName", target.Name);
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
            StopFunction($"Failure removing SSIS environment variable {target.Name} from {target.FolderName}\\{target.EnvironmentName} on {instance}", target: target.Name, exception: ex, continueLoop: true);
            return false;
        }

        return true;
    }

    private static object? ValueOrNull(object raw)
    {
        return raw is DBNull ? null : raw;
    }
}
