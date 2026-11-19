#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Management.Smo.Agent;
using AgentJob = Microsoft.SqlServer.Management.Smo.Agent.Job;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaAgentJob.ps1: the connect, the -IncludeExecution query, the blank -Job and -ExcludeJob checks,
// every filter and the output run here in C#, in the pinned order. Name, type and category filters compare as -in and
// -notin do (AgentNameFilter.ContainsName); the -Database lookup is the pinned case-insensitive hashtable. Correction: azure-unsupported.
/// <summary>Retrieves SQL Server Agent job details and execution status from one or more instances.</summary>
/// <para>
/// Retrieves detailed information about SQL Server Agent jobs including their configuration, status, schedules, and execution history. This function connects to SQL instances and queries the msdb database to return job properties like owner, category, last run outcome, and current execution status. Use this to monitor job health across your environment, audit job configurations before deployments, or identify jobs associated with specific databases for maintenance planning.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentJob -SqlInstance localhost
/// </code>
/// <para>
/// Returns all SQL Agent Jobs on the local default SQL Server instance
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentJob -SqlInstance localhost, sql2016
/// </code>
/// <para>
/// Returns all SQl Agent Jobs for the local and sql2016 SQL Server instances
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentJob -SqlInstance localhost -Job BackupData, BackupDiff
/// </code>
/// <para>
/// Returns all SQL Agent Jobs named BackupData and BackupDiff from the local SQL Server instance.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentJob -SqlInstance localhost -ExcludeJob BackupDiff
/// </code>
/// <para>
/// Returns all SQl Agent Jobs for the local SQL Server instances, except the BackupDiff Job.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentJob -SqlInstance localhost -ExcludeDisabledJobs
/// </code>
/// <para>
/// Returns all SQl Agent Jobs for the local SQL Server instances, excluding the disabled jobs.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $servers | Get-DbaAgentJob | Out-GridView -PassThru | Start-DbaAgentJob -WhatIf
/// </code>
/// <para>
/// Find all of your Jobs from SQL Server instances in the $servers collection, select the jobs you want to start then see jobs would start if you ran Start-DbaAgentJob
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentJob -SqlInstance sqlserver2014a | Where-Object Category -eq "Report Server" | Export-DbaScript -Path "C:\temp\sqlserver2014a_SSRSJobs.sql"
/// </code>
/// <para>
/// Exports all SSRS jobs from SQL instance sqlserver2014a to a file.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentJob -SqlInstance sqlserver2014a -Database msdb
/// </code>
/// <para>
/// Finds all jobs on sqlserver2014a that T-SQL job steps associated with msdb database
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Agent, Job
/// Author: Garry Bargsley (@gbargsley), blog.garrybargsley.com
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaAgentJob" />
[Cmdlet(VerbsCommon.Get, "DbaAgentJob")]
[OutputType(typeof(AgentJob))]
public sealed class GetDbaAgentJobCommand : DbaInstanceCmdlet
{
    /// <para>
    /// The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.
    /// </para>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <para>
    /// Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
    /// </para>
    /// <para>
    /// Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
    /// </para>
    /// <para>
    /// For MFA support, please use Connect-DbaInstance.
    /// </para>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <para>
    /// Specifies specific SQL Agent job names to retrieve. Accepts an array of job names for targeting multiple jobs.
    /// Use this when you need to check status or configuration of specific jobs instead of retrieving all jobs on the instance.
    /// </para>
    [Parameter(Position = 2)]
    public string[]? Job { get; set; }

    /// <para>
    /// Excludes specific SQL Agent job names from the results. Accepts an array of job names to skip.
    /// Useful when you want most jobs except for specific ones like test jobs or jobs you're not responsible for managing.
    /// </para>
    [Parameter(Position = 3)]
    public string[]? ExcludeJob { get; set; }

    /// <para>
    /// Filters jobs to only those containing T-SQL job steps that target specific databases.
    /// Essential for database-specific maintenance planning or identifying which jobs will be affected by database operations like restores or migrations.
    /// </para>
    [Parameter(Position = 4)]
    public string[]? Database { get; set; }

    /// <para>
    /// Filters jobs by their assigned category such as 'Database Maintenance', 'Report Server', or custom categories.
    /// Helpful for organizing job management tasks by functional area or finding jobs related to specific SQL Server features.
    /// </para>
    [Parameter(Position = 5)]
    public string[]? Category { get; set; }

    /// <para>
    /// Excludes jobs from specific categories from the results. Accepts an array of category names.
    /// Use this to filter out jobs you don't manage, such as third-party application jobs or SSRS jobs when focusing on database maintenance.
    /// </para>
    [Parameter(Position = 6)]
    public string[]? ExcludeCategory { get; set; }

    /// <para>
    /// Excludes disabled SQL Agent jobs from the results, showing only enabled jobs.
    /// Use this when focusing on active job monitoring or troubleshooting since disabled jobs won't execute.
    /// </para>
    [Parameter]
    public SwitchParameter ExcludeDisabledJobs { get; set; }

    /// <para>
    /// Adds execution start date information for currently running jobs to the output.
    /// Essential for troubleshooting long-running jobs or monitoring active job execution in real-time.
    /// </para>
    [Parameter]
    public SwitchParameter IncludeExecution { get; set; }

    /// <para>
    /// Specifies whether to return Local jobs, MultiServer jobs, or both. Local jobs run only on the current instance while MultiServer jobs are managed centrally.
    /// Use 'Local' when managing single-instance environments or 'MultiServer' when working with SQL Server multi-server administration setups.
    /// </para>
    [Parameter(Position = 7)]
    [ValidateSet("MultiServer", "Local")]
    public string[] Type { get; set; } = new[] { "MultiServer", "Local" };

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    private const string ExecutionQuery = @"SELECT [job].[job_id] AS [JobId], [activity].[start_execution_date] AS [StartDate]
                FROM [msdb].[dbo].[sysjobs_view] AS [job]
                    INNER JOIN [msdb].[dbo].[sysjobactivity] AS [activity] ON [job].[job_id] = [activity].[job_id]
                WHERE [activity].[run_requested_date] IS NOT NULL
                    AND [activity].[start_execution_date] IS NOT NULL
                    AND [activity].[stop_execution_date] IS NULL;";

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { Connect-DbaInstance } catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            // Correction azure-unsupported: Azure SQL Database has no SQL Server Agent or msdb jobs, so it is refused as
            // Connect-DbaInstance -AzureUnsupported does.
            Server? server = ConnectInstance(instance, "Failure", azureUnsupported: true);
            if (server is null)
            {
                continue;
            }

            // PS: if (Test-Bound 'IncludeExecution') { $jobExecutionResults = $server.Query($query) } (also for -IncludeExecution:$false)
            DataTable? jobExecutionResults = null;
            if (TestBound(nameof(IncludeExecution)))
            {
                jobExecutionResults = QueryExecution(server);
            }

            // Check if Job parameter is bound with null, empty, or whitespace-only values
            string[]? jobFilter = Job;
            if (TestBound(nameof(Job)))
            {
                // Filter out any null/empty/whitespace values
                jobFilter = FilterBlank(Job);

                // If all values were null/empty/whitespace, skip processing
                if (jobFilter.Length == 0)
                {
                    WriteMessage(MessageLevel.Verbose, "The -Job parameter was explicitly provided but contains only null, empty, or whitespace values. No jobs will be returned.");
                    continue;
                }
            }

            // Check if ExcludeJob parameter is bound with null, empty, or whitespace-only values
            string[]? excludeJobFilter = ExcludeJob;
            if (TestBound(nameof(ExcludeJob)))
            {
                // Filter out any null/empty/whitespace values
                excludeJobFilter = FilterBlank(ExcludeJob);

                // If all values were null/empty/whitespace, ignore the parameter
                if (excludeJobFilter.Length == 0)
                {
                    WriteMessage(MessageLevel.Verbose, "The -ExcludeJob parameter was explicitly provided but contains only null, empty, or whitespace values. Parameter will be ignored.");
                    excludeJobFilter = null;
                }
            }

            // PS: $jobs = $server.JobServer.Jobs | Where-Object JobType -in $Type, then each filter in the pinned order
            Hashtable? dbLookup = FilterHelper.IsActive(Database) ? DatabaseLookup(Database!) : null;
            foreach (AgentJob agentJob in ReadJobs(server))
            {
                if (!AgentNameFilter.ContainsName(Type, agentJob.JobType.ToString()))
                {
                    continue;
                }
                if (jobFilter is { Length: > 0 } && !AgentNameFilter.ContainsName(jobFilter, agentJob.Name))
                {
                    continue;
                }
                if (excludeJobFilter is { Length: > 0 } && AgentNameFilter.ContainsName(excludeJobFilter, agentJob.Name))
                {
                    continue;
                }
                if (ExcludeDisabledJobs.ToBool() && !agentJob.IsEnabled)
                {
                    continue;
                }
                if (dbLookup is not null && !HasStepInDatabase(agentJob, dbLookup))
                {
                    continue;
                }
                if (FilterHelper.IsActive(Category) && !InCategory(Category!, agentJob.Category))
                {
                    continue;
                }
                if (FilterHelper.IsActive(ExcludeCategory) && InCategory(ExcludeCategory!, agentJob.Category))
                {
                    continue;
                }

                WriteObject(Decorate(server, agentJob, jobExecutionResults));
            }
        }
    }

    /// <summary>PS: $server.Query($query), the dbatools Server.Query script method: ConnectionContext.ExecuteWithResults, first table.</summary>
    private DataTable? QueryExecution(Server server)
    {
        DataSet resultSet;
        try
        {
            resultSet = server.ConnectionContext.ExecuteWithResults(ExecutionQuery);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // caller-try: terminate -- continuing would emit this instance's jobs without StartDate, or with the previous instance's results
            ThrowTerminatingError(QueryFaultRecord(failure)); // style-ok: cs-raw-streams statement fault outside Stop-Function, as in the source
            return null;
        }
        return resultSet.Tables.Count > 0 ? resultSet.Tables[0] : null;
    }

    /// <summary>PS: $server.JobServer.Jobs enumerated by the pipeline into $jobs.</summary>
    private List<AgentJob> ReadJobs(Server server)
    {
        string property = "JobServer";
        JobCollection collection;
        try
        {
            JobServer jobServer = server.JobServer;
            property = "Jobs";
            collection = jobServer.Jobs;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // caller-try: terminate -- continuing would filter and emit the previous instance's $jobs under this instance
            ThrowTerminatingError(GetterFaultRecord(property, failure)); // style-ok: cs-raw-streams statement fault outside Stop-Function, as in the source
            return new List<AgentJob>();
        }

        List<AgentJob> jobs = new();
        IEnumerator? enumerator = null;
        try
        {
            enumerator = LanguagePrimitives.GetEnumerator(collection);
            while (enumerator is not null && enumerator.MoveNext())
            {
                if (enumerator.Current is AgentJob agentJob)
                {
                    jobs.Add(agentJob);
                }
            }
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // caller-try: terminate -- continuing would filter and emit the previous instance's $jobs under this instance
            ThrowTerminatingError(EnumerationFaultRecord(failure, enumerator)); // style-ok: cs-raw-streams pipeline statement fault outside Stop-Function, as in the source
        }
        return jobs;
    }

    /// <summary>The job wrapped as the pinned Add-Member and Select-DefaultView calls leave it.</summary>
    private static PSObject Decorate(Server server, AgentJob agentJob, DataTable? jobExecutionResults)
    {
        List<string> defaults = new()
        {
            "ComputerName", "InstanceName", "SqlInstance", "Name", "Category", "OwnerLoginName",
            "CurrentRunStatus", "CurrentRunRetryAttempt", "Enabled", "LastRunDate", "LastRunOutcome",
            "HasSchedule", "OperatorToEmail", "CreateDate"
        };

        PSObject wrapped = PSObject.AsPSObject(agentJob);

        // PS: if ($currentJobId -in $jobExecutionResults.JobId) { [DbaDateTime] of the latest StartDate }
        DateTime? startDate = FindLatestStartDate(jobExecutionResults, agentJob.JobID);
        if (startDate is not null)
        {
            ReplaceNoteProperty(wrapped, "StartDate", new DbaDateTime(startDate.Value));
            defaults.Add("StartDate");
        }

        ReplaceNoteProperty(wrapped, "ComputerName", SmoServerExtensions.GetComputerName(server));
        ReplaceNoteProperty(wrapped, "InstanceName", server.ServiceName);
        ReplaceNoteProperty(wrapped, "SqlInstance", SmoServerExtensions.GetDomainInstanceName(server));

        // PS: Select-DefaultView -Property ... 'IsEnabled as Enabled' ... 'DateCreated as CreateDate'
        AddAliasIfMissing(wrapped, "Enabled", "IsEnabled");
        AddAliasIfMissing(wrapped, "CreateDate", "DateCreated");
        OutputHelper.SetDefaultDisplayPropertySet(wrapped, defaults.ToArray());
        return wrapped;
    }

    private static string[] FilterBlank(string[]? values)
    {
        List<string> kept = new();
        foreach (string value in values ?? Array.Empty<string>())
        {
            if (!string.IsNullOrWhiteSpace(value))
            {
                kept.Add(value);
            }
        }
        return kept.ToArray();
    }

    // PS: Where-Object Category -in $Category; a missing category matches no name.
    private static bool InCategory(string[] categories, string? category)
    {
        return category is not null && AgentNameFilter.ContainsName(categories, category);
    }

    // PS: $dbLookup = @{}; foreach ($db in $Database) { $dbLookup[$db] = $true }, a case-insensitive hashtable.
    // A null name fails that one assignment in the pin and is left out here; no step has a null name to match it.
    // Correction culture-database-match: OrdinalIgnoreCase on both editions, as PowerShell 7's @{} compares, so
    // TEMPDB/tempdb style matches hold under every culture (Turkish I included).
    private static Hashtable DatabaseLookup(string[] databases)
    {
        Hashtable lookup = new(StringComparer.OrdinalIgnoreCase);
        foreach (string? db in databases)
        {
            if (db is not null)
            {
                lookup[db] = true;
            }
        }
        return lookup;
    }

    // PS: foreach ($step in $_.JobSteps) { if ($dbLookup.ContainsKey($step.DatabaseName)) { return $true } }
    // A step without a database name matches no key.
    private static bool HasStepInDatabase(AgentJob agentJob, Hashtable dbLookup)
    {
        foreach (JobStep step in agentJob.JobSteps)
        {
            string? databaseName = step.DatabaseName;
            if (databaseName is not null && dbLookup.ContainsKey(databaseName))
            {
                return true;
            }
        }
        return false;
    }

    private static DateTime? FindLatestStartDate(DataTable? jobExecutionResults, Guid jobId)
    {
        if (jobExecutionResults is null)
        {
            return null;
        }
        DateTime? latest = null;
        foreach (DataRow row in jobExecutionResults.Rows)
        {
            if (row["JobId"] is Guid rowJobId && rowJobId == jobId && row["StartDate"] is DateTime rowStart)
            {
                if (latest is null || rowStart > latest.Value)
                {
                    latest = rowStart;
                }
            }
        }
        return latest;
    }

    /// <summary>
    /// The record a failed Server.Query call raises: its catch concatenates the messages of the failure's exception chain
    /// without separators and throws that string, which the method binder reports as the ScriptMethodRuntimeException of
    /// 'Exception calling "Query" with "1" argument(s)'.
    /// </summary>
    private static ErrorRecord QueryFaultRecord(Exception failure)
    {
        string message = String.Empty;
        Exception current = failure;
        while (current.InnerException != null)
        {
            message += current.Message;
            current = current.InnerException;
        }
        message += current.Message;
        MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
            "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", message), new RuntimeException(message, failure));
        return new ErrorRecord(call, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
    }

    // The record the member binder gives a failing property getter ($server.JobServer or .Jobs): ExceptionWhenGetting.
    private static ErrorRecord GetterFaultRecord(string property, Exception failure)
    {
        GetValueInvocationException fault = new(String.Format(CultureInfo.InvariantCulture,
            "Exception getting \"{0}\": \"{1}\"", property, failure.Message), failure);
        return new ErrorRecord(fault, "ExceptionWhenGetting", ErrorCategory.NotSpecified, null);
    }

    // The engine's record when the failure carries one (ExceptionInGetEnumerator); otherwise the record a failing
    // MoveNext gives (BadEnumeration, InvalidOperation, the enumerator as target).
    private static ErrorRecord EnumerationFaultRecord(Exception failure, IEnumerator? enumerator)
    {
        if (failure is IContainsErrorRecord container && container.ErrorRecord is not null)
            return new ErrorRecord(container.ErrorRecord, failure);
        RuntimeException fault = new(String.Format(CultureInfo.InvariantCulture,
            "An error occurred while enumerating through a collection: {0}.", failure.Message), failure);
        return new ErrorRecord(fault, "BadEnumeration", ErrorCategory.InvalidOperation, enumerator);
    }

    private static void AddAliasIfMissing(PSObject wrapped, string aliasName, string referencedName)
    {
        if (wrapped.Properties[aliasName] is null)
        {
            OutputHelper.AddAliasProperty(wrapped, aliasName, referencedName);
        }
    }

    private static void ReplaceNoteProperty(PSObject wrapped, string name, object? value)
    {
        PSPropertyInfo? existing = wrapped.Properties[name];
        if (existing is PSNoteProperty)
        {
            wrapped.Properties.Remove(name);
        }
        wrapped.Properties.Add(new PSNoteProperty(name, value));
    }
}
