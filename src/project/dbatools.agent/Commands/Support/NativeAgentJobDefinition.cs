#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using Microsoft.SqlServer.Management.Smo.Agent;

namespace Dataplat.Dbatools.Commands;

/// <summary>The four definition sections used by the pinned Get-AgentJobFingerprint helper.</summary>
internal static class NativeAgentJobDefinition
{
    internal static string[] Snapshot(Job job, string? owner = null, bool? enabled = null)
    {
        string properties = string.Join("\n", new[]
        {
            "Owner=" + (string.IsNullOrEmpty(owner) ? job.OwnerLoginName : owner),
            "Category=" + job.Category,
            "Description=" + Normalize(job.Description),
            "StartStepID=" + Text(job.StartStepID),
            "EmailLevel=" + Text(job.EmailLevel),
            "OperatorToEmail=" + job.OperatorToEmail,
            "PageLevel=" + Text(job.PageLevel),
            "OperatorToPage=" + job.OperatorToPage,
            "NetSendLevel=" + Text(job.NetSendLevel),
            "OperatorToNetSend=" + job.OperatorToNetSend,
            "EventLogLevel=" + Text(job.EventLogLevel),
            "DeleteLevel=" + Text(job.DeleteLevel)
        });
        List<string> steps = new List<string>();
        foreach (JobStep step in job.JobSteps.Cast<JobStep>().OrderBy(value => value.ID))
        {
            steps.Add(string.Join("\n", new[]
            {
                "ID=" + Text(step.ID), "Name=" + step.Name,
                "SubSystem=" + Text(step.SubSystem), "Command=" + Normalize(step.Command),
                "DatabaseName=" + step.DatabaseName, "DatabaseUserName=" + step.DatabaseUserName,
                "Server=" + step.Server,
                "ProxyName=" + (job.Parent.Parent.VersionMajor >= 9 ? step.ProxyName : ""),
                "OnSuccessAction=" + Text(step.OnSuccessAction), "OnSuccessStep=" + Text(step.OnSuccessStep),
                "OnFailAction=" + Text(step.OnFailAction), "OnFailStep=" + Text(step.OnFailStep),
                "RetryAttempts=" + Text(step.RetryAttempts), "RetryInterval=" + Text(step.RetryInterval),
                "OutputFileName=" + step.OutputFileName, "JobStepFlags=" + Text(step.JobStepFlags),
                "CommandExecutionSuccessCode=" + Text(step.CommandExecutionSuccessCode),
                "OSRunPriority=" + Text(step.OSRunPriority)
            }));
        }
        List<string> schedules = new List<string>();
        foreach (JobSchedule schedule in job.JobSchedules)
        {
            schedules.Add(string.Join("\n", new[]
            {
                "Name=" + schedule.Name, "IsEnabled=" + Text(schedule.IsEnabled),
                "FrequencyTypes=" + Text(schedule.FrequencyTypes), "FrequencyInterval=" + Text(schedule.FrequencyInterval),
                "FrequencySubDayTypes=" + Text(schedule.FrequencySubDayTypes),
                "FrequencySubDayInterval=" + Text(schedule.FrequencySubDayInterval),
                "FrequencyRelativeIntervals=" + Text(schedule.FrequencyRelativeIntervals),
                "FrequencyRecurrenceFactor=" + Text(schedule.FrequencyRecurrenceFactor),
                "ActiveStartDate=" + schedule.ActiveStartDate.ToString("yyyyMMdd", CultureInfo.CurrentCulture),
                "ActiveEndDate=" + schedule.ActiveEndDate.ToString("yyyyMMdd", CultureInfo.CurrentCulture),
                "ActiveStartTimeOfDay=" + Text(schedule.ActiveStartTimeOfDay),
                "ActiveEndTimeOfDay=" + Text(schedule.ActiveEndTimeOfDay)
            }));
        }
        return new[]
        {
            properties, "IsEnabled=" + Text(enabled ?? job.IsEnabled),
            string.Join("\n--\n", steps),
            string.Join("\n--\n", schedules.OrderBy(value => value, StringComparer.CurrentCultureIgnoreCase))
        };
    }

    private static string Normalize(string value) => value.Replace("\r\n", "\n").TrimEnd();
    private static string Text(object value) => Convert.ToString(value, CultureInfo.InvariantCulture) ?? "";
}
