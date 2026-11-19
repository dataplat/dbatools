#nullable enable

using System;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Utility;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// The catalog reads and writes Stop-DbaSsisExecution makes, kept apart from the cmdlet's own lifecycle.
/// </summary>
public sealed partial class StopDbaSsisExecutionCommand : DbaInstanceCmdlet
{
    /// <summary>The status code the catalog uses for an execution that is currently running.</summary>
    private const int RunningStatus = 2;

    /// <summary>
    /// Get-DbaSsisExecution's own projection of catalog.executions, so a stopped execution comes
    /// back in the same shape the command that found it emits. Filtered to one id.
    /// </summary>
    private const string ExecutionSql = @"
        WITH
            cteLoglevel AS (
                SELECT
                    execution_id AS ExecutionID,
                    CAST(parameter_value AS INT) AS LoggingLevel
                FROM
                    [SSISDB].[catalog].[execution_parameter_values]
                WHERE
                    parameter_name = 'LOGGING_LEVEL'
            )
            , cteStatus AS (
                SELECT
                     [key]
                    ,[code]
                FROM (
                    VALUES
                          ( 1,'Created'  )
                        , ( 2,'Running'  )
                        , ( 3,'Cancelled')
                        , ( 4,'Failed'   )
                        , ( 5,'Pending'  )
                        , ( 6,'Halted'   )
                        , ( 7,'Succeeded')
                        , ( 8,'Stopping' )
                        , ( 9,'Completed')
                ) codes([key],[code])
            )
            SELECT
                      e.execution_id AS ExecutionID
                    , e.folder_name AS FolderName
                    , e.project_name AS ProjectName
                    , e.package_name AS PackageName
                    , e.project_lsn AS ProjectLsn
                    , Environment = ISNULL(e.environment_folder_name, '') + ISNULL('\' + e.environment_name,  '')
                    , s.code AS StatusCode
                    , e.start_time AS StartTime
                    , e.end_time AS EndTime
                    , ElapsedMinutes = DATEDIFF(mi, e.start_time, e.end_time)
                    , l.LoggingLevel
                    , e.reference_id AS ReferenceId
                    , e.reference_type AS ReferenceType
                    , e.environment_folder_name AS EnvironmentFolderName
                    , e.environment_name AS EnvironmentName
                    , e.executed_as_name AS ExecutedAsName
                    , e.use32bitruntime AS Use32BitRuntime
                    , e.operation_type AS OperationType
                    , e.created_time AS CreatedTime
                    , e.object_type AS ObjectType
                    , e.object_id AS ObjectId
                    , e.status AS Status
                    , e.caller_name AS CallerName
                    , e.process_id AS ProcessId
                    , e.stopped_by_name AS StoppedByName
                    , e.dump_id AS DumpId
                    , e.server_name AS ServerName
                    , e.machine_name AS MachineName
                    , e.worker_agent_id AS WorkerAgentId
                    , e.total_physical_memory_kb AS TotalPhysicalMemoryKb
                    , e.available_physical_memory_kb AS AvailablePhysicalMemoryKb
                    , e.total_page_file_kb AS TotalPageFileKb
                    , e.available_page_file_kb AS AvailablePageFileKb
                    , e.cpu_count AS CpuCount
                    , e.executed_count AS ExecutedCount
            FROM
                [SSISDB].[catalog].[executions] e
                LEFT OUTER JOIN cteLoglevel l
                    ON e.execution_id = l.ExecutionID
                LEFT OUTER JOIN cteStatus s
                    ON s.[key] = e.status
            WHERE e.execution_id = @executionId
            OPTION  ( RECOMPILE );
        ";

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

    private void StopExecution(ExecutionTarget target)
    {
        string instance = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(target.Server);

        PSObject? before = ReadExecution(target.Server, target.Id);
        if (before == null)
        {
            StopFunction($"SSIS execution {target.Id} does not exist on {instance}", target: target.Target, category: ErrorCategory.ObjectNotFound, continueLoop: true);
            return;
        }

        // Measured against the catalog rather than assumed from the status names: prepare_stop
        // selects the operation only WHERE status = 2 OR status = 8, and raises 27126 straight away
        // when it is 8 - so Running is the only status a stop can be issued for. Everything else,
        // including an execution that finished between the Get- and this call, is reported and
        // skipped rather than handed to the server to refuse.
        object? statusValue = before.Properties["Status"]?.Value;
        int status = statusValue == null ? 0 : Convert.ToInt32(statusValue, CultureInfo.InvariantCulture);
        if (status != RunningStatus)
        {
            string statusCode = Convert.ToString(before.Properties["StatusCode"]?.Value, CultureInfo.InvariantCulture) ?? status.ToString(CultureInfo.InvariantCulture);
            StopFunction($"SSIS execution {target.Id} on {instance} is {statusCode}, not Running, so there is nothing to stop", target: target.Target, category: ErrorCategory.InvalidOperation, continueLoop: true);
            return;
        }

        if (!ShouldProcess(instance, $"Stopping SSIS execution {target.Id}"))
        {
            return;
        }

        try
        {
            using SqlCommand command = new("EXEC [SSISDB].[catalog].[stop_operation] @operation_id = @executionId", target.Server.ConnectionContext.SqlConnectionObject);
            // catalog.stop_operation names its parameter @operation_id while every caller here holds
            // an execution id. They are the same key space, not a coincidence: sys.foreign_keys
            // reports FK_Executions_ExecutionId_Operations, internal.executions(execution_id) ->
            // internal.operations(operation_id).
            command.Parameters.AddWithValue("@executionId", target.Id);
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
            StopFunction($"Failure stopping SSIS execution {target.Id} on {instance}", target: target.Target, exception: ex, continueLoop: true);
            return;
        }

        // Read back rather than report: the stop is a request, so what the caller needs to see is
        // the status the catalog moved the execution to, which is usually Stopping and not yet
        // Cancelled.
        PSObject? after = ReadExecution(target.Server, target.Id);
        if (after != null)
        {
            WriteObject(after);
        }
    }

    private PSObject? ReadExecution(Server server, long executionId)
    {
        using SqlCommand command = new(ExecutionSql, server.ConnectionContext.SqlConnectionObject);
        command.Parameters.AddWithValue("@executionId", executionId);

        SetActiveCommand(command);
        try
        {
            using SqlDataReader reader = command.ExecuteReader();
            if (!reader.Read())
            {
                return null;
            }

            PSObject execution = new();
            OutputHelper.AddInstanceProperties(execution, server);
            for (int ordinal = 0; ordinal < reader.FieldCount; ordinal++)
            {
                string name = reader.GetName(ordinal);
                object raw = reader.GetValue(ordinal);
                object? value = name is "StartTime" or "EndTime" or "CreatedTime" ? ToDbaDateTime(raw) : ValueOrNull(raw);
                execution.Properties.Add(new PSNoteProperty(name, value));
            }
            OutputHelper.InsertTypeName(execution, "SsisExecution");
            OutputHelper.SetDefaultDisplayPropertySet(execution, "ComputerName", "InstanceName", "SqlInstance", "ExecutionID", "FolderName", "ProjectName", "PackageName", "StatusCode", "StartTime", "EndTime", "ElapsedMinutes");
            return execution;
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
