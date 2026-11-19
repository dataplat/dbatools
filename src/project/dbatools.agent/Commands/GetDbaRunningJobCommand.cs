#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Management.Smo.Agent;
using SmoAgentJob = Microsoft.SqlServer.Management.Smo.Agent.Job;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaRunningJob.ps1 at refs/pins/dbatools-2026-10-22. Its nested Get-DbaAgentJob -SqlInstance $server
// -IncludeExecution call runs inline: that command reuses the connected server, runs its execution query, decorates every job
// as it does and leaves the non-Idle ones for this command's Where-Object. Its statement faults are raised from this command.
// Corrections (quality/corrections/Get-DbaRunningJob.json): dropped-job (a piped job deleted since it was read is not reported
// as running) and azure-unsupported (Azure SQL Database has no SQL Server Agent and is refused as Connect-DbaInstance
// -AzureUnsupported does).

/// <summary>
/// Retrieves SQL Server Agent jobs that are currently executing
/// </summary>
/// <para>
/// This function returns SQL Server Agent jobs that are actively running at the moment you call it, filtering out any jobs in idle state.
/// Use this to monitor job execution during maintenance windows, troubleshoot performance issues by identifying resource-consuming jobs, or verify that no jobs are running before performing maintenance operations.
/// The function refreshes job status information to provide real-time execution details rather than cached data.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaRunningJob -SqlInstance sql2017
/// </code>
/// <para>
/// Returns any active jobs on sql2017
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentJob -SqlInstance sql2017, sql2019 | Get-DbaRunningJob
/// </code>
/// <para>
/// Returns all active jobs on multiple instances piped into the function.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $servers | Get-DbaRunningJob
/// </code>
/// <para>
/// Returns all active jobs on multiple instances piped into the function.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Agent, Job
/// Author: Stephen Bennett, sqlnotesfromtheunderground.wordpress.com
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// <item>
/// <term>OUTPUTS</term>
/// <description>
/// <para>
/// Microsoft.SqlServer.Management.Smo.Agent.Job
/// </para>
/// <para>
/// Returns one Job object for each SQL Server Agent job that is currently executing (not in Idle state).
/// When no jobs are running, the command returns nothing.
/// </para>
/// <para>
/// Default display properties (via Get-DbaAgentJob with Select-DefaultView):
/// - ComputerName: The computer name of the SQL Server instance
/// - InstanceName: The SQL Server instance name
/// - SqlInstance: The full SQL Server instance name (computer\instance format)
/// - Name: The name of the Agent job
/// - CurrentRunStatus: Current execution status (Executing, Idle, Suspended, etc.)
/// - IsEnabled: Boolean indicating if the job is enabled
/// - LastRunOutcome: Result of the most recent execution (Succeeded, Failed, Cancelled, etc.)
/// - LastRunDate: DateTime of the most recent job execution
/// - NextRunDate: DateTime scheduled for the next execution
/// - Owner: The login that owns the job
/// - CreateDate: DateTime when the job was created
/// - Description: Text description of the job's purpose
/// </para>
/// <para>
/// Additional properties available from the base SMO Agent.Job object via Select-Object *:
/// - JobID: Unique identifier (GUID) for the job
/// - EventLogLevel: Logging level for event log (Never, OnSuccess, OnFailure, Always)
/// - EmailLevel: Email notification level (Never, OnSuccess, OnFailure, Always)
/// - NetSendLevel: Network send notification level (Never, OnSuccess, OnFailure, Always)
/// - NetsendOperatorName: Name of operator for network send notifications
/// - EmailOperatorName: Name of operator for email notifications
/// - OperatorToNetSend: Operator configured for network send notifications
/// - StartStepID: Step number where execution begins
/// - Category: The category/classification of the job
/// - DeleteLevel: When to delete job history (Never, OnSuccess, OnFailure, Always)
/// - TargetServers: Collection of target servers for multi-server jobs
/// - HasSchedule: Boolean indicating if the job has any schedules assigned
/// </para>
/// <para>
/// All properties from the base SMO Agent.Job object are accessible using Select-Object *.
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaRunningJob" />
[Cmdlet(VerbsCommon.Get, "DbaRunningJob")]
[OutputType(typeof(SmoAgentJob))]
public sealed class GetDbaRunningJobCommand : DbaInstanceCmdlet
{
    // PS (Get-DbaAgentJob): the -IncludeExecution query, verbatim.
    private const string ExecutionQuery = @"SELECT [job].[job_id] AS [JobId], [activity].[start_execution_date] AS [StartDate]
                FROM [msdb].[dbo].[sysjobs_view] AS [job]
                    INNER JOIN [msdb].[dbo].[sysjobactivity] AS [activity] ON [job].[job_id] = [activity].[job_id]
                WHERE [activity].[run_requested_date] IS NOT NULL
                    AND [activity].[start_execution_date] IS NOT NULL
                    AND [activity].[stop_execution_date] IS NULL;";

    /// <para>
    /// The target SQL Server instance or instances
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
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
    /// Accepts SQL Server Agent job objects piped from Get-DbaAgentJob for filtering to only running jobs.
    /// Use this when you need to check execution status on a specific set of jobs rather than all jobs on an instance.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 2)]
    [PsAgentJobArrayCast]
    public SmoAgentJob[]? InputObject { get; set; }

    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
        {
            // PS: try { Connect-DbaInstance } catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            // Correction azure-unsupported: SQL Server Agent is not available in Azure SQL Database, so the connection refuses it
            // as Connect-DbaInstance -AzureUnsupported does.
            Server? server = ConnectInstance(instance, "Failure", azureUnsupported: true);
            if (server is null)
                continue;

            // PS: $server.JobServer.Jobs.Refresh($true). A fault is written and the next statement runs.
            RefreshJobs(server);

            // PS: Get-DbaAgentJob -SqlInstance $server -IncludeExecution | Where-Object CurrentRunStatus -ne 'Idle'
            foreach (SmoAgentJob agentJob in ReadDecoratedJobs(server))
            {
                if (IsNotIdle(agentJob))
                    WriteObject(agentJob);
            }
        }

        foreach (SmoAgentJob? job in InputObject ?? Array.Empty<SmoAgentJob>())
        {
            // PS: $job.Refresh(); $job | Where-Object CurrentRunStatus -ne 'Idle'. A null element: the method call on $null faults
            // and the pipeline of $null gives nothing.
            if (job is null)
            {
                SurfaceFault(NullCallRecord());
                continue;
            }
            SmoAgentJob current = job;
            Statement(() => current.Refresh(), failure => MethodCallRecord("Refresh", 0, failure));
            // Correction dropped-job: a job deleted since it was read refreshes without a fault and is marked dropped; it is not
            // executing, where the pin's Where-Object reads its unreadable status as $null and returns it.
            if (current.State == SqlSmoState.Dropped)
                continue;
            if (IsNotIdle(current))
                WriteObject(current);
        }
    }

    // PS: $server.JobServer.Jobs.Refresh($true), each step's own fault. $null.Jobs is $null, and the Refresh call on it faults.
    private void RefreshJobs(Server server)
    {
        JobServer? jobServer = null;
        if (!Statement(() => jobServer = server.JobServer, failure => PropertyReadRecord("JobServer", failure)))
            return;
        if (jobServer is null)
        {
            SurfaceFault(NullCallRecord());
            return;
        }
        JobServer agent = jobServer;
        JobCollection? jobs = null;
        if (!Statement(() => jobs = agent.Jobs, failure => PropertyReadRecord("Jobs", failure)))
            return;
        if (jobs is null)
        {
            SurfaceFault(NullCallRecord());
            return;
        }
        JobCollection collection = jobs;
        Statement(() => collection.Refresh(true), failure => MethodCallRecord("Refresh", 1, failure));
    }

    /// <summary>
    /// The nested Get-DbaAgentJob -SqlInstance $server -IncludeExecution with its default -Type (every MultiServer and Local
    /// job): the execution query, then each job with its StartDate, instance notes and default view. Every job is read before
    /// the first leaves, as the pin collects $jobs first.
    /// </summary>
    private List<SmoAgentJob> ReadDecoratedJobs(Server server)
    {
        // PS: $jobExecutionResults = $server.Query($query). A fault leaves it unset and the command goes on.
        DataTable? executions = null;
        Statement(() => executions = server.ConnectionContext.ExecuteWithResults(ExecutionQuery).Tables[0], ServerQueryRecord);

        // PS: $jobs = $server.JobServer.Jobs | Where-Object JobType -in $Type. A getter's fault, or the collection's fault when the
        // pipeline enumerates it, leaves $jobs unset; $null as the collection gives no jobs and no fault.
        List<SmoAgentJob> jobs = new();
        JobServer? jobServer = null;
        if (!Statement(() => jobServer = server.JobServer, failure => PropertyReadRecord("JobServer", failure)) || jobServer is null)
            return jobs;
        JobServer agent = jobServer;
        JobCollection? collection = null;
        if (!Statement(() => collection = agent.Jobs, failure => PropertyReadRecord("Jobs", failure)) || collection is null)
            return jobs;
        JobCollection all = collection;
        bool read = Statement(() =>
        {
            foreach (SmoAgentJob agentJob in all)
            {
                string type = agentJob.JobType.ToString();
                if (String.Equals(type, "MultiServer", StringComparison.OrdinalIgnoreCase) || String.Equals(type, "Local", StringComparison.OrdinalIgnoreCase))
                    jobs.Add(agentJob);
            }
        }, EnumerationRecord);
        if (!read)
            return new List<SmoAgentJob>();

        foreach (SmoAgentJob agentJob in jobs)
            Decorate(agentJob, executions);
        return jobs;
    }

    // PS (Get-DbaAgentJob): StartDate when the job is in the execution results, the instance notes, then
    // Select-DefaultView with 'IsEnabled as Enabled' and 'DateCreated as CreateDate'.
    private static void Decorate(SmoAgentJob agentJob, DataTable? executions)
    {
        PSObject wrapped = PSObject.AsPSObject(agentJob);
        List<string> view = new()
        {
            "ComputerName", "InstanceName", "SqlInstance", "Name", "Category", "OwnerLoginName", "CurrentRunStatus",
            "CurrentRunRetryAttempt", "Enabled", "LastRunDate", "LastRunOutcome", "HasSchedule", "OperatorToEmail", "CreateDate"
        };

        DateTime? started = LatestStart(executions, agentJob.JobID);
        if (started is not null)
        {
            wrapped.Properties.Remove("StartDate");
            wrapped.Properties.Add(new PSNoteProperty("StartDate", new DbaDateTime(started.Value)));
            view.Add("StartDate");
        }

        // PS: Add-Member -Force replaces the notes an earlier call left on the same object.
        Server server = agentJob.Parent.Parent;
        foreach (string name in new[] { "ComputerName", "InstanceName", "SqlInstance" })
            wrapped.Properties.Remove(name);
        OutputHelper.AddInstanceProperties(wrapped, server);

        foreach (KeyValuePair<string, string> alias in new[] { new KeyValuePair<string, string>("Enabled", "IsEnabled"), new KeyValuePair<string, string>("CreateDate", "DateCreated") })
        {
            wrapped.Properties.Remove(alias.Key);
            OutputHelper.AddAliasProperty(wrapped, alias.Key, alias.Value);
        }
        OutputHelper.SetDefaultDisplayPropertySet(wrapped, view.ToArray());
    }

    // PS: ($jobExecutionResults | Where-Object JobId -eq $currentJobId | Sort-Object StartDate -Descending | Select-Object -First 1).StartDate
    private static DateTime? LatestStart(DataTable? executions, Guid jobId)
    {
        if (executions is null)
            return null;
        DateTime? latest = null;
        foreach (DataRow row in executions.Rows)
        {
            if (row["JobId"] is Guid rowId && rowId == jobId && row["StartDate"] is DateTime start && (latest is null || start > latest.Value))
                latest = start;
        }
        return latest;
    }

    // PS: Where-Object CurrentRunStatus -ne 'Idle'. Where-Object reads a property whose getter throws as $null, which is not 'Idle'.
    private static bool IsNotIdle(SmoAgentJob job)
    {
        try
        {
            return job.CurrentRunStatus != JobExecutionStatus.Idle;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // The status could not be read; Where-Object keeps the job.
            return true;
        }
    }

    /// <summary>Runs one statement of the pin; a fault is surfaced and false returned.</summary>
    private bool Statement(Action body, Func<Exception, ErrorRecord> record)
    {
        try
        {
            body();
            return true;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            SurfaceFault(record(failure));
            return false;
        }
    }

    // The pin's raw statement fault: written, and the next statement runs; a caller's try receives it and the command ends there.
    private void SurfaceFault(ErrorRecord record)
    {
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop ("keep going unless -EnableException", point 3)
            ThrowTerminatingError(record); // style-ok: cs-raw-streams statement fault outside Stop-Function, as in the source
        }
        StatementFault.Surface(this, record);
    }

    // PS: a .NET method called from the source; its exception is the statement's MethodInvocationException.
    private static ErrorRecord MethodCallRecord(string method, int arguments, Exception failure)
    {
        MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
            "Exception calling \"{0}\" with \"{1}\" argument(s): \"{2}\"", method, arguments, failure.Message), failure);
        return new ErrorRecord(call, failure.GetType().Name, ErrorCategory.NotSpecified, null);
    }

    // PS: a property read from the source; a getter's exception is the statement's GetValueInvocationException.
    private static ErrorRecord PropertyReadRecord(string property, Exception failure)
    {
        GetValueInvocationException read = new(String.Format(CultureInfo.InvariantCulture,
            "Exception getting \"{0}\": \"{1}\"", property, failure.Message), failure);
        return new ErrorRecord(read, "ExceptionWhenGetting", ErrorCategory.NotSpecified, null);
    }

    // PS: a method called on $null.
    private static ErrorRecord NullCallRecord()
    {
        RuntimeException fault = new("You cannot call a method on a null-valued expression.");
        return new ErrorRecord(fault, "InvokeMethodOnNull", ErrorCategory.InvalidOperation, null);
    }

    /// <summary>
    /// PS: $server.Query($query), the dbatools Server.Query script method: its catch joins the messages of the ExecuteWithResults
    /// failure's exception chain and throws that text, which the method binder reports as 'Exception calling "Query"'.
    /// </summary>
    private static ErrorRecord ServerQueryRecord(Exception failure)
    {
        List<string> messages = new();
        for (Exception? current = failure; current is not null; current = current.InnerException)
            messages.Add(current.Message);
        string joined = String.Concat(messages);
        // The script method's 'throw $message' and the engine's wrap of it: two RuntimeExceptions of that text, nothing beneath
        // (probe pin-contract-r4, both editions).
        RuntimeException thrown = new(joined, new RuntimeException(joined));
        MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
            "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", joined), thrown);
        return new ErrorRecord(call, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
    }

    // PS: a pipeline enumerating a collection whose enumerator throws.
    private static ErrorRecord EnumerationRecord(Exception failure)
    {
        ExtendedTypeSystemException enumeration = new(String.Format(CultureInfo.InvariantCulture,
            "The following exception occurred while trying to enumerate the collection: \"{0}\".", failure.Message), failure);
        return new ErrorRecord(enumeration, "ExceptionInGetEnumerator", ErrorCategory.NotSpecified, null);
    }
}
