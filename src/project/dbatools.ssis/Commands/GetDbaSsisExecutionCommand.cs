#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// <para type="synopsis">Retrieves SSIS package executions from the SSIS catalog database (SSISDB).</para>
/// <para type="description">Retrieves executions recorded in the SSIS catalog (SSISDB) - what ran, under which project and package, when it started and finished, and how it ended. Use it to find failed or long-running packages, to track execution patterns over time, and to investigate deployment issues.</para>
/// <para type="description">Reads the catalog.executions view directly with parameterized T-SQL rather than the Integration Services object model, so it works on both PowerShell editions and on Linux. An instance with no SSIS catalog reports a warning and returns nothing.</para>
/// <para type="description">Get-DbaSsisExecutionHistory is an alias for this command and every parameter it accepted still binds in the same position, so existing scripts keep working. The reported properties it documented are reproduced under the same names.</para>
/// <para type="description">Use -IncludeOperations to attach the catalog.operations row behind each execution, and -IncludeMessages to attach its catalog.operation_messages rows. Both are off by default because operation_messages is the largest table in a busy catalog and pulling it unasked turns a routine status check into a full log dump.</para>
/// </summary>
/// <example>
///   <code>PS C:\&gt; Get-DbaSsisExecution -SqlInstance SMTQ01 -Folder SMTQ_PRC</code>
///   <para>Gets every execution on SMTQ01 that ran out of the SMTQ_PRC folder.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Get-DbaSsisExecution -SqlInstance SMTQ01 -Status Failed, Cancelled -Since (Get-Date).AddDays(-1)</code>
///   <para>Gets the executions that failed or were cancelled in the last day.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Get-DbaSsisExecution -SqlInstance SMTQ01 -ExecutionId 40001 -IncludeMessages | Select-Object -ExpandProperty Messages</code>
///   <para>Gets the log messages the catalog recorded for one execution.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Get-DbaSsisExecution -SqlInstance SMTQ01 -IncludeOperations -Type 200</code>
///   <para>Attaches the operation row behind each execution and keeps only operation type 200 (package execution). The documented types include 1 (integration services initialization), 2 (retention window), 3 (MaxProjectVersion), 101 (deploy project), 106 (restore project), 200 (create and start execution), 202 (stop operation) and 300 (validate project); the domain grows with the server version, which is why this parameter takes the number rather than a friendly name that would go stale and silently drop rows.</para>
/// </example>
[Cmdlet(VerbsCommon.Get, "DbaSsisExecution")]
[Alias("Get-DbaSsisExecutionHistory")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaSsisExecutionCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>Limits results to executions that started on or after this date and time.</summary>
    [Parameter(Position = 2)]
    [PsDateTimeCast]
    public DateTime Since { get; set; }

    /// <summary>Filters results to specific execution statuses.</summary>
    [Parameter(Position = 3)]
    [ValidateSet("Created", "Running", "Cancelled", "Failed", "Pending", "Halted", "Succeeded", "Stopping", "Completed")]
    public string[]? Status { get; set; }

    /// <summary>Filters results to specific SSIS projects deployed to the catalog. Names are matched exactly - this is a name list, not a pattern.</summary>
    [Parameter(Position = 4)]
    public string[]? Project { get; set; }

    /// <summary>Filters results to specific SSIS catalog folders. Names are matched exactly - this is a name list, not a pattern.</summary>
    [Parameter(Position = 5)]
    public string[]? Folder { get; set; }

    /// <summary>Filters results to specific SSIS environments used during execution. Names are matched exactly - this is a name list, not a pattern.</summary>
    [Parameter(Position = 6)]
    public string[]? Environment { get; set; }

    /// <summary>Limits results to specific execution ids.</summary>
    [Parameter(Position = 7)]
    public long[]? ExecutionId { get; set; }

    /// <summary>Limits the attached operations to specific catalog.operations operation_type values. Only meaningful with -IncludeOperations.</summary>
    [Parameter(Position = 8)]
    public int[]? Type { get; set; }

    /// <summary>Attaches the catalog.operations row behind each execution as an Operations property.</summary>
    [Parameter]
    public SwitchParameter IncludeOperations { get; set; }

    /// <summary>Attaches the catalog.operation_messages rows for each execution as a Messages property.</summary>
    [Parameter]
    public SwitchParameter IncludeMessages { get; set; }

    private string _sql = string.Empty;
    private readonly List<KeyValuePair<string, object>> _queryParameters = new();

    protected override void BeginProcessing()
    {
        // Silently ignoring -Type would look like the filter had been applied and returned
        // everything, which is the wrong way round for a parameter whose whole job is to narrow.
        if (FilterHelper.IsActive(Type) && !IncludeOperations)
        {
            StopFunction("-Type filters the operations attached by -IncludeOperations, so it does nothing on its own. Add -IncludeOperations or drop -Type.");
            return;
        }

        // ValidateSet binds case-insensitively, so the lookup has to as well.
        Dictionary<string, int> statuses = new(StringComparer.OrdinalIgnoreCase)
        {
            ["Created"] = 1,
            ["Running"] = 2,
            ["Cancelled"] = 3,
            ["Failed"] = 4,
            ["Pending"] = 5,
            ["Halted"] = 6,
            ["Succeeded"] = 7,
            ["Stopping"] = 8,
            ["Completed"] = 9,
        };

        string statusq = string.Empty;
        if (FilterHelper.IsActive(Status))
        {
            List<string> statusCodes = new();
            foreach (string status in Status!)
            {
                statusCodes.Add(statuses[status].ToString(CultureInfo.InvariantCulture));
            }
            statusq = "\n\t\tAND e.[status] IN (" + string.Join(",", statusCodes) + ")";
        }

        string projectq = BuildValuePredicate(Project, "project", "e.[project_name]");
        string folderq = BuildValuePredicate(Folder, "folder", "e.[folder_name]");
        string environmentq = BuildValuePredicate(Environment, "environment", "e.[environment_name]");

        string executionq = string.Empty;
        if (ExecutionId != null && ExecutionId.Length > 0)
        {
            StringBuilder predicate = new();
            predicate.Append("\n\t\tAND ( 1=0 ");
            int ordinal = 0;
            foreach (long id in ExecutionId)
            {
                ordinal++;
                string parameterName = "executionid" + ordinal.ToString(CultureInfo.InvariantCulture);
                predicate.Append("\n\t\t\tOR e.[execution_id] = @").Append(parameterName);
                _queryParameters.Add(new KeyValuePair<string, object>(parameterName, id));
            }
            predicate.Append("\n\t\t)");
            executionq = predicate.ToString();
        }

        // An unbound [datetime] is DateTime.MinValue on both editions, which is what the
        // superseded command's `if ($Since)` test treated as "not supplied".
        string sinceq = string.Empty;
        if (Since != default)
        {
            sinceq = "\n\t\tAND e.[start_time] >= @since";
            _queryParameters.Add(new KeyValuePair<string, object>("since", Since));
        }

        // Three-part naming keeps the connection on whatever database it opened against, so the
        // read never has to switch context on a connection the caller may be reusing.
        _sql = @"
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
            WHERE 1=1" + statusq + projectq + folderq + environmentq + executionq + sinceq + @"
            ORDER BY e.execution_id
            OPTION  ( RECOMPILE );
        ";

        WriteMessage(MessageLevel.Debug, "\nSQL statement: " + _sql);
        StringBuilder parameterText = new();
        foreach (KeyValuePair<string, object> parameter in _queryParameters)
        {
            parameterText.Append(parameter.Key).Append(" = ").Append(Convert.ToString(parameter.Value, CultureInfo.InvariantCulture)).Append('\n');
        }
        WriteMessage(MessageLevel.Debug, "\nParameters:" + parameterText);
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // The SSIS catalog schema arrived in SQL 2012, so an older instance is refused with
            // the version message rather than failing later on a missing catalog schema.
            Server server = ConnectInstance(instance, "Failure", minimumVersion: 11);
            if (server == null)
            {
                continue;
            }

            try
            {
                // ConnectionService hands back a Server whose ConnectionContext may still be
                // lazy; SqlConnectionObject is only usable once it has actually connected.
                if (!server.ConnectionContext.IsOpen)
                {
                    server.ConnectionContext.Connect();
                }

                if (!CatalogExists(server))
                {
                    StopFunction($"No SSIS catalog (SSISDB) found on {instance}", target: instance, continueLoop: true);
                    continue;
                }

                // The operations and messages reads need the same connection, which cannot serve a
                // second command while a reader is open, so asking for them is what forces the
                // executions to be held. Without a switch the rows still go straight to the pipeline.
                List<PSObject>? pending = IncludeOperations || IncludeMessages ? new List<PSObject>() : null;

                using SqlCommand command = new(_sql, server.ConnectionContext.SqlConnectionObject);
                foreach (KeyValuePair<string, object> parameter in _queryParameters)
                {
                    command.Parameters.AddWithValue(parameter.Key, parameter.Value);
                }
                SetActiveCommand(command);
                try
                {
                    using SqlDataReader reader = command.ExecuteReader();
                    while (reader.Read())
                    {
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
                        if (pending == null)
                        {
                            WriteObject(execution);
                        }
                        else
                        {
                            pending.Add(execution);
                        }
                    }
                }
                finally
                {
                    SetActiveCommand(null);
                }

                if (pending == null)
                {
                    continue;
                }

                foreach (PSObject execution in pending)
                {
                    long executionId = Convert.ToInt64(execution.Properties["ExecutionID"].Value, CultureInfo.InvariantCulture);
                    if (IncludeOperations)
                    {
                        execution.Properties.Add(new PSNoteProperty("Operations", ReadOperations(server, executionId)));
                    }
                    if (IncludeMessages)
                    {
                        execution.Properties.Add(new PSNoteProperty("Messages", ReadMessages(server, executionId)));
                    }
                    WriteObject(execution);
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StopFunction($"Failure retrieving SSIS executions from {instance}", target: instance, exception: ex, continueLoop: true);
            }
        }
    }

    /// <summary>
    /// catalog.executions is a projection over catalog.operations and shares its key, so an
    /// execution's operation row is the one whose operation_id equals the execution_id. There is
    /// no other correlation column, which is also why -Type can empty this list: an execution
    /// whose operation_type is not in the requested set attaches nothing.
    /// </summary>
    private PSObject[] ReadOperations(Server server, long executionId)
    {
        StringBuilder sql = new();
        sql.Append("SELECT operation_id AS OperationId, operation_type AS OperationType, created_time AS CreatedTime,");
        sql.Append(" object_type AS ObjectType, object_id AS ObjectId, object_name AS ObjectName, status AS Status,");
        sql.Append(" start_time AS StartTime, end_time AS EndTime, caller_name AS CallerName, process_id AS ProcessId,");
        sql.Append(" stopped_by_name AS StoppedByName, server_name AS ServerName, machine_name AS MachineName,");
        sql.Append(" operation_guid AS OperationGuid");
        sql.Append(" FROM [SSISDB].[catalog].[operations] WHERE operation_id = @operationId");

        List<KeyValuePair<string, object>> parameters = new()
        {
            new KeyValuePair<string, object>("operationId", executionId),
        };

        if (FilterHelper.IsActive(Type))
        {
            sql.Append(" AND operation_type IN (");
            int ordinal = 0;
            foreach (int operationType in Type!)
            {
                ordinal++;
                string parameterName = "operationtype" + ordinal.ToString(CultureInfo.InvariantCulture);
                if (ordinal > 1)
                {
                    sql.Append(", ");
                }
                sql.Append('@').Append(parameterName);
                parameters.Add(new KeyValuePair<string, object>(parameterName, operationType));
            }
            sql.Append(')');
        }

        sql.Append(" ORDER BY operation_id");
        return ReadRows(server, sql.ToString(), parameters, "SsisOperation");
    }

    private PSObject[] ReadMessages(Server server, long executionId)
    {
        StringBuilder sql = new();
        sql.Append("SELECT operation_message_id AS OperationMessageId, operation_id AS OperationId, message_time AS MessageTime,");
        sql.Append(" message_type AS MessageType, message_source_type AS MessageSourceType, message AS Message,");
        sql.Append(" extended_info_id AS ExtendedInfoId");
        sql.Append(" FROM [SSISDB].[catalog].[operation_messages] WHERE operation_id = @operationId ORDER BY operation_message_id");

        List<KeyValuePair<string, object>> parameters = new()
        {
            new KeyValuePair<string, object>("operationId", executionId),
        };
        return ReadRows(server, sql.ToString(), parameters, "SsisOperationMessage");
    }

    private PSObject[] ReadRows(Server server, string sql, List<KeyValuePair<string, object>> parameters, string typeName)
    {
        List<PSObject> rows = new();
        using SqlCommand command = new(sql, server.ConnectionContext.SqlConnectionObject);
        foreach (KeyValuePair<string, object> parameter in parameters)
        {
            command.Parameters.AddWithValue(parameter.Key, parameter.Value);
        }
        SetActiveCommand(command);
        try
        {
            using SqlDataReader reader = command.ExecuteReader();
            while (reader.Read())
            {
                PSObject row = new();
                OutputHelper.AddInstanceProperties(row, server);
                for (int ordinal = 0; ordinal < reader.FieldCount; ordinal++)
                {
                    string name = reader.GetName(ordinal);
                    object raw = reader.GetValue(ordinal);
                    object? value = name is "StartTime" or "EndTime" or "CreatedTime" or "MessageTime" ? ToDbaDateTime(raw) : ValueOrNull(raw);
                    row.Properties.Add(new PSNoteProperty(name, value));
                }
                OutputHelper.InsertTypeName(row, typeName);
                rows.Add(row);
            }
        }
        finally
        {
            SetActiveCommand(null);
        }
        return rows.ToArray();
    }

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

    private string BuildValuePredicate(string[]? values, string parameterPrefix, string columnExpression)
    {
        if (!FilterHelper.IsActive(values))
        {
            return string.Empty;
        }
        StringBuilder predicate = new();
        predicate.Append("\n\t\tAND ( 1=0 ");
        int ordinal = 0;
        foreach (string value in values!)
        {
            ordinal++;
            string parameterName = parameterPrefix + ordinal.ToString(CultureInfo.InvariantCulture);
            predicate.Append("\n\t\t\tOR " + columnExpression + " = @" + parameterName);
            _queryParameters.Add(new KeyValuePair<string, object>(parameterName, value));
        }
        predicate.Append("\n\t\t)");
        return predicate.ToString();
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
