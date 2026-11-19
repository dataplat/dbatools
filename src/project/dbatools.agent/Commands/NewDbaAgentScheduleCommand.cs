#nullable enable

using System;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Management.Smo.Agent;

namespace Dataplat.Dbatools.Commands;

/// <summary>Creates SQL Agent schedules and optionally attaches them to existing jobs.</summary>
[Cmdlet(VerbsCommon.New, "DbaAgentSchedule", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
[OutputType(typeof(JobSchedule))]
public sealed partial class NewDbaAgentScheduleCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The job(s) to attach the new schedule to.</summary>
    [Parameter(Position = 2)]
    public object[]? Job { get; set; }

    /// <summary>The name of the schedule.</summary>
    [Parameter(Position = 3)]
    public object? Schedule { get; set; }

    /// <summary>Create the schedule in a disabled state.</summary>
    [Parameter]
    public SwitchParameter Disabled { get; set; }

    /// <summary>The overall frequency pattern for the schedule.</summary>
    [Parameter(Position = 4)]
    [ValidateSet("Once", "OneTime", "Daily", "Weekly", "Monthly", "MonthlyRelative", "AgentStart", "AutoStart", "IdleComputer", "OnIdle")]
    public object? FrequencyType { get; set; }

    /// <summary>The days or intervals the job runs, based on FrequencyType.</summary>
    [Parameter(Position = 5)]
    public object[]? FrequencyInterval { get; set; }

    /// <summary>The unit of time for running jobs multiple times within a day.</summary>
    [Parameter(Position = 6)]
    [ValidateSet("Once", "Time", "Seconds", "Second", "Minutes", "Minute", "Hours", "Hour")]
    public object? FrequencySubdayType { get; set; }

    /// <summary>How many subday units to wait between executions.</summary>
    [Parameter(Position = 7)]
    public int FrequencySubdayInterval { get; set; }

    /// <summary>Which occurrence within the month for MonthlyRelative schedules.</summary>
    [Parameter(Position = 8)]
    [ValidateSet("Unused", "First", "Second", "Third", "Fourth", "Last")]
    public object? FrequencyRelativeInterval { get; set; }

    /// <summary>The interval between occurrences for weekly/monthly schedules.</summary>
    [Parameter(Position = 9)]
    public int FrequencyRecurrenceFactor { get; set; }

    /// <summary>A natural-language schedule description.</summary>
    [Parameter(Position = 10)]
    public string? FrequencyText { get; set; }

    /// <summary>The earliest date the schedule becomes active (yyyyMMdd).</summary>
    [Parameter(Position = 11)]
    public string? StartDate { get; set; }

    /// <summary>The last date the schedule is active (yyyyMMdd).</summary>
    [Parameter(Position = 12)]
    public string? EndDate { get; set; }

    /// <summary>The daily start time (HHmmss).</summary>
    [Parameter(Position = 13)]
    public string? StartTime { get; set; }

    /// <summary>The daily end time (HHmmss).</summary>
    [Parameter(Position = 14)]
    public string? EndTime { get; set; }

    /// <summary>The owner login for the schedule.</summary>
    [Parameter(Position = 15)]
    public string? Owner { get; set; }

    /// <summary>Apply sensible defaults for unset parameters instead of erroring.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    private string _scheduleName = String.Empty;
    private int _frequencyType;
    private int _subdayType;
    private int _relativeInterval;
    private int _interval;
    private bool _useDefaults;
    private DateTime _activeStartDate;
    private DateTime _activeEndDate;
    private TimeSpan _activeStartTime;
    private TimeSpan _activeEndTime;
    private JobSchedule? _jobSchedule;

    protected override void BeginProcessing()
    {
        NormalizeSchedule();
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            _jobSchedule = null;
            Server? server = ConnectInstance(instance);
            if (server is null)
                continue;

            if (!ConfirmScheduleChange(instance, String.Format("Adding the schedule {0}", _scheduleName)))
                continue;
            if (!TryCreateSchedule(server, instance))
                continue;
            server.Refresh();
            server.JobServer.Refresh();
            server.JobServer.SharedSchedules.Refresh();
            UpdateScheduleCache(server);
            if (_jobSchedule is not null)
            {
                if (LanguagePrimitives.IsTrue(Job))
                    AttachSchedule(server, instance, _jobSchedule);
                WriteCurrentSchedule(server, _jobSchedule.ScheduleUid);
            }
        }
    }

    protected override void EndProcessing()
    {
        if (!Interrupted)
            WriteMessage(MessageLevel.Verbose, "Finished creating job schedule(s).");
    }

    private bool ConfirmScheduleChange(DbaInstanceParameter instance, string action)
    {
        if (!Force)
            return ShouldProcess(instance.ToString(), action);

        // FrequencyText enables defaults after the source's confirmation preference decision.
        return AgentConfirmation.WithConfirmationSuppressed(
            SessionState, () => ShouldProcess(instance.ToString(), action));
    }
}
