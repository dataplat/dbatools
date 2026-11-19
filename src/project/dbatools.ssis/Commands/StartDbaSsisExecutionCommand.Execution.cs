#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// The catalog calls that create, parameterise, start and follow one execution.
/// </summary>
public sealed partial class StartDbaSsisExecutionCommand : DbaInstanceCmdlet
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
    /// An execution binds to a reference, not to an environment: a project has to reference an
    /// environment before it can run against it, and the same environment name can be referenced
    /// out of two folders, which is what -EnvironmentFolder disambiguates.
    /// </summary>
    /// <remarks>
    /// A relative reference stores environment_folder_name NULL and resolves in the project's own
    /// folder - catalog.create_environment_reference sets the lookup folder to @folder_name for
    /// reference_type 'R' and refuses a folder name outright, and it stores the given folder for
    /// 'A'. So the reference's effective folder is ISNULL(environment_folder_name, folders.name),
    /// and matching on the stored column alone let a project holding both a relative reference to
    /// Production and an absolute one to another folder's Production satisfy the predicate twice.
    /// TOP 1 then picked whichever row the plan reached first.
    /// </remarks>
    private long? ReadReferenceId(Server server)
    {
        // Unqualified means the environment beside the project, which is the one folder a caller
        // can name without ambiguity; anything else has to be asked for by folder.
        string sql = "SELECT TOP 1 references_.reference_id FROM [SSISDB].[catalog].[environment_references] references_ JOIN [SSISDB].[catalog].[projects] projects ON projects.project_id = references_.project_id JOIN [SSISDB].[catalog].[folders] folders ON folders.folder_id = projects.folder_id WHERE folders.name = @folderName AND projects.name = @projectName AND references_.environment_name = @environmentName AND ISNULL(references_.environment_folder_name, folders.name) = @environmentFolderName ORDER BY references_.reference_id";

        using SqlCommand command = new(sql, server.ConnectionContext.SqlConnectionObject);
        command.Parameters.AddWithValue("@folderName", Folder);
        command.Parameters.AddWithValue("@projectName", Project);
        command.Parameters.AddWithValue("@environmentName", Environment);
        command.Parameters.AddWithValue("@environmentFolderName", TestBound(nameof(EnvironmentFolder)) ? EnvironmentFolder : Folder);

        SetActiveCommand(command);
        try
        {
            object? result = command.ExecuteScalar();
            return result == null || result is DBNull ? null : Convert.ToInt64(result);
        }
        finally
        {
            SetActiveCommand(null);
        }
    }

    private long CreateExecution(Server server, long? referenceId)
    {
        using SqlCommand command = new("EXEC [SSISDB].[catalog].[create_execution] @folder_name = @folderName, @project_name = @projectName, @package_name = @packageName, @reference_id = @referenceId, @use32bitruntime = @use32BitRuntime, @execution_id = @executionId OUTPUT", server.ConnectionContext.SqlConnectionObject);
        command.Parameters.AddWithValue("@folderName", Folder);
        command.Parameters.AddWithValue("@projectName", Project);
        command.Parameters.AddWithValue("@packageName", Package);
        command.Parameters.AddWithValue("@referenceId", (object?)referenceId ?? DBNull.Value);
        command.Parameters.AddWithValue("@use32BitRuntime", Use32BitRuntime.ToBool());
        SqlParameter executionIdParameter = command.Parameters.Add("@executionId", System.Data.SqlDbType.BigInt);
        executionIdParameter.Direction = System.Data.ParameterDirection.Output;

        SetActiveCommand(command);
        try
        {
            command.ExecuteNonQuery();
        }
        finally
        {
            SetActiveCommand(null);
        }

        return Convert.ToInt64(executionIdParameter.Value);
    }

    private void SetParameterValues(Server server, long executionId)
    {
        if (Parameter != null)
        {
            foreach (DictionaryEntry entry in Parameter)
            {
                SetParameterValue(server, executionId, PackageParameterScope, Convert.ToString(entry.Key)!, entry.Value);
            }
        }

        if (ProjectParameter != null)
        {
            foreach (DictionaryEntry entry in ProjectParameter)
            {
                SetParameterValue(server, executionId, ProjectParameterScope, Convert.ToString(entry.Key)!, entry.Value);
            }
        }

        if (TestBound(nameof(LoggingLevel)))
        {
            SetParameterValue(server, executionId, SystemParameterScope, "LOGGING_LEVEL", LoggingLevel);
        }
    }

    private void SetParameterValue(Server server, long executionId, short scope, string parameterName, object? parameterValue)
    {
        using SqlCommand command = new("EXEC [SSISDB].[catalog].[set_execution_parameter_value] @execution_id = @executionId, @object_type = @objectType, @parameter_name = @parameterName, @parameter_value = @parameterValue", server.ConnectionContext.SqlConnectionObject);
        command.Parameters.AddWithValue("@executionId", executionId);
        command.Parameters.AddWithValue("@objectType", scope);
        command.Parameters.AddWithValue("@parameterName", parameterName);
        command.Parameters.AddWithValue("@parameterValue", Unwrap(parameterValue) ?? DBNull.Value);

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

    private void StartExecution(Server server, long executionId)
    {
        using SqlCommand command = new("EXEC [SSISDB].[catalog].[start_execution] @execution_id = @executionId", server.ConnectionContext.SqlConnectionObject);
        command.Parameters.AddWithValue("@executionId", executionId);

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

    /// <summary>
    /// Polls rather than setting the SYNCHRONIZED system parameter, which would make
    /// start_execution itself block for the whole package run with no client-side way to give up -
    /// and no way to implement -Timeout at all.
    /// </summary>
    /// <returns>False when the caller should not be handed an execution: the wait expired, or the
    /// package ended in a failing state, both of which are reported here.</returns>
    private bool WaitForCompletion(Server server, DbaInstanceParameter instance, long executionId)
    {
        DateTime deadline = TestBound(nameof(Timeout)) ? DateTime.UtcNow.AddSeconds(Timeout) : DateTime.MaxValue;

        while (true)
        {
            int status = ReadStatus(server, executionId);
            if (IsTerminalStatus(status))
            {
                if (!IsFailedStatus(status))
                {
                    return true;
                }

                // The status alone names no cause, and the catalog's own log is where the cause
                // is. A caller told only "Failed" has to go and find this view themselves.
                string reason = ReadOperationMessages(server, executionId);
                string detail = reason.Length == 0 ? string.Empty : $": {reason}";
                StopFunction($"SSIS package {Package} from project {Project} in folder {Folder} on {instance} finished as {StatusName(status)} (execution {executionId}){detail}", target: instance, continueLoop: true);
                return false;
            }

            if (DateTime.UtcNow >= deadline)
            {
                // Stopping the run would be a destructive act the caller did not ask for; that is
                // Stop-DbaSsisExecution's job. The execution id is in the message so they can.
                StopFunction($"Timed out after {Timeout} seconds waiting for SSIS package {Package} from project {Project} in folder {Folder} on {instance}; execution {executionId} is still {StatusName(ReadStatus(server, executionId))} and has NOT been stopped", target: instance, continueLoop: true);
                return false;
            }

            // Sleeping through the cmdlet's own cancellation check keeps Ctrl-C responsive during
            // a long wait; a bare Thread.Sleep would swallow it for the whole interval. The
            // deadline is checked here too, not only at the top of the loop - sleeping the whole
            // interval out first would let a -Timeout expire and be reported a poll interval late.
            for (int elapsed = 0; elapsed < PollIntervalSeconds; elapsed++)
            {
                if (Stopping)
                {
                    throw new PipelineStoppedException();
                }
                if (DateTime.UtcNow >= deadline)
                {
                    break;
                }
                System.Threading.Thread.Sleep(1000);
            }
        }
    }

    private int ReadStatus(Server server, long executionId)
    {
        using SqlCommand command = new("SELECT status FROM [SSISDB].[catalog].[executions] WHERE execution_id = @executionId", server.ConnectionContext.SqlConnectionObject);
        command.Parameters.AddWithValue("@executionId", executionId);

        SetActiveCommand(command);
        try
        {
            object? result = command.ExecuteScalar();
            return result == null || result is DBNull ? 0 : Convert.ToInt32(result);
        }
        finally
        {
            SetActiveCommand(null);
        }
    }

    private static string StatusName(int status)
    {
        return status switch
        {
            1 => "Created",
            2 => "Running",
            3 => "Cancelled",
            4 => "Failed",
            5 => "Pending",
            6 => "Halted",
            7 => "Succeeded",
            8 => "Stopping",
            9 => "Completed",
            _ => "Unknown"
        };
    }

    /// <summary>
    /// The failure is the news; losing the explanation must not replace it with a failure to read
    /// the explanation, so a read that goes wrong here reports nothing rather than throwing.
    /// </summary>
    private string ReadOperationMessages(Server server, long executionId)
    {
        try
        {
            using SqlCommand command = new("SELECT TOP 10 message FROM [SSISDB].[catalog].[operation_messages] WHERE operation_id = @executionId AND message_type = 120 ORDER BY operation_message_id", server.ConnectionContext.SqlConnectionObject);
            command.Parameters.AddWithValue("@executionId", executionId);

            List<string> messages = new();
            SetActiveCommand(command);
            try
            {
                using SqlDataReader reader = command.ExecuteReader();
                while (reader.Read())
                {
                    if (reader["message"] is string message)
                    {
                        messages.Add(message);
                    }
                }
            }
            finally
            {
                SetActiveCommand(null);
            }

            return string.Join(" | ", messages);
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception)
        {
            return string.Empty;
        }
    }
    /// <summary>
    /// Whether a column exists on one of the catalog's own views. The catalog ships as objects
    /// inside SSISDB, so what it exposes is a property of the database in front of you rather than
    /// of the engine hosting it - a restored catalog is older than its server, and the emit SELECT
    /// has to be built from what is actually there.
    /// </summary>
    private bool CatalogViewHasColumn(Server server, string viewName, string columnName)
    {
        using SqlCommand command = new("SELECT COUNT(*) FROM [SSISDB].sys.columns catalogColumns JOIN [SSISDB].sys.objects catalogObjects ON catalogObjects.object_id = catalogColumns.object_id JOIN [SSISDB].sys.schemas catalogSchemas ON catalogSchemas.schema_id = catalogObjects.schema_id WHERE catalogSchemas.name = 'catalog' AND catalogObjects.name = @viewName AND catalogColumns.name = @columnName", server.ConnectionContext.SqlConnectionObject);
        command.Parameters.AddWithValue("@viewName", viewName);
        command.Parameters.AddWithValue("@columnName", columnName);

        SetActiveCommand(command);
        try
        {
            object? result = command.ExecuteScalar();
            return result is not null and not DBNull && Convert.ToInt32(result, CultureInfo.InvariantCulture) > 0;
        }
        finally
        {
            SetActiveCommand(null);
        }
    }
}
