#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Linq;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Management.Smo.Agent;
using SmoAgentJob = Microsoft.SqlServer.Management.Smo.Agent.Job;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Migrates SQL Server Agent jobs between instances with dependency validation
/// </summary>
/// <para>
/// Copies SQL Server Agent jobs from one instance to another while automatically validating all dependencies including databases, logins, proxy accounts, and operators. This eliminates the manual process of checking prerequisites before moving jobs during migrations, disaster recovery, or environment promotions.
/// </para>
/// <para>
/// The function intelligently skips jobs associated with maintenance plans and provides detailed validation messages for any missing dependencies. By default, existing jobs are preserved unless -Force is specified to overwrite them.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Copy-DbaAgentJob -Source sqlserver2014a -Destination sqlcluster
/// </code>
/// <para>
/// Copies all jobs from sqlserver2014a to sqlcluster, using Windows credentials. If jobs with the same name exist on sqlcluster, they will be skipped.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Copy-DbaAgentJob -Source sqlserver2014a -Destination sqlcluster -Job PSJob -SourceSqlCredential $cred -Force
/// </code>
/// <para>
/// Copies a single job, the PSJob job from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If a job with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Copy-DbaAgentJob -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force
/// </code>
/// <para>
/// Shows what would happen if the command were executed using force.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentJob -SqlInstance sqlserver2014a | Where-Object Category -eq "Report Server" | Copy-DbaAgentJob -Destination sqlserver2014b
/// </code>
/// <para>
/// Copies all SSRS jobs (subscriptions) from AlwaysOn Primary SQL instance sqlserver2014a to AlwaysOn Secondary SQL instance sqlserver2014b
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Copy-DbaAgentJob -Source sqlserver2014a -Destination sqlserver2014b -UseLastModified
/// </code>
/// <para>
/// Copies jobs from sqlserver2014a to sqlserver2014b, creating jobs that don't exist and recreating only those whose definition differs and where the source is not older. Jobs with an identical definition are skipped even when their date_modified values differ. A job that differs only in its enabled state has the flag updated in place.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Copy-DbaAgentJob -Source sqlserver2014a -Destination sqlserver2014a -Job "OriginalJob" -NewName "JobCopy"
/// </code>
/// <para>
/// Copies the job "OriginalJob" on sqlserver2014a to the same server as "JobCopy". When source and destination are the same instance, -NewName is required.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Migration, Agent, Job
/// Author: Chrissy LeMaire (@cl), netnerds.net
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Copy-DbaAgentJob" />
[Cmdlet(VerbsCommon.Copy, "DbaAgentJob", DefaultParameterSetName = "Default",
    SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaAgentJobCommand : DbaBaseCmdlet
{
    /// <para>
    /// Source SQL Server instance containing the jobs to copy. You must have sysadmin access and server version must be SQL Server version 2000 or higher.
    /// Use this when copying jobs from a specific instance rather than piping job objects with InputObject.
    /// </para>
    [Parameter(Position = 0)]
    public DbaInstanceParameter? Source { get; set; }

    /// <para>
    /// Alternative credentials for connecting to the source SQL Server instance. Accepts PowerShell credentials (Get-Credential).
    /// Use this when the source server requires different authentication than your current Windows session, such as SQL authentication or cross-domain scenarios.
    /// Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
    /// </para>
    [Parameter(Position = 1)]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <para>
    /// Destination SQL Server instance(s) where jobs will be created. You must have sysadmin access and the server must be SQL Server 2000 or higher.
    /// Supports multiple destinations to copy jobs to multiple servers simultaneously during migrations or DR setup.
    /// </para>
    [Parameter(Mandatory = true, Position = 2)]
    public DbaInstanceParameter[] Destination { get; set; } = null!;

    /// <para>
    /// Alternative credentials for connecting to the destination SQL Server instance. Accepts PowerShell credentials (Get-Credential).
    /// Use this when the destination server requires different authentication than your current Windows session, such as SQL authentication or cross-domain scenarios.
    /// Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
    /// </para>
    [Parameter(Position = 3)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <para>
    /// Specifies which SQL Agent jobs to copy by name. Accepts wildcards and multiple job names.
    /// Use this to copy specific jobs instead of all jobs, such as during selective migrations or when testing job deployments.
    /// If unspecified, all jobs will be processed.
    /// </para>
    [Parameter(Position = 4)]
    public object[]? Job { get; set; }

    /// <para>
    /// Specifies which SQL Agent jobs to skip during the copy operation. Accepts wildcards and multiple job names.
    /// Use this to exclude specific jobs from bulk operations, such as skipping environment-specific jobs or maintenance tasks that shouldn't be migrated.
    /// </para>
    [Parameter(Position = 5)]
    public object[]? ExcludeJob { get; set; }

    /// <para>
    /// Disables the job on the source server after successfully copying it to the destination.
    /// Use this during server migrations or failover scenarios where you want to prevent the job from running on the old server while it runs on the new one.
    /// With -UseLastModified it also applies when the job was found identical on the destination or only its enabled state was aligned;
    /// it does not apply when the job was skipped because the destination copy is newer.
    /// </para>
    [Parameter]
    public SwitchParameter DisableOnSource { get; set; }

    /// <para>
    /// Creates the job on the destination server but leaves it disabled.
    /// Use this when deploying jobs to test environments or when you need to review and modify job steps before enabling them in the new environment.
    /// </para>
    [Parameter]
    public SwitchParameter DisableOnDestination { get; set; }

    /// <para>
    /// Overwrites existing jobs on the destination server and automatically sets missing job owners to the 'sa' login.
    /// Use this when you need to replace existing jobs or when source job owners don't exist on the destination server during migrations.
    /// </para>
    [Parameter]
    public SwitchParameter Force { get; set; }

    /// <para>
    /// The new name for the job on the destination server.
    /// Required when source and destination are the same server instance. Use this to create a copy of a job under a different name on the same or a different server.
    /// Cannot be used when copying multiple jobs simultaneously.
    /// </para>
    [Parameter(Position = 6)]
    public string? NewName { get; set; }

    /// <para>
    /// Compares the job definition on source and destination - job properties, enabled state, steps and schedules - and only copies when they actually differ.
    /// When the definitions differ, the direction is decided by each job's effective last-modified time: the later of msdb.dbo.sysjobs.date_modified and
    /// the date_modified of every schedule attached to the job (sp_update_schedule only touches sysschedules, not the job row). On SQL Server 2000,
    /// which has no sysschedules, only the job row is used. Both values are normalised to UTC using each server's current time zone offset so
    /// instances in different time zones compare correctly; across a daylight-saving change the value for a job modified before the switch can be
    /// off by one hour, which only matters when source and destination are in different time zones.
    /// - Job doesn't exist on destination: creates it
    /// - Definitions identical: skips, regardless of timestamps
    /// - Only the enabled state differs and source is not older: updates the flag in place without recreating the job
    /// - Definitions differ and source is newer (or equal): drops and recreates the job
    /// - Definitions differ and destination is newer: skips with a warning
    /// Job IDs, timestamps, version numbers, schedule IDs/UIDs and run history are excluded from the comparison, so jobs that are
    /// identical but were created independently (for example on AG replicas) are not needlessly recreated.
    /// Use this for incremental synchronization scenarios where you want to keep jobs up-to-date without unconditionally overwriting them.
    /// </para>
    [Parameter]
    public SwitchParameter UseLastModified { get; set; }

    /// <para>
    /// Accepts SQL Agent job objects from the pipeline, typically from Get-DbaAgentJob.
    /// Use this to copy pre-filtered jobs or when combining with other job management cmdlets for complex workflows.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 7)]
    public SmoAgentJob[]? InputObject { get; set; }

    private SmoAgentJob[] _beginJobs = Array.Empty<SmoAgentJob>();
    private string[] _sourceJobNames = Array.Empty<string>();
    private bool _inputBound;
    private readonly HashSet<string> _refreshed = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

    protected override void BeginProcessing()
    {
        _inputBound = TestBound(nameof(InputObject));
        _beginJobs = InputObject ?? Array.Empty<SmoAgentJob>();
        if (Source is not null)
        {
            Server? source = Connect(Source, SourceSqlCredential, false,
                string.Format("Error occurred while establishing connection to {0}", Source));
            if (source is null)
            {
                _beginJobs = Array.Empty<SmoAgentJob>();
                return;
            }
            SmoAgentJob[] jobs = source.JobServer.Jobs.Cast<SmoAgentJob>()
                .Where(value => value.JobType == JobType.Local || value.JobType == JobType.MultiServer).ToArray();
            _sourceJobNames = jobs.Select(value => value.Name).ToArray();
            WildcardNameMatcher include = Matcher(Job, _sourceJobNames);
            WildcardNameMatcher exclude = Matcher(ExcludeJob, _sourceJobNames);
            _beginJobs = jobs.Where(value =>
                (!TestBound(nameof(Job)) || include.Matches(value.Name)) &&
                (!TestBound(nameof(ExcludeJob)) || !exclude.Matches(value.Name))).ToArray();
        }
        if (TestBound(nameof(NewName)) && _beginJobs.Length > 1)
            StopFunction("Cannot use -NewName when copying multiple jobs");
    }

    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted) return;
        bool pipelineInput = !_inputBound && InputObject is not null;
        SmoAgentJob[] jobs = pipelineInput ? InputObject! : _beginJobs;
        foreach (DbaInstanceParameter destination in Destination)
        {
            CancellationToken.ThrowIfCancellationRequested();
            Server? target = Connect(destination, DestinationSqlCredential, true, "Failure");
            if (target is null) continue;
            if (UseLastModified && _refreshed.Add(target.Name))
                target.JobServer.Jobs.Refresh();
            foreach (SmoAgentJob job in jobs)
            {
                CancellationToken.ThrowIfCancellationRequested();
                if (UseLastModified) Refresh(job);
                IEnumerable<string> scope = Source is not null && !pipelineInput
                    ? _sourceJobNames
                    : job.Parent.Jobs.Cast<SmoAgentJob>().Select(value => value.Name);
                WildcardNameMatcher include = Matcher(Job, scope);
                WildcardNameMatcher exclude = Matcher(ExcludeJob, scope);
                if (TestBound(nameof(Job)) && !include.Matches(job.Name))
                {
                    WriteMessage(MessageLevel.Verbose, string.Format("Job [{0}] filtered. Skipping.", job.Name));
                    continue;
                }
                if (TestBound(nameof(ExcludeJob)) && exclude.Matches(job.Name))
                {
                    WriteMessage(MessageLevel.Verbose, string.Format("Job [{0}] excluded. Skipping.", job.Name));
                    continue;
                }
                CopyJob(job, target, destination);
            }
        }
    }

    private void CopyJob(SmoAgentJob job, Server target, DbaInstanceParameter destination)
    {
        Server source = job.Parent.Parent;
        string name = job.Name;
        string destinationName = TestBound(nameof(NewName)) ? NewName! : name;
        if (Equal(source.Name, target.Name) && !TestBound(nameof(NewName)))
        {
            StopFunction(string.Format("Source and destination are the same server ({0}). Use -NewName to copy job [{1}] with a different name on the same server.", target.Name, name), continueLoop: true);
            return;
        }
        PSObject status = Status(source, target, destinationName);
        WriteMessage(MessageLevel.Verbose, "Working on job: " + name);
        DataTable plans = Query(source, @"SELECT sp.[name] AS MaintenancePlanName
FROM msdb.dbo.sysmaintplan_plans AS sp
INNER JOIN msdb.dbo.sysmaintplan_subplans AS sps ON sps.plan_id = sp.id
WHERE job_id = @jobId", new SqlParameter("@jobId", SqlDbType.UniqueIdentifier) { Value = job.JobID });
        if (plans.Rows.Count != 0)
        {
            string planNames = string.Join(" ", plans.Rows.Cast<DataRow>().Select(row => Text(row[0])));
            Skip(status, destination, string.Format("Job [{0}] is associated with Maintenance Plan: {1}", name, planNames), "Job is associated with maintenance plan");
            return;
        }

        string[] missingDatabases = job.JobSteps.Cast<JobStep>()
            .Where(step => step.SubSystem != AgentSubSystem.ActiveScripting && step.SubSystem != AgentSubSystem.AnalysisQuery && step.SubSystem != AgentSubSystem.AnalysisCommand)
            .Select(step => step.DatabaseName).Where(value => !string.IsNullOrEmpty(value) && !target.Databases.Cast<Microsoft.SqlServer.Management.Smo.Database>().Any(db => Equal(db.Name, value))).ToArray();
        if (missingDatabases.Length != 0)
        {
            string names = Unique(missingDatabases);
            Skip(status, destination, string.Format("Database(s) {0} doesn't exist on destination. Skipping job [{1}].", string.Join(" ", missingDatabases), name),
                "Job is dependent on database: " + names,
                string.Format("Database(s) {0} doesn't exist on destination. Skipping job [{1}].", names, name));
            return;
        }
        string owner = job.OwnerLoginName;
        bool missingOwner = !target.Logins.Cast<Login>().Any(login => Equal(login.Name, owner));
        if (missingOwner)
        {
            try
            {
                if (target.EnumWindowsUserInfo(owner).Rows.Count > 0)
                {
                    WriteMessage(MessageLevel.Verbose, string.Format("Login {0} not found as a direct login but has access via AD group membership on destination. Proceeding.", owner));
                    missingOwner = false;
                }
            }
            catch (PipelineStoppedException) { throw; }
            catch (Exception ex)
            {
                WriteMessage(MessageLevel.Verbose, string.Format("Could not verify AD group membership for {0} on destination: {1}", owner, ex.Message));
            }
        }
        if (missingOwner && !Force)
        {
            Skip(status, destination, string.Format("Login(s) {0} doesn't exist on destination. Use -Force to set owner to [sa]. Skipping job [{1}].", owner, name), "Job is dependent on login " + owner);
            return;
        }
        string[] missingProxies = job.JobSteps.Cast<JobStep>()
            .Select(step => step.ProxyName).Where(value => !string.IsNullOrEmpty(value) && !target.JobServer.ProxyAccounts.Cast<ProxyAccount>().Any(proxy => Equal(proxy.Name, value))).ToArray();
        if (missingProxies.Length != 0)
        {
            string names = Unique(missingProxies);
            Skip(status, destination, string.Format("Proxy Account(s) {0} doesn't exist on destination. Skipping job [{1}].", string.Join(" ", missingProxies), name),
                "Job is dependent on proxy " + names,
                string.Format("Proxy Account(s) {0} doesn't exist on destination. Skipping job [{1}].", names, name));
            return;
        }
        string[] missingOperators = new[] { job.OperatorToEmail, job.OperatorToNetSend, job.OperatorToPage }
            .Where(value => !string.IsNullOrEmpty(value) && !target.JobServer.Operators.Cast<Operator>().Any(op => Equal(op.Name, value))).ToArray();
        if (missingOperators.Length != 0)
        {
            string names = Unique(missingOperators);
            Skip(status, destination, string.Format("Operator(s) {0} doesn't exist on destination. Skipping job [{1}]", names, name), "Job is dependent on operator " + names);
            return;
        }

        SmoAgentJob? existing = target.JobServer.Jobs.Cast<SmoAgentJob>().FirstOrDefault(value => Equal(value.Name, destinationName));
        List<string> alerts = new List<string>();
        bool skipCreate = false;
        bool drop = false;
        string? replacementOwner = null;
        if (missingOwner)
            replacementOwner = Text(Query(target, "SELECT name FROM master.sys.server_principals WHERE sid = 0x01").Rows[0][0]);
        if (existing is not null)
        {
            if (UseLastModified)
            {
                try
                {
                    Refresh(existing);
                    string[] desired = NativeAgentJobDefinition.Snapshot(job, replacementOwner, DisableOnDestination ? false : (bool?)null);
                    string[] current = NativeAgentJobDefinition.Snapshot(existing);
                    string[] labels = { "job properties", "enabled state", "steps", "schedules" };
                    string[] changed = Enumerable.Range(0, labels.Length).Where(index => !string.Equals(desired[index], current[index], StringComparison.Ordinal)).Select(index => labels[index]).ToArray();
                    if (changed.Length == 0)
                    {
                        Skip(status, destination, string.Format("Job {0} has an identical definition on source and destination. Skipping.", destinationName), "Job definition is identical on source and destination");
                        skipCreate = true;
                    }
                    else
                    {
                        string changedText = string.Join(", ", changed);
                        DateTime sourceDate = LastModified(job);
                        DateTime destinationDate = LastModified(existing);
                        if (destinationDate > sourceDate)
                        {
                            if (Confirm(destination, string.Format("Job {0} differs ({1}) but is newer on destination. Skipping.", destinationName, changedText)))
                            {
                                Emit(status, "Skipped", string.Format(CultureInfo.InvariantCulture, "Definition differs ({0}) but destination job is newer than source (dest: {1} UTC, source: {2} UTC)", changedText, destinationDate, sourceDate));
                                WriteMessage(MessageLevel.Warning, string.Format(CultureInfo.InvariantCulture, "Job {0} differs from source ({1}) but is newer on destination ({2} UTC) than source ({3} UTC). Skipping. Use -Force without -UseLastModified to overwrite.", destinationName, changedText, destinationDate, sourceDate));
                            }
                            return;
                        }
                        if (changed.Length == 1 && changed[0] == "enabled state")
                        {
                            bool enabled = !DisableOnDestination && job.IsEnabled;
                            if (Confirm(destination, string.Format("Job {0} differs only in enabled state. Setting IsEnabled to {1}.", destinationName, enabled)))
                            {
                                try
                                {
                                    existing.IsEnabled = enabled;
                                    existing.Alter();
                                    Emit(status, "Successful", string.Format("Enabled state set to {0} in place; definition otherwise identical, job not recreated", enabled));
                                    WriteMessage(MessageLevel.Verbose, string.Format("Job {0} differs only in enabled state. Set IsEnabled to {1} without recreating.", destinationName, enabled));
                                }
                                catch (PipelineStoppedException) { throw; }
                                catch (Exception ex)
                                {
                                    Emit(status, "Failed");
                                    WriteMessage(MessageLevel.Verbose, string.Format("Issue updating enabled state for job {0} on {1} | {2}", destinationName, destination, ex.Message));
                                    return;
                                }
                            }
                            skipCreate = true;
                        }
                        else if (Confirm(destination, string.Format(CultureInfo.InvariantCulture, "Job {0} differs ({1}) and source is not older (source: {2} UTC, dest: {3} UTC). Dropping and recreating.", destinationName, changedText, sourceDate, destinationDate)))
                        {
                            WriteMessage(MessageLevel.Verbose, string.Format("Job {0} differs from source ({1}). Dropping and recreating.", destinationName, changedText));
                            drop = true;
                        }
                    }
                }
                catch (PipelineStoppedException) { throw; }
                catch (Exception ex)
                {
                    WriteMessage(MessageLevel.Warning, string.Format("Error comparing job definitions for {0} | {1}", name, ex.Message));
                    if (!Force)
                    {
                        SkipExisting(status, destination, name);
                        return;
                    }
                }
            }
            else if (!Force)
            {
                SkipExisting(status, destination, name);
                return;
            }
            else if (Confirm(destination, string.Format("Dropping job {0} and recreating", destinationName)))
            {
                WriteMessage(MessageLevel.Verbose, "Dropping Job " + destinationName);
                drop = true;
            }
            if (drop)
            {
                try
                {
                    DataTable rows = Query(target, "SELECT name FROM msdb.dbo.sysalerts WHERE job_id = (SELECT job_id FROM msdb.dbo.sysjobs WHERE name = @jobName)", NameParameter("@jobName", destinationName));
                    alerts.AddRange(rows.Rows.Cast<DataRow>().Select(row => Text(row[0])));
                    WriteMessage(MessageLevel.Verbose, string.Format("Found {0} alert(s) referencing job {1}", alerts.Count, destinationName));
                    existing.Drop();
                }
                catch (PipelineStoppedException) { throw; }
                catch (Exception ex)
                {
                    Emit(status, "Failed");
                    WriteMessage(MessageLevel.Verbose, string.Format("Issue dropping job {0} on {1} | {2}", name, destination, ex.Message));
                    return;
                }
            }
        }

        if (!skipCreate && Confirm(destination, "Creating Job " + destinationName))
        {
            try
            {
                WriteMessage(MessageLevel.Verbose, string.Format("Copying Job {0} as {1}", name, destinationName));
                string sql = string.Join(Environment.NewLine, job.Script().Cast<string>()) + Environment.NewLine;
                if (replacementOwner is not null)
                    sql = sql.Replace("@owner_login_name=" + SqlLiteral(owner), "@owner_login_name=" + SqlLiteral(replacementOwner));
                sql = System.Text.RegularExpressions.Regex.Replace(sql,
                    System.Text.RegularExpressions.Regex.Escape("@server=" + SqlLiteral(SmoServerExtensions.GetDomainInstanceName(source))),
                    match => "@server=" + SqlLiteral(SmoServerExtensions.GetDomainInstanceName(target)),
                    System.Text.RegularExpressions.RegexOptions.IgnoreCase);
                if (TestBound(nameof(NewName)))
                    sql = sql.Replace("@job_name=" + SqlLiteral(name), "@job_name=" + SqlLiteral(destinationName));
                WriteMessage(MessageLevel.Debug, sql);
                SetActiveConnection(target.ConnectionContext);
                target.ConnectionContext.ExecuteNonQuery(sql);
                target.JobServer.Jobs.Refresh();
                SmoAgentJob created = target.JobServer.Jobs[destinationName];
                created.IsEnabled = source.JobServer.Jobs[name].IsEnabled;
                created.Alter();
                if (alerts.Count > 0)
                {
                    WriteMessage(MessageLevel.Verbose, "Restoring alert-to-job links for " + name);
                    foreach (string alert in alerts)
                    {
                        try
                        {
                            Query(target, "EXEC msdb.dbo.sp_update_alert @name = @alertName, @job_name = @jobName", NameParameter("@alertName", alert), NameParameter("@jobName", destinationName));
                            WriteMessage(MessageLevel.Verbose, string.Format("Restored link between alert [{0}] and job [{1}]", alert, destinationName));
                        }
                        catch (PipelineStoppedException) { throw; }
                        catch (Exception ex)
                        {
                            WriteMessage(MessageLevel.Warning, string.Format("Failed to restore alert link for [{0}] to job [{1}] | {2}", alert, destinationName, ex.Message));
                        }
                    }
                }
                Emit(status, "Successful");
            }
            catch (PipelineStoppedException) { throw; }
            catch (Exception ex)
            {
                Emit(status, "Failed", MessageService.GetErrorMessage(new ErrorRecord(ex, "CopyJob", ErrorCategory.NotSpecified, job)));
                WriteMessage(MessageLevel.Verbose, string.Format("Issue copying job {0} on {1} | {2}", name, destination, ex.Message));
                return;
            }
        }
        if (DisableOnDestination && !skipCreate && Confirm(destination, "Disabling " + destinationName))
        {
            WriteMessage(MessageLevel.Verbose, string.Format("Disabling {0} on {1}", destinationName, destination));
            target.JobServer.Jobs[destinationName].IsEnabled = false;
            AlterUncaught(target.JobServer.Jobs[destinationName]);
        }
        if (DisableOnSource && Confirm(Source, "Disabling " + name))
        {
            WriteMessage(MessageLevel.Verbose, string.Format("Disabling {0} on {1}", name, Source));
            job.IsEnabled = false;
            AlterUncaught(job);
        }
    }

    private void AlterUncaught(SmoAgentJob job)
    {
        try { job.Alter(); }
        catch (PipelineStoppedException) { throw; }
        catch (Exception ex)
        {
            MethodInvocationException wrapped = new MethodInvocationException(
                string.Format("Exception calling \"Alter\" with \"0\" argument(s): \"{0}\"", ex.Message), ex);
            ErrorRecord record = new ErrorRecord(wrapped, ex.GetType().Name, ErrorCategory.NotSpecified, null);
            if (EnableException.ToBool())
            {
                // caller-try: terminate -- -EnableException requests a stop at the failed disable operation.
                ThrowTerminatingError(record); // style-ok: cs-raw-streams preserve the source's uncaught method fault outside Stop-Function
            }
            StatementFault.Surface(this, record);
        }
    }

    private Server? Connect(DbaInstanceParameter instance, PSCredential? credential, bool continueLoop, string failure)
    {
        WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
        try
        {
            Server server = ConnectionService.GetServer(new SmoConnectionRequest
            {
                Instance = instance, SqlCredential = credential,
                AzureUnsupported = true,
                BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential", "AzureUnsupported" },
                MessageCallback = (level, message) => WriteAttributedMessage("Connect-DbaInstance", level, message)
            });
            SetActiveConnection(server.ConnectionContext);
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "We are finished with this instance");
            return server;
        }
        catch (PipelineStoppedException) { throw; }
        catch (Exception ex)
        {
            if (!continueLoop)
            {
                WarnSourceConnection(instance, ex);
                return null;
            }
            StopFunction(failure, target: instance, errorRecord: new ErrorRecord(ex, "dbatools_Copy-DbaAgentJob", ErrorCategory.ConnectionError, instance), category: ErrorCategory.ConnectionError, continueLoop: continueLoop);
            return null;
        }
    }

    private void WarnSourceConnection(DbaInstanceParameter instance, Exception exception)
    {
        // The pinned begin block calls Get-DbaAgentJob without forwarding EnableException.
        MessageService.MessageRequest request = new()
        {
            FunctionName = "Get-DbaAgentJob", ModuleName = "dbatools", Level = MessageLevel.Warning,
            Message = "Failure", EnableException = false, FromStopFunction = true,
            File = MyInvocation.ScriptName, Line = MyInvocation.ScriptLineNumber
        };
        object target = MessageService.CollapseTarget(MessageService.ResolveTarget(this, request, instance));
        Exception transformed = MessageService.ResolveException(this, request, exception);
        ErrorRecord input = new(transformed, "dbatools_Get-DbaAgentJob", ErrorCategory.ConnectionError, target);
        ErrorRecord record = new(new Exception(MessageService.GetErrorMessage(input), transformed),
            "dbatools_Get-DbaAgentJob", ErrorCategory.ConnectionError, target);
        request.Target = target;
        request.ErrorRecord = new[] { record };
        MessageService.Write(this, request);
        try
        {
            if (SessionState.PSVariable.GetValue("global:Error") is System.Collections.ArrayList errors)
            {
                errors.Insert(0, record);
                int limit;
                if (!Int32.TryParse(Convert.ToString(SessionState.PSVariable.GetValue("MaximumErrorCount"), CultureInfo.InvariantCulture), out limit))
                    limit = 256;
                if (limit >= 0 && errors.Count > limit)
                    errors.RemoveRange(limit, errors.Count - limit);
            }
        }
        catch (Exception)
        {
            // Restricted session state must not replace the original connection failure.
        }
    }

    private bool Confirm(DbaInstanceParameter? destination, string action)
    {
        string target = destination?.ToString() ?? "";
        return Force ? AgentConfirmation.WithConfirmationSuppressed(SessionState, () => ShouldProcess(target, action)) : ShouldProcess(target, action);
    }

    private DataTable Query(Server server, string sql, params SqlParameter[] parameters)
    {
        WriteMessage(MessageLevel.Debug, sql);
        SqlConnection connection = server.ConnectionContext.SqlConnectionObject;
        bool opened = connection.State != ConnectionState.Open;
        if (opened) connection.Open();
        try
        {
            using (SqlCommand command = connection.CreateCommand())
            {
                command.CommandText = sql;
                command.CommandTimeout = server.ConnectionContext.StatementTimeout;
                command.Parameters.AddRange(parameters);
                SetActiveCommand(command);
                try
                {
                    using (SqlDataReader reader = command.ExecuteReader())
                    {
                        DataTable rows = new DataTable();
                        if (reader.FieldCount > 0) rows.Load(reader);
                        return rows;
                    }
                }
                finally { SetActiveCommand(null); }
            }
        }
        finally { if (opened) connection.Close(); }
    }

    private DateTime LastModified(SmoAgentJob job)
    {
        const string current = @"SELECT DATEADD(MINUTE, -DATEDIFF(MINUTE, GETUTCDATE(), GETDATE()), MAX(x.date_modified))
FROM (
    SELECT j.date_modified FROM msdb.dbo.sysjobs AS j WHERE j.job_id = @jobId
    UNION ALL
    SELECT s.date_modified FROM msdb.dbo.sysjobschedules AS js
    INNER JOIN msdb.dbo.sysschedules AS s ON s.schedule_id = js.schedule_id
    WHERE js.job_id = @jobId
) AS x";
        DataTable rows = Query(job.Parent.Parent, current,
            new SqlParameter("@jobId", SqlDbType.UniqueIdentifier) { Value = job.JobID });
        return (DateTime)rows.Rows[0][0];
    }

    private static void Refresh(SmoAgentJob job)
    {
        job.Refresh();
        job.JobSteps.Refresh(true);
        job.JobSchedules.Refresh(true);
    }

    private static WildcardNameMatcher Matcher(object[]? values, IEnumerable<string> scope)
        => WildcardNameFilter.CreateMatcher(values, true,
            (value, name) => LanguagePrimitives.Equals(value, name, true, CultureInfo.InvariantCulture), scope);

    private static bool Equal(string left, string right) => string.Equals(left, right, StringComparison.InvariantCultureIgnoreCase);
    private static string Text(object value) => Convert.ToString(value, CultureInfo.InvariantCulture) ?? "";
    private static string Unique(IEnumerable<string> values) => string.Join(", ", values.OrderBy(value => value, StringComparer.CurrentCultureIgnoreCase).Distinct(StringComparer.Ordinal));
    private static string SqlLiteral(string value) => "N'" + value.Replace("'", "''") + "'";
    private static SqlParameter NameParameter(string name, string value) => new SqlParameter(name, SqlDbType.NVarChar, 128) { Value = value };

    private void SkipExisting(PSObject status, DbaInstanceParameter destination, string name)
        => Skip(status, destination, string.Format("Job {0} exists at destination. Use -Force to drop and migrate.", name), "Already exists on destination");

    private void Skip(PSObject status, DbaInstanceParameter destination, string action, string notes, string? verbose = null)
    {
        if (!Confirm(destination, action)) return;
        Emit(status, "Skipped", notes);
        WriteMessage(MessageLevel.Verbose, verbose ?? action);
    }

    private static PSObject Status(Server source, Server destination, string name)
    {
        PSObject result = new PSObject();
        result.Properties.Add(new PSNoteProperty("SourceServer", source.Name));
        result.Properties.Add(new PSNoteProperty("DestinationServer", destination.Name));
        result.Properties.Add(new PSNoteProperty("Name", name));
        result.Properties.Add(new PSNoteProperty("Type", "Agent Job"));
        result.Properties.Add(new PSNoteProperty("Status", null));
        result.Properties.Add(new PSNoteProperty("Notes", null));
        result.Properties.Add(new PSNoteProperty("DateTime", new DbaDateTime(DateTime.Now)));
        OutputHelper.SetDefaultDisplayPropertySet(result, "DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes");
        OutputHelper.InsertTypeName(result, "MigrationObject");
        return result;
    }

    private void Emit(PSObject status, string outcome, string? notes = null)
    {
        status.Properties["Status"].Value = outcome;
        status.Properties["Notes"].Value = notes;
        WriteObject(status);
    }
}
