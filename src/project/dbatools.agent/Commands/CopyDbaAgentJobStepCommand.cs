#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Management.Smo.Agent;
using System.Text;
using SmoAgentJob = Microsoft.SqlServer.Management.Smo.Agent.Job;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Copies job steps from one SQL Server Agent job to another, preserving job history by synchronizing steps without dropping the job itself.
/// </summary>
/// <para>
/// Synchronizes SQL Server Agent job steps between instances by copying step definitions from source jobs to destination jobs. Unlike Copy-DbaAgentJob with -Force, this command preserves job execution history because it only drops and recreates individual steps rather than the entire job. This is essential for maintaining historical job execution data in Always On Availability Group scenarios, disaster recovery environments, or when deploying step modifications across multiple servers.
/// </para>
/// <para>
/// The function removes all existing steps from the destination job before copying source steps, ensuring a clean synchronization. Job metadata like ownership, schedules, and alerts remain unchanged on the destination.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Copy-DbaAgentJobStep -Source PrimaryAG -Destination SecondaryAG1, SecondaryAG2 -Job "MaintenanceJob"
/// </code>
/// <para>
/// Copies all job steps from the "MaintenanceJob" on PrimaryAG to the same job on SecondaryAG1 and SecondaryAG2, preserving job history on the destination servers.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentJob -SqlInstance PrimaryAG -Job "BackupJob" | Copy-DbaAgentJobStep -Destination SecondaryAG1
/// </code>
/// <para>
/// Retrieves the BackupJob from PrimaryAG and synchronizes its steps to the same job on SecondaryAG1 using pipeline input.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Copy-DbaAgentJobStep -Source sqlserver2014a -Destination sqlcluster -Job "DataETL" -SourceSqlCredential $cred
/// </code>
/// <para>
/// Copies job steps for the "DataETL" job from sqlserver2014a to sqlcluster, using SQL credentials for the source server and Windows credentials for the destination.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Copy-DbaAgentJobStep -Source Primary -Destination Replica1, Replica2, Replica3
/// </code>
/// <para>
/// Synchronizes all job steps from Primary to multiple AG replicas, ensuring all replicas have identical job step definitions while preserving their individual job execution histories.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Migration, Agent, Job
/// Author: the dbatools team + Claude
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Copy-DbaAgentJobStep" />
[Cmdlet(VerbsCommon.Copy, "DbaAgentJobStep", DefaultParameterSetName = "Default",
    SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaAgentJobStepCommand : DbaBaseCmdlet
{
    /// <para>
    /// Source SQL Server instance containing the jobs with steps to copy. You must have sysadmin access and server version must be SQL Server 2000 or higher.
    /// Use this when copying job steps from a specific instance rather than piping job objects with InputObject.
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
    /// Destination SQL Server instance(s) where job steps will be synchronized. You must have sysadmin access and the server must be SQL Server 2000 or higher.
    /// Supports multiple destinations to copy job steps to multiple servers simultaneously, such as syncing all AG replicas or DR servers.
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
    /// Specifies which SQL Agent jobs to process by name. Accepts wildcards and multiple job names.
    /// Use this to synchronize steps for specific jobs, such as copying modified steps from a primary AG replica to secondary replicas.
    /// If unspecified, all jobs will be processed.
    /// </para>
    [Parameter(Position = 4)]
    public object[]? Job { get; set; }

    /// <para>
    /// Specifies which SQL Agent jobs to skip during the copy operation. Accepts wildcards and multiple job names.
    /// Use this to exclude specific jobs from bulk operations, such as skipping environment-specific jobs that shouldn't be synchronized.
    /// </para>
    [Parameter(Position = 5)]
    public object[]? ExcludeJob { get; set; }

    /// <para>
    /// Specifies which job steps to copy by name. If not specified, all steps are copied.
    /// Use this to synchronize specific steps rather than all steps from a job.
    /// </para>
    [Parameter(Position = 6)]
    public string[]? Step { get; set; }

    /// <para>
    /// Accepts SQL Agent job objects from the pipeline, typically from Get-DbaAgentJob.
    /// Use this to copy steps for pre-filtered jobs or when combining with other job management cmdlets for complex workflows.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 7)]
    public SmoAgentJob[]? InputObject { get; set; }

    private SmoAgentJob[] _initialJobs = Array.Empty<SmoAgentJob>();
    private readonly Dictionary<Server, string[]> _sourceJobScopes = new();
    private bool _explicitInput;
    private bool _filterJobs;
    private bool _excludeJobs;
    private bool _filterSteps;

    protected override void BeginProcessing()
    {
        _explicitInput = TestBound(nameof(InputObject));
        _filterJobs = TestBound(nameof(Job));
        _excludeJobs = TestBound(nameof(ExcludeJob));
        _filterSteps = TestBound(nameof(Step));
        _initialJobs = InputObject ?? Array.Empty<SmoAgentJob>();
        if (Source is null) return;
        try
        {
            Server? source = ConnectServer(Source, SourceSqlCredential, true);
            if (source is null) { _initialJobs = Array.Empty<SmoAgentJob>(); return; }
            List<SmoAgentJob> selected = new List<SmoAgentJob>();
            SmoAgentJob[] sourceJobs = source.JobServer.Jobs.Cast<SmoAgentJob>()
                .Where(job => job.JobType == JobType.Local || job.JobType == JobType.MultiServer).ToArray();
            string[] scope = sourceJobs.Select(job => job.Name).ToArray();
            _sourceJobScopes[source] = scope;
            WildcardNameMatcher include = Matcher(Job, scope);
            WildcardNameMatcher exclude = Matcher(ExcludeJob, scope);
            foreach (SmoAgentJob job in sourceJobs)
            {
                if (_filterJobs && !include.Matches(job.Name)) continue;
                if (_excludeJobs && exclude.Matches(job.Name)) continue;
                selected.Add(job);
            }
            _initialJobs = selected.ToArray();
        }
        catch (PipelineStoppedException) { throw; }
        catch (Exception ex)
        {
            ErrorRecord error = ex is IContainsErrorRecord recorded ? recorded.ErrorRecord :
                new ErrorRecord(ex, ex.GetType().Name, ErrorCategory.ConnectionError, Source);
            StopFunction(string.Format("Error occurred while establishing connection to {0}", Source),
                category: ErrorCategory.ConnectionError, errorRecord: error, target: Source);
            return;
        }
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
        SmoAgentJob[] jobs = !_explicitInput && InputObject is not null ? InputObject : _initialJobs;
        foreach (DbaInstanceParameter destination in Destination)
        {
            CancellationToken.ThrowIfCancellationRequested();
            Server? server = ConnectServer(destination, DestinationSqlCredential, false);
            if (server is null) continue;
            JobCollection destinationJobs = server.JobServer.Jobs;
            foreach (SmoAgentJob sourceJob in jobs)
            {
                CancellationToken.ThrowIfCancellationRequested();
                string name = sourceJob.Name;
                // Literal precedence belongs to the source server, not a filtered or single-record subset.
                string[] scope = _filterJobs || _excludeJobs ? SourceJobScope(sourceJob.Parent.Parent) : Array.Empty<string>();
                WildcardNameMatcher include = Matcher(Job, scope);
                WildcardNameMatcher exclude = Matcher(ExcludeJob, scope);
                DateTime timestamp = DateTime.Now;
                if (_filterJobs && !include.Matches(name))
                {
                    WriteMessage(MessageLevel.Verbose, string.Format("Job [{0}] filtered. Skipping.", name));
                    continue;
                }
                if (_excludeJobs && exclude.Matches(name))
                {
                    WriteMessage(MessageLevel.Verbose, string.Format("Job [{0}] excluded. Skipping.", name));
                    continue;
                }
                WriteMessage(MessageLevel.Verbose, "Working on job: " + name);
                SmoAgentJob? target = null;
                foreach (SmoAgentJob candidate in destinationJobs)
                    if (LanguagePrimitives.Equals(candidate.Name, name, true)) { target = candidate; break; }
                if (target is null)
                {
                    if (ShouldProcess(destination.ToString(), string.Format("Job {0} does not exist on destination. Skipping step synchronization.", name)))
                    {
                        WriteStatus(sourceJob, server, timestamp, "Skipped", "Job does not exist on destination. Use Copy-DbaAgentJob to create it first.");
                        WriteMessage(MessageLevel.Warning, string.Format("Job {0} does not exist on destination {1}. Use Copy-DbaAgentJob to create it first.", name, destination));
                    }
                    continue;
                }
                List<JobStep> sourceSteps = SelectSteps(sourceJob.JobSteps);
                if (_filterSteps && sourceSteps.Count == 0)
                {
                    WriteMessage(MessageLevel.Warning, string.Format("No matching steps found in job {0} for specified step names: {1}", name, string.Join(", ", Step ?? Array.Empty<string>())));
                    continue;
                }
                if (!ShouldProcess(destination.ToString(), "Synchronizing steps for job " + name)) continue;
                try
                {
                    List<JobStep> removed = SelectSteps(target.JobSteps);
                    WriteMessage(MessageLevel.Verbose, string.Format("Removing {0} existing step(s) from {1} on {2}", removed.Count, name, destination));
                    foreach (JobStep step in removed)
                    {
                        WriteMessage(MessageLevel.Verbose, string.Format("Removing step {0} from {1} on {2}", step.Name, name, destination));
                        step.Drop();
                    }
                    target.JobSteps.Refresh();
                    WriteMessage(MessageLevel.Verbose, string.Format("Copying {0} step(s) from {1} to {2}", sourceSteps.Count, name, destination));
                    ScriptingOptions options = new ScriptingOptions { AgentJobId = false };
                    foreach (JobStep step in sourceSteps)
                    {
                        WriteMessage(MessageLevel.Verbose, string.Format("Creating step {0} in {1} on {2}", step.Name, name, destination));
                        StringBuilder script = new StringBuilder();
                        foreach (string? batch in step.Script(options)) script.AppendLine(batch);
                        string sql = script.ToString();
                        WriteMessage(MessageLevel.Debug, sql);
                        server.ConnectionContext.ExecuteNonQuery(sql);
                    }
                    target.JobSteps.Refresh();
                    WriteStatus(sourceJob, server, timestamp, "Successful", string.Format("Synchronized {0} job step(s)", sourceSteps.Count));
                }
                catch (PipelineStoppedException) { throw; }
                catch (Exception ex)
                {
                    ErrorRecord error = new ErrorRecord(ex, ex.GetType().Name, ErrorCategory.NotSpecified, destination);
                    WriteStatus(sourceJob, server, timestamp, "Failed", MessageService.GetErrorMessage(error));
                    StopFunction(string.Format("Failed to synchronize steps for job {0} on {1}", name, destination), errorRecord: error, target: destination, continueLoop: true);
                }
            }
        }
    }

    private string[] SourceJobScope(Server source)
    {
        if (!_sourceJobScopes.TryGetValue(source, out var scope))
        {
            scope = source.JobServer.Jobs.Cast<SmoAgentJob>()
                .Where(job => job.JobType == JobType.Local || job.JobType == JobType.MultiServer)
                .Select(job => job.Name).ToArray();
            _sourceJobScopes.Add(source, scope);
        }
        return scope;
    }

    private List<JobStep> SelectSteps(JobStepCollection steps)
    {
        List<JobStep> result = new List<JobStep>();
        foreach (JobStep step in steps)
        {
            bool include = !_filterSteps;
            foreach (string filter in Step ?? Array.Empty<string>())
                if (LanguagePrimitives.Equals(filter, step.Name, true)) { include = true; break; }
            if (include) result.Add(step);
        }
        return result;
    }

    private static WildcardNameMatcher Matcher(object[]? patterns, IEnumerable<string> scope)
        => WildcardNameFilter.CreateMatcher(patterns, true,
            (value, name) => LanguagePrimitives.Equals(value, name, true, CultureInfo.InvariantCulture), scope);

    private Server? ConnectServer(DbaInstanceParameter instance, PSCredential? credential, bool source)
    {
        WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
        try
        {
            SmoConnectionRequest request = new SmoConnectionRequest();
            request.Instance = instance;
            request.SqlCredential = credential;
            request.AzureUnsupported = true;
            request.BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential", "AzureUnsupported" };
            request.MessageCallback = (level, message) => WriteAttributedMessage("Connect-DbaInstance", level, message);
            Server connected = ConnectionService.GetServer(request);
            SetActiveConnection(connected.ConnectionContext);
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "We are finished with this instance");
            return connected;
        }
        catch (PipelineStoppedException) { throw; }
        catch (Exception ex)
        {
            if (source)
            {
                WarnSourceConnection(instance, ex);
                return null;
            }
            ErrorRecord error = new ErrorRecord(ex, "dbatools_Copy-DbaAgentJobStep", ErrorCategory.ConnectionError, instance);
            StopFunction("Failure", errorRecord: error, category: ErrorCategory.ConnectionError, target: instance, continueLoop: true);
            return null;
        }
    }

    private void WarnSourceConnection(DbaInstanceParameter instance, Exception exception)
    {
        // Pinned Copy-DbaAgentJobStep:121-131 does not forward EnableException to Get-DbaAgentJob.
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

    private void WriteStatus(SmoAgentJob job, Server destination, DateTime timestamp, string status, string? notes)
    {
        PSObject result = new PSObject();
        result.Properties.Add(new PSNoteProperty("SourceServer", job.Parent.Parent.Name));
        result.Properties.Add(new PSNoteProperty("DestinationServer", destination.Name));
        result.Properties.Add(new PSNoteProperty("Name", job.Name));
        result.Properties.Add(new PSNoteProperty("Type", "Agent Job Steps"));
        result.Properties.Add(new PSNoteProperty("Status", status));
        result.Properties.Add(new PSNoteProperty("Notes", notes));
        result.Properties.Add(new PSNoteProperty("DateTime", new DbaDateTime(timestamp)));
        OutputHelper.InsertTypeName(result, "MigrationObject");
        OutputHelper.SetDefaultDisplayPropertySet(result, "DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes");
        WriteObject(result);
    }
}
