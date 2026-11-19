#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Management.Smo.Agent;
using SmoAgentJob = Microsoft.SqlServer.Management.Smo.Agent.Job;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves detailed SQL Agent job step information including execution status and configuration from SQL Server instances.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaAgentJobStep")]
public sealed class GetDbaAgentJobStepCommand : DbaInstanceCmdlet
{
    /// <summary>Target SQL Server instances.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    [PsAgentStepDbaInstanceArrayCast]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>Job names to include.</summary>
    [Parameter(Position = 2)]
    public string[]? Job { get; set; }

    /// <summary>Job names to exclude.</summary>
    [Parameter(Position = 3)]
    public string[]? ExcludeJob { get; set; }

    /// <summary>SQL Agent jobs supplied directly or through the pipeline.</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    [PsAgentJobArrayCast]
    public SmoAgentJob[]? InputObject { get; set; }

    /// <summary>Exclude jobs whose IsEnabled property is false.</summary>
    [Parameter]
    public SwitchParameter ExcludeDisabledJobs { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Server? _server;
    private readonly List<SmoAgentJob> _jobs = new();
    private bool _instanceFromCommandLine;
    private bool _inputFromCommandLine;
    private bool _commandLineTaken;

    protected override void BeginProcessing()
    {
        // Only command-line arguments are bound before the first record; pipeline input binds per record.
        _instanceFromCommandLine = TestBound(nameof(SqlInstance));
        _inputFromCommandLine = TestBound(nameof(InputObject));
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // Accumulate every record's jobs, correcting the source, which rebinds $InputObject on each
        // piped record and so keeps only the last piped job. A command-line value is the same on every
        // record and is taken once; a pipeline value is new on each record and is always taken.
        bool takeInput = !_inputFromCommandLine || !_commandLineTaken;
        bool takeInstances = !_instanceFromCommandLine || !_commandLineTaken;
        _commandLineTaken = true;

        if (takeInput)
        {
            foreach (SmoAgentJob? job in InputObject ?? Array.Empty<SmoAgentJob>())
            {
                if (job is not null)
                    _jobs.Add(job);
            }
        }
        if (!takeInstances)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
        {
            if (Interrupted)
                return;

            Server? server = ConnectInstance(instance);
            if (server is null)
                continue;

            _server = server;
            WriteMessage(MessageLevel.Verbose, String.Format("Collecting jobs on {0}", instance));
            foreach (SmoAgentJob job in server.JobServer.Jobs)
                _jobs.Add(job);
        }
    }

    protected override void EndProcessing()
    {
        if (Interrupted)
            return;

        // Pinned help documents wildcards for -Job and -ExcludeJob, which the source's literal -In
        // and -NotIn never honoured. A real job name of the job's own instance stays literal
        // (pinned Install-DbaMaintenanceSolution passes one), so matchers are kept per JobServer.
        List<JobServer> scopeServers = new();
        List<WildcardNameMatcher[]> scopeMatchers = new();
        WildcardNameMatcher[] MatchersFor(JobServer jobServer)
        {
            for (int index = 0; index < scopeServers.Count; index++)
            {
                if (ReferenceEquals(scopeServers[index], jobServer))
                    return scopeMatchers[index];
            }
            WildcardNameMatcher[] created =
            {
                AgentNameFilter.CreateMatcher(Job, true, JobNames(jobServer)),
                AgentNameFilter.CreateMatcher(ExcludeJob, true, JobNames(jobServer))
            };
            scopeServers.Add(jobServer);
            scopeMatchers.Add(created);
            return created;
        }

        List<SmoAgentJob> jobs = new();
        foreach (SmoAgentJob job in _jobs)
        {
            if (Interrupted)
                return;
            if (LanguagePrimitives.IsTrue(Job) && !MatchersFor(job.Parent)[0].Matches(job.Name))
                continue;
            if (LanguagePrimitives.IsTrue(ExcludeJob) && MatchersFor(job.Parent)[1].Matches(job.Name))
                continue;
            if (ExcludeDisabledJobs && !job.IsEnabled)
                continue;
            jobs.Add(job);
        }

        // The source interpolates the server variable followed by the literal suffix ".Name".
        WriteMessage(MessageLevel.Verbose, String.Format("Collecting job steps on ({0}.Name)", _server));
        foreach (SmoAgentJob job in jobs)
        {
            foreach (JobStep step in job.JobSteps)
            {
                if (Interrupted)
                    return;

                PSObject output = PSObject.AsPSObject(step);
                foreach (string name in new[] { "ComputerName", "InstanceName", "SqlInstance", "AgentJob" })
                    output.Properties.Remove(name);
                OutputHelper.AddInstanceProperties(output, step.Parent.Parent.Parent);
                output.Properties.Add(new PSNoteProperty("AgentJob", step.Parent.Name));
                OutputHelper.SetDefaultDisplayPropertySet(output,
                    "ComputerName", "InstanceName", "SqlInstance", "AgentJob", "Name", "SubSystem",
                    "LastRunDate", "LastRunOutcome", "State");
                WriteObject(output);
            }
        }
    }

    // Every job name of one instance, the unfiltered scope of the job name filters.
    private static IEnumerable<string> JobNames(JobServer? jobServer)
    {
        if (jobServer is null)
            yield break;
        foreach (SmoAgentJob job in jobServer.Jobs)
            yield return job.Name;
    }
}

/// <summary>Reproduces the advanced function's typed DbaInstanceParameter array conversion.</summary>
internal sealed class PsAgentStepDbaInstanceArrayCastAttribute : ArgumentTransformationAttribute
{
    public override object? Transform(EngineIntrinsics engineIntrinsics, object? inputData)
    {
        if (inputData is null)
            return null;
        try
        {
            return LanguagePrimitives.ConvertTo(inputData, typeof(DbaInstanceParameter[]), CultureInfo.InvariantCulture);
        }
        catch (PSInvalidCastException ex)
        {
            throw new ArgumentTransformationMetadataException(ex.Message, ex);
        }
    }
}

/// <summary>Reproduces the advanced function's typed SQL Agent Job array conversion.</summary>
internal sealed class PsAgentJobArrayCastAttribute : ArgumentTransformationAttribute
{
    public override object? Transform(EngineIntrinsics engineIntrinsics, object? inputData)
    {
        if (inputData is null)
            return null;
        try
        {
            return LanguagePrimitives.ConvertTo(inputData, typeof(SmoAgentJob[]), CultureInfo.InvariantCulture);
        }
        catch (PSInvalidCastException ex)
        {
            throw new ArgumentTransformationMetadataException(ex.Message, ex);
        }
    }
}
