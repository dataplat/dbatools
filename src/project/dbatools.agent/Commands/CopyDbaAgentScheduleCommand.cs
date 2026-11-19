#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Management.Smo.Agent;
using AgentJob = Microsoft.SqlServer.Management.Smo.Agent.Job;
using System.Text;
using SmoAgentJobSchedule = Microsoft.SqlServer.Management.Smo.Agent.JobSchedule;

namespace Dataplat.Dbatools.Commands;

/// <summary>Migrates SQL Agent shared job schedules between SQL Server instances for job schedule standardization.</summary>
[Cmdlet(VerbsCommon.Copy, "DbaAgentSchedule",
    SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaAgentScheduleCommand : DbaBaseCmdlet
{
    /// <summary>Source SQL Server instance.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter? Source { get; set; }

    /// <summary>Alternative credential for the source instance.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <summary>Destination SQL Server instances.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    public DbaInstanceParameter[] Destination { get; set; } = null!;

    /// <summary>Alternative credential for destination instances.</summary>
    [Parameter(Position = 3)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>Only copy schedules with these names.</summary>
    [Parameter(Position = 4)]
    public string[]? Schedule { get; set; }

    /// <summary>Only copy schedules with these identifiers.</summary>
    [Parameter(Position = 5)]
    public int[]? Id { get; set; }

    /// <summary>Shared schedules supplied directly or through the pipeline.</summary>
    [Parameter(ValueFromPipeline = true, Position = 6)]
    public SmoAgentJobSchedule[]? InputObject { get; set; }

    /// <summary>Request replacement of existing schedules.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    private SmoAgentJobSchedule[] _initial = Array.Empty<SmoAgentJobSchedule>();
    private bool _explicitInput;

    protected override void BeginProcessing()
    {
        _explicitInput = TestBound(nameof(InputObject));
        _initial = InputObject ?? Array.Empty<SmoAgentJobSchedule>();
        if (Source is null) return;
        Server? source = Open(Source, SourceSqlCredential, false);
        if (source is null) return;
        if (LanguagePrimitives.IsTrue(InputObject)) return;
        // The source Refresh is the causal read fault and belongs to Copy. After it fails,
        // omit the nested getter's secondary child-owned enumeration record.
        if (!Refresh(source)) return;
        List<SmoAgentJobSchedule> selected = new List<SmoAgentJobSchedule>();
        foreach (SmoAgentJobSchedule schedule in source.JobServer.SharedSchedules)
        {
            if (FilterHelper.IsActive(Schedule) && !MatchSchedule(schedule.Name)) continue;
            if (FilterHelper.IsActive(Id) && Array.IndexOf(Id!, schedule.ID) < 0) continue;
            selected.Add(schedule);
        }
        _initial = selected.ToArray();
    }

    protected override void ProcessRecord()
    {
        if (Interrupted) return;
        if (!LanguagePrimitives.IsTrue(Source) && !LanguagePrimitives.IsTrue(InputObject))
        {
            StopFunction("You must specify either Source or pipe in results from Get-DbaAgentSchedule");
            return;
        }
        SmoAgentJobSchedule[] schedules = !_explicitInput && InputObject is not null ? InputObject : _initial;
        foreach (DbaInstanceParameter destination in Destination)
        {
            CancellationToken.ThrowIfCancellationRequested();
            Server? server = Open(destination, DestinationSqlCredential, true);
            if (server is null) continue;
            bool destinationRead = Refresh(server);
            List<string> existingNames = new List<string>();
            // A failed refresh is reported by this command. The pin's subsequent Get-DbaAgentSchedule
            // refresh and enumeration only add child-owned consequences; omit those duplicate records.
            if (destinationRead)
                foreach (SmoAgentJobSchedule existing in server.JobServer.SharedSchedules)
                    if (!FilterHelper.IsActive(Schedule) || MatchSchedule(existing.Name)) existingNames.Add(existing.Name);
            foreach (SmoAgentJobSchedule current in schedules)
            {
                CancellationToken.ThrowIfCancellationRequested();
                string name = current.Name;
                DateTime timestamp = DateTime.Now;
                bool exists = existingNames.Exists(value => LanguagePrimitives.Equals(value, name, true));
                if (exists)
                {
                    if (!Force)
                    {
                        string action = string.Format("Shared job schedule {0} exists at destination. Use -Force to drop and migrate.", name);
                        if (Approve(destination, action))
                        {
                            Emit(current, server, timestamp, "Skipped", "Already exists on destination");
                            WriteMessage(MessageLevel.Verbose, action);
                        }
                        continue;
                    }
                    bool attached = false;
                    foreach (AgentJob job in server.JobServer.Jobs)
                        foreach (SmoAgentJobSchedule schedule in job.JobSchedules)
                            if (LanguagePrimitives.Equals(schedule.Name, name, true)) attached = true;
                    if (attached)
                    {
                        string action = string.Format("Schedule [{0}] has associated jobs. Skipping.", name);
                        if (Approve(destination, action))
                        {
                            Emit(current, server, timestamp, "Skipped", "Schedule has associated jobs");
                            WriteMessage(MessageLevel.Verbose, action);
                        }
                        continue;
                    }
                    if (Approve(destination, "Dropping schedule " + name + " and recreating"))
                    {
                        try
                        {
                            WriteMessage(MessageLevel.Verbose, "Dropping schedule " + name);
                            server.JobServer.SharedSchedules[name].Drop();
                        }
                        catch (PipelineStoppedException) { throw; }
                        catch (Exception ex)
                        {
                            Emit(current, server, timestamp, "Failed", "Issue dropping schedule on destination");
                            WriteMessage(MessageLevel.Verbose, string.Format("Issue dropping schedule {0} on {1} | {2}", name, destination, ex.Message));
                            continue;
                        }
                    }
                }
                if (!Approve(destination, "Creating schedule " + name)) continue;
                try
                {
                    WriteMessage(MessageLevel.Verbose, "Copying schedule " + name);
                    StringBuilder script = new StringBuilder();
                    foreach (string? part in current.Script()) script.AppendLine(part);
                    string sql = script.ToString();
                    WriteMessage(MessageLevel.Debug, sql);
                    server.ConnectionContext.ExecuteNonQuery(sql);
                    Emit(current, server, timestamp, "Successful", null);
                }
                catch (PipelineStoppedException) { throw; }
                catch (Exception ex)
                {
                    Emit(current, server, timestamp, "Failed", null);
                    WriteMessage(MessageLevel.Verbose, string.Format("Issue creating schedule {0} on {1} | {2}", name, destination, ex.Message));
                }
            }
        }
    }

    private bool MatchSchedule(string name)
    {
        foreach (string filter in Schedule ?? Array.Empty<string>())
            if (LanguagePrimitives.Equals(filter, name, true) ||
                new WildcardPattern(filter, WildcardOptions.IgnoreCase).IsMatch(name)) return true;
        return false;
    }

    private Server? Open(DbaInstanceParameter instance, PSCredential? credential, bool continueLoop)
    {
        WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
        SmoConnectionRequest request = new SmoConnectionRequest
        {
            Instance = instance, SqlCredential = credential, MinimumVersion = 9, AzureUnsupported = true,
            BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential", "MinimumVersion", "AzureUnsupported" },
            MessageCallback = (level, message) => WriteAttributedMessage("Connect-DbaInstance", level, message)
        };
        try
        {
            Server server = ConnectionService.GetServer(request);
            SetActiveConnection(server.ConnectionContext);
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "We are finished with this instance");
            return server;
        }
        catch (PipelineStoppedException) { throw; }
        catch (Exception ex)
        {
            ErrorRecord record = new ErrorRecord(ex, "dbatools_Copy-DbaAgentSchedule", ErrorCategory.ConnectionError, instance);
            StopFunction("Failure", target: instance, errorRecord: record, category: ErrorCategory.ConnectionError, continueLoop: continueLoop);
            return null;
        }
    }

    private bool Refresh(Server server)
    {
        try { server.JobServer.SharedSchedules.Refresh(); return true; }
        catch (PipelineStoppedException) { throw; }
        catch (Exception ex)
        {
            MethodInvocationException wrapped = new MethodInvocationException(
                string.Format("Exception calling \"Refresh\" with \"0\" argument(s): \"{0}\"", ex.Message), ex);
            ErrorRecord record = new ErrorRecord(wrapped, ex.GetType().Name, ErrorCategory.NotSpecified, null);
            if (EnableException)
                // caller-try: terminate -- EnableException explicitly requests the first read fault to stop.
                ThrowTerminatingError(record); // style-ok: cs-raw-streams source method fault outside Stop-Function
            StatementFault.Surface(this, record);
            return false;
        }
    }

    private bool Approve(DbaInstanceParameter target, string action)
    {
        if (!Force) return ShouldProcess(target.ToString(), action);
        return AgentConfirmation.WithConfirmationSuppressed(SessionState, () => ShouldProcess(target.ToString(), action));
    }

    private void Emit(SmoAgentJobSchedule schedule, Server destination, DateTime timestamp, string status, string? notes)
    {
        JobServer sourceAgent = schedule.Parent is JobServer agent ? agent : ((AgentJob)schedule.Parent).Parent;
        PSObject result = new PSObject();
        string[] properties = { "SourceServer", "DestinationServer", "Type", "Name", "Status", "Notes", "DateTime" };
        object?[] values = { sourceAgent.Parent.Name, destination.Name, "Agent Schedule", schedule.Name, status, notes, new DbaDateTime(timestamp) };
        for (int i = 0; i < properties.Length; i++) result.Properties.Add(new PSNoteProperty(properties[i], values[i]));
        OutputHelper.SetDefaultDisplayPropertySet(result, "DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes");
        OutputHelper.InsertTypeName(result, "MigrationObject");
        WriteObject(result);
    }
}
