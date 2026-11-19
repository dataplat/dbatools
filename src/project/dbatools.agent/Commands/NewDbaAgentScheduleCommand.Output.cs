#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Management.Smo.Agent;

namespace Dataplat.Dbatools.Commands;

public sealed partial class NewDbaAgentScheduleCommand
{
    private void WriteCurrentSchedule(Server server, Guid scheduleUid)
    {
        // The source queries the current server by the retained UID instead of emitting the
        // old object directly when a later creation was declined.
        server.JobServer.SharedSchedules.Refresh();
        foreach (JobSchedule schedule in server.JobServer.SharedSchedules)
        {
            if (schedule.ScheduleUid != scheduleUid)
                continue;
            PSObject output = PSObject.AsPSObject(schedule);
            output.Properties.Remove("ComputerName");
            output.Properties.Remove("InstanceName");
            output.Properties.Remove("SqlInstance");
            output.Properties.Remove("Description");
            output.Properties.Remove("ScheduleName");
            OutputHelper.AddInstanceProperties(output, server);
            output.Properties.Add(new PSNoteProperty("Description", ScheduleDescription(schedule)));
            OutputHelper.AddAliasProperty(output, "ScheduleName", "Name");
            OutputHelper.SetDefaultDisplayPropertySet(output,
                "ComputerName", "InstanceName", "SqlInstance", "ScheduleName", "ActiveEndDate",
                "ActiveEndTimeOfDay", "ActiveStartDate", "ActiveStartTimeOfDay", "DateCreated",
                "FrequencyInterval", "FrequencyRecurrenceFactor", "FrequencyRelativeIntervals",
                "FrequencySubDayInterval", "FrequencySubDayTypes", "FrequencyTypes", "IsEnabled",
                "JobCount", "Description", "ScheduleUid");
            WriteObject(output);
        }
    }

    private static string ScheduleDescription(JobSchedule schedule)
    {
        CultureInfo culture = CultureInfo.CurrentCulture;
        DateTimeFormatInfo format = culture.DateTimeFormat;
        string startDate = schedule.ActiveStartDate.ToString(format.ShortDatePattern, culture);
        string endDate = schedule.ActiveEndDate.ToString(format.ShortDatePattern, culture);
        string startTime = DateTime.Today.Add(schedule.ActiveStartTimeOfDay).ToString(format.LongTimePattern, culture);
        string endTime = DateTime.Today.Add(schedule.ActiveEndTimeOfDay).ToString(format.LongTimePattern, culture);
        int frequency = (int)schedule.FrequencyTypes;
        StringBuilder description = new();
        switch (frequency)
        {
            case 1:
                description.AppendFormat("Occurs on {0} at {1}", startDate, startTime);
                break;
            case 4:
            case 8:
            case 16:
            case 32:
                description.Append("Occurs every ");
                break;
            case 64:
                return "Start automatically when SQL Server Agent starts ";
            case 128:
                return "Start whenever the CPUs become idle";
        }
        switch (frequency)
        {
            case 4:
                if (schedule.FrequencyInterval == 1)
                    description.Append("day ");
                else if (schedule.FrequencyInterval > 1)
                    description.AppendFormat("{0} day(s) ", schedule.FrequencyInterval);
                break;
            case 8:
                if (schedule.FrequencyRecurrenceFactor == 1)
                    description.Append("week on ");
                else if (schedule.FrequencyRecurrenceFactor > 1)
                    description.AppendFormat("{0} week(s) on ", schedule.FrequencyRecurrenceFactor);
                description.Append(WeeklyDays(schedule.FrequencyInterval));
                description.Append(' ');
                break;
            case 16:
                if (schedule.FrequencyRecurrenceFactor == 1)
                    description.Append("month ");
                else if (schedule.FrequencyRecurrenceFactor > 1)
                    description.AppendFormat("{0} month(s) ", schedule.FrequencyRecurrenceFactor);
                description.AppendFormat("on day {0} of that month ", schedule.FrequencyInterval);
                break;
            case 32:
                description.Append((int)schedule.FrequencyRelativeIntervals switch
                {
                    1 => "first ", 2 => "second ", 4 => "third ", 8 => "fourth ", 16 => "last ", _ => String.Empty
                });
                description.Append(schedule.FrequencyInterval switch
                {
                    1 => "Sunday ", 2 => "Monday ", 3 => "Tuesday ", 4 => "Wednesday ",
                    5 => "Thursday ", 6 => "Friday ", 7 => "Saturday ", 8 => "Day ",
                    9 => "Weekday ", 10 => "Weekend day ", _ => String.Empty
                });
                description.AppendFormat("of every {0} month(s) ", schedule.FrequencyRecurrenceFactor);
                break;
        }
        int subdayType = (int)schedule.FrequencySubDayTypes;
        if (subdayType == 0 || subdayType == 1)
            description.AppendFormat("at {0}. ", startTime);
        else
        {
            string unit = subdayType switch { 2 => "second", 4 => "minute", 8 => "hour", _ => String.Empty };
            if (unit.Length > 0)
                description.AppendFormat("every {0} {1}(s) ", schedule.FrequencySubDayInterval, unit);
            description.AppendFormat("between {0} and {1}. ", startTime, endTime);
        }
        if (schedule.ActiveEndDate.Year == 9999)
            description.AppendFormat("Schedule will be used starting on {0}.", startDate);
        else
            description.AppendFormat("Schedule will used between {0} and {1}.", startDate, endDate);
        return description.ToString();
    }

    private static string WeeklyDays(int interval)
    {
        List<string> days = new();
        string[] names = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" };
        int[] bits = { 2, 4, 8, 16, 32, 64, 1 };
        for (int index = 0; index < names.Length; index++)
            if (interval >= 127 || (interval & bits[index]) != 0)
                days.Add(names[index]);
        return String.Join(", ", days);
    }
}
