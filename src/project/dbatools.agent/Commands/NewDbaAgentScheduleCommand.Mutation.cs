#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.TabExpansion;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Management.Smo.Agent;
using AgentJob = Microsoft.SqlServer.Management.Smo.Agent.Job;

namespace Dataplat.Dbatools.Commands;

public sealed partial class NewDbaAgentScheduleCommand
{
    private bool TryCreateSchedule(Server server, DbaInstanceParameter instance)
    {
        bool constructing = true;
        try
        {
            WriteMessage(MessageLevel.Verbose, String.Format("Adding the schedule {0} on instance {1}", _jobSchedule, instance));
            _jobSchedule = new JobSchedule(server.JobServer, _scheduleName);
            constructing = false;
            WriteMessage(MessageLevel.Verbose, Disabled ? "Setting job schedule to disabled" : "Setting job schedule to enabled");
            _jobSchedule.IsEnabled = !Disabled;
            if (_interval >= 1)
            {
                WriteMessage(MessageLevel.Verbose, String.Format("Setting job schedule frequency interval to {0}", _interval));
                _jobSchedule.FrequencyInterval = _interval;
            }
            if (_frequencyType >= 1)
            {
                WriteMessage(MessageLevel.Verbose, String.Format("Setting job schedule frequency to {0}", _frequencyType));
                _jobSchedule.FrequencyTypes = (FrequencyTypes)_frequencyType;
            }
            if (_subdayType >= 1)
            {
                WriteMessage(MessageLevel.Verbose, String.Format("Setting job schedule frequency subday type to {0}", _subdayType));
                _jobSchedule.FrequencySubDayTypes = (FrequencySubDayTypes)_subdayType;
            }
            if (FrequencySubdayInterval >= 1)
            {
                WriteMessage(MessageLevel.Verbose, String.Format("Setting job schedule frequency subday interval to {0}", FrequencySubdayInterval));
                _jobSchedule.FrequencySubDayInterval = FrequencySubdayInterval;
            }
            if (_relativeInterval >= 1 && _frequencyType == 32)
            {
                WriteMessage(MessageLevel.Verbose, String.Format("Setting job schedule frequency relative interval to {0}", _relativeInterval));
                _jobSchedule.FrequencyRelativeIntervals = (FrequencyRelativeIntervals)_relativeInterval;
            }
            if (FrequencyRecurrenceFactor >= 1 && (_frequencyType == 8 || _frequencyType == 16 || _frequencyType == 32))
            {
                WriteMessage(MessageLevel.Verbose, String.Format("Setting job schedule frequency recurrence factor to {0}", FrequencyRecurrenceFactor));
                _jobSchedule.FrequencyRecurrenceFactor = FrequencyRecurrenceFactor;
            }
            WriteMessage(MessageLevel.Verbose, String.Format("Setting job schedule start date to {0} / {1}", StartDate, _activeStartDate));
            _jobSchedule.ActiveStartDate = _activeStartDate;
            WriteMessage(MessageLevel.Verbose, String.Format("Setting job schedule end date to {0} / {1}", EndDate, _activeEndDate));
            _jobSchedule.ActiveEndDate = _activeEndDate;
            WriteMessage(MessageLevel.Verbose, String.Format("Setting job schedule start time to {0} / {1}", StartTime, _activeStartTime));
            _jobSchedule.ActiveStartTimeOfDay = _activeStartTime;
            WriteMessage(MessageLevel.Verbose, String.Format("Setting job schedule end time to {0} / {1}", EndTime, _activeEndTime));
            _jobSchedule.ActiveEndTimeOfDay = _activeEndTime;
            if (!String.IsNullOrEmpty(Owner))
                _jobSchedule.OwnerLoginName = Owner;
            _jobSchedule.Create();
            WriteMessage(MessageLevel.Verbose, String.Format("Job schedule created with UID {0}", _jobSchedule.ScheduleUid));
            return true;
        }
        catch (Exception exception) when (exception is not PipelineStoppedException)
        {
            string message = constructing && exception.Message.IndexOf("newParent", StringComparison.OrdinalIgnoreCase) >= 0
                ? "Cannot create agent schedule through a contained availability group listener. SQL Server Agent objects are instance-level and must be managed on the instance directly. Please connect to the primary replica instead of the listener. Use Get-DbaAvailabilityGroup to find the current primary replica."
                : "Something went wrong adding the schedule.";
            ErrorRecord record = new(exception, "dbatools_New-DbaAgentSchedule", ErrorCategory.NotSpecified, instance);
            StopFunction(message, target: instance, errorRecord: record, continueLoop: true);
            return false;
        }
    }

    private void AttachSchedule(Server server, DbaInstanceParameter instance, JobSchedule schedule)
    {
        HashSet<string> requestedJobs = new(StringComparer.OrdinalIgnoreCase);
        foreach (object supplied in Job!)
        {
            string name = Text(supplied);
            if (!String.IsNullOrWhiteSpace(name))
                requestedJobs.Add(name);
        }
        if (requestedJobs.Count == 0)
        {
            WriteAttributedMessage("Get-DbaAgentJob", MessageLevel.Verbose, "The -Job parameter was explicitly provided but contains only null, empty, or whitespace values. No jobs will be returned.");
            return;
        }
        foreach (AgentJob job in server.JobServer.Jobs)
        {
            if ((job.JobType != JobType.Local && job.JobType != JobType.MultiServer) || !requestedJobs.Contains(job.Name))
                continue;
            if (!ConfirmScheduleChange(instance, String.Format("Adding the schedule {0} to job {1}", _scheduleName, job.Name)))
                continue;
            WriteMessage(MessageLevel.Verbose, String.Format("Adding schedule {0} to job {1}", _scheduleName, job.Name));
            ReportMethodCall(() => job.AddSharedSchedule(schedule.ID), "AddSharedSchedule", 1);
            ReportMethodCall(schedule.Refresh, "Refresh", 0);
        }
    }

    private void ReportMethodCall(Action action, string method, int argumentCount)
    {
        try
        {
            action();
        }
        catch (Exception exception) when (exception is not PipelineStoppedException)
        {
            // These source method calls are outside Stop-Function's warning/exception policy.
            MethodInvocationException invocation = new(String.Format("Exception calling \"{0}\" with \"{1}\" argument(s): \"{2}\"", method, argumentCount, exception.Message), exception);
            WriteError(new ErrorRecord(invocation, exception.GetType().Name, ErrorCategory.NotSpecified, null));
        }
    }

    private void UpdateScheduleCache(Server server)
    {
        string serverName = server.Name.ToLowerInvariant();
        try
        {
            IDictionary? cache = TabExpansionHost.Cache["schedule"] as IDictionary;
            if (cache is null || !cache.Contains(serverName))
            {
                WriteAttributedMessage("Add-TeppCacheItem", MessageLevel.Debug, String.Format("No cache for {0} found.", serverName));
                return;
            }
            List<string> names = new();
            object? cached = cache[serverName];
            if (cached is IEnumerable items && cached is not string)
            {
                foreach (object item in items)
                    names.Add(Text(item));
            }
            else if (cached is not null)
                names.Add(Text(cached));
            foreach (string name in names)
            {
                if (!String.Equals(name, _scheduleName, StringComparison.OrdinalIgnoreCase))
                    continue;
                WriteAttributedMessage("Add-TeppCacheItem", MessageLevel.Debug, String.Format("{0} already in cache for schedule on {1}.", _scheduleName, serverName));
                return;
            }
            names.Add(_scheduleName);
            names.Sort(StringComparer.Create(CultureInfo.CurrentCulture, true));
            cache[serverName] = names.Count == 1 ? (object)names[0] : names.ToArray();
            WriteAttributedMessage("Add-TeppCacheItem", MessageLevel.Debug, String.Format("{0} added to cache for schedule on {1}.", _scheduleName, serverName));
        }
        catch (Exception exception) when (exception is not PipelineStoppedException)
        {
            WriteAttributedMessage("Add-TeppCacheItem", MessageLevel.Debug, String.Format("Failed to add {0} to cache for schedule on {1}. {2}", _scheduleName, serverName, exception.Message));
        }
    }
}
