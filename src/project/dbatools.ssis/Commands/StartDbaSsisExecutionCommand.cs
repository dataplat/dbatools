#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// <para type="synopsis">Starts a package in the SSIS catalog.</para>
/// <para type="description">Runs a package that has been deployed to the SSIS catalog (SSISDB), optionally against an environment and with execution parameters, and returns the execution decorated exactly like Get-DbaSsisExecution emits it.</para>
/// <para type="description">Calls catalog.create_execution, then catalog.set_execution_parameter_value once per supplied parameter, then catalog.start_execution - with parameterized T-SQL rather than the Integration Services object model, so it works on both PowerShell editions and on Linux. The execution id the first proc hands back is the only thing that identifies the run: the parameter calls need it, the start needs it, and the caller needs it to poll the run or to stop it later.</para>
/// <para type="description">Without -Synchronous the command returns as soon as the run has been started, so the status is normally Pending or Running. With it, the command polls the catalog until the run reaches a terminal state and a package that ends Failed, Cancelled or Halted is reported as a failure rather than as a success that happens to carry a bad status.</para>
/// <para type="description">-Package is the package name as the catalog stores it, which includes the .dtsx extension.</para>
/// </summary>
/// <example>
///   <code>PS C:\&gt; Start-DbaSsisExecution -SqlInstance sql2019 -Folder Finance -Project Ledger -Package Load.dtsx</code>
///   <para>Starts Load.dtsx and returns the execution without waiting for it.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Start-DbaSsisExecution -SqlInstance sql2019 -Folder Finance -Project Ledger -Package Load.dtsx -Environment Production -Synchronous -Timeout 600</code>
///   <para>Runs the package against the Production environment and waits up to ten minutes for it to finish. On expiry the command stops waiting and says so; it does not stop the execution.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Start-DbaSsisExecution -SqlInstance sql2019 -Folder Finance -Project Ledger -Package Load.dtsx -Parameter @{ BatchSize = 500 } -ProjectParameter @{ Region = "EU" } -LoggingLevel 3</code>
///   <para>Sets a package parameter, a project parameter and the logging level for this run only. The two hashtables are separate because the catalog discriminates the scopes and a name can exist in both.</para>
/// </example>
[Cmdlet(VerbsLifecycle.Start, "DbaSsisExecution", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(PSObject))]
public sealed partial class StartDbaSsisExecutionCommand : DbaInstanceCmdlet
{
    // set_execution_parameter_value discriminates the scope on one smallint, so the two hashtables
    // and the logging level are the caller's way of saying which one a name belongs to. Guessing
    // by looking the name up in catalog.object_parameters would break on a project parameter and a
    // package parameter that share a name.
    private const short ProjectParameterScope = 20;
    private const short PackageParameterScope = 30;
    private const short SystemParameterScope = 50;

    private const int PollIntervalSeconds = 3;

    // catalog.executions.status; the rest (Created, Running, Pending, Stopping) mean still going.
    private static bool IsTerminalStatus(int status)
    {
        return status is 3 or 4 or 6 or 7 or 9;
    }

    private static bool IsFailedStatus(int status)
    {
        return status is 3 or 4 or 6;
    }

    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The SSIS catalog folder the project is deployed to.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    public string Folder { get; set; } = null!;

    /// <summary>The deployed project the package belongs to.</summary>
    [Parameter(Mandatory = true, Position = 3)]
    public string Project { get; set; } = null!;

    /// <summary>The package to run, named as the catalog stores it - including the .dtsx extension.</summary>
    [Parameter(Mandatory = true, Position = 4)]
    public string Package { get; set; } = null!;

    /// <summary>The environment to run against. The project must already reference it; references are what the catalog binds an execution to, not environments directly.</summary>
    [Parameter(Position = 5)]
    public string? Environment { get; set; }

    /// <summary>The folder the environment lives in, when it is not the project's own folder. Omit it and -Environment is looked for beside the project, so a reference to a same-named environment elsewhere is not picked up by accident. Requires -Environment.</summary>
    [Parameter(Position = 6)]
    public string? EnvironmentFolder { get; set; }

    /// <summary>Package-scoped parameter values for this run, as a name/value hashtable.</summary>
    [Parameter(Position = 7)]
    public Hashtable? Parameter { get; set; }

    /// <summary>Project-scoped parameter values for this run, as a name/value hashtable.</summary>
    [Parameter(Position = 8)]
    public Hashtable? ProjectParameter { get; set; }

    /// <summary>The LOGGING_LEVEL system parameter for this run: 0 None, 1 Basic, 2 Performance, 3 Verbose.</summary>
    [Parameter(Position = 9)]
    public int LoggingLevel { get; set; }

    /// <summary>How many seconds to wait with -Synchronous before giving up on the wait. On expiry the command stops waiting; the execution keeps running.</summary>
    [Parameter(Position = 10)]
    public int Timeout { get; set; }

    /// <summary>Waits for the run to reach a terminal state and reports a failed package as a failure.</summary>
    [Parameter]
    public SwitchParameter Synchronous { get; set; }

    /// <summary>Runs the package in the 32-bit runtime.</summary>
    [Parameter]
    public SwitchParameter Use32BitRuntime { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void BeginProcessing()
    {
        // A timeout on a call that never waits is not a harmless no-op: the caller asked for a
        // bound on something this shape of call does not do, so saying nothing would leave them
        // believing the run was waited for and cut short.
        if (TestBound(nameof(Timeout)) && !Synchronous.ToBool())
        {
            StopFunction("-Timeout applies only with -Synchronous: without it the command returns as soon as the run has started and never waits", category: ErrorCategory.InvalidArgument);
            return;
        }

        // Zero or negative reads as "do not wait", but the wait it would produce is one poll of a
        // package that has had no time to finish - so every run would report a timeout it never
        // really had. There is no non-waiting -Synchronous; -Timeout 0 is a caller mistake.
        if (TestBound(nameof(Timeout)) && Timeout <= 0)
        {
            StopFunction($"-Timeout must be greater than zero seconds, not {Timeout}: omit it to wait for the run without a bound", category: ErrorCategory.InvalidArgument);
            return;
        }

        // -EnvironmentFolder only ever disambiguates -Environment. On its own it looks like the
        // run was bound to an environment, and the package would quietly run on its design-time
        // values instead - the failure mode is a successful execution with the wrong settings,
        // which nothing downstream reports.
        if (TestBound(nameof(EnvironmentFolder)) && !TestBound(nameof(Environment)))
        {
            StopFunction("-EnvironmentFolder names the folder to look for -Environment in and does nothing on its own: add -Environment, or drop -EnvironmentFolder to run on the package's design-time values", category: ErrorCategory.InvalidArgument);
        }
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

                long? referenceId = null;
                if (TestBound(nameof(Environment)))
                {
                    referenceId = ReadReferenceId(server);
                    if (referenceId == null)
                    {
                        // Starting the package anyway would run it with its design-time values and
                        // fail somewhere inside the package, which reads as a package bug rather
                        // than as the missing reference it is.
                        string environmentDescription = TestBound(nameof(EnvironmentFolder)) ? $"{EnvironmentFolder}\\{Environment}" : Environment!;
                        StopFunction($"Project {Project} in folder {Folder} on {instance} has no reference to environment {environmentDescription}; create the reference before running the package against it", target: instance, continueLoop: true);
                        continue;
                    }
                }

                string target = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server);
                if (!ShouldProcess(target, $"Starting SSIS package {Package} from project {Project} in folder {Folder}"))
                {
                    continue;
                }

                long executionId;
                try
                {
                    executionId = CreateExecution(server, referenceId);
                    SetParameterValues(server, executionId);
                    StartExecution(server, executionId);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    StopFunction($"Failure starting SSIS package {Package} from project {Project} in folder {Folder} on {instance}", target: instance, exception: ex, continueLoop: true);
                    continue;
                }

                if (Synchronous.ToBool() && !WaitForCompletion(server, instance, executionId))
                {
                    continue;
                }

                EmitExecution(server, executionId);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StopFunction($"Failure starting SSIS packages on {instance}", target: instance, exception: ex, continueLoop: true);
            }
        }
    }

    /// <summary>
    /// The started execution is re-emitted in Get-DbaSsisExecution's shape and decorated
    /// identically, so Start -&gt; Get pipelines compose and the status names are the same words in
    /// both commands.
    /// </summary>
    private void EmitExecution(Server server, long executionId)
    {
        // worker_agent_id arrived with Scale Out in SQL 2017, and naming it on an older catalog
        // fails the whole SELECT - which would leave the execution started and unreportable. The
        // engine version does not answer whether the column is there: catalog.executions is a view
        // inside SSISDB, so a catalog restored from an older instance keeps the older view on a
        // newer engine. Ask the catalog. The property stays in the output either way, so the shape
        // does not change with the server.
        string workerAgentColumn = CatalogViewHasColumn(server, "executions", "worker_agent_id")
            ? "e.worker_agent_id"
            : "CAST(NULL AS uniqueidentifier)";

        string sql = $@"
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
                    , {workerAgentColumn} AS WorkerAgentId
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

        using SqlCommand command = new(sql, server.ConnectionContext.SqlConnectionObject);
        command.Parameters.AddWithValue("@executionId", executionId);

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
                WriteObject(execution);
            }
        }
        finally
        {
            SetActiveCommand(null);
        }
    }

    private static object? Unwrap(object? value)
    {
        // PowerShell hands hashtable values over wrapped often enough that unwrapping is not
        // optional; SqlClient cannot bind a PSObject to a sql_variant.
        return value is PSObject wrapper ? wrapper.BaseObject : value;
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
