#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Management.Smo.Agent;
using SmoAgentJobSchedule = Microsoft.SqlServer.Management.Smo.Agent.JobSchedule;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves SQL Agent shared schedules with detailed timing and recurrence information.
/// </summary>
/// <para>
/// Retrieves all shared schedules from SQL Server Agent along with human-readable descriptions of their timing patterns. These shared schedules can be reused across multiple jobs to standardize maintenance windows and reduce schedule management overhead. The function provides filtering options by schedule name, unique identifier, or numeric ID, making it useful for schedule auditing, documentation, and troubleshooting automated job execution patterns.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentSchedule -SqlInstance localhost
/// </code>
/// <para>
/// Returns all SQL Agent Shared Schedules on the local default SQL Server instance
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentSchedule -SqlInstance localhost, sql2016
/// </code>
/// <para>
/// Returns all SQL Agent Shared Schedules for the local and sql2016 SQL Server instances
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentSchedule -SqlInstance localhost, sql2016 -Id 3
/// </code>
/// <para>
/// Returns the SQL Agent Shared Schedules with the Id of 3
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentSchedule -SqlInstance localhost, sql2016 -ScheduleUid 'bf57fa7e-7720-4936-85a0-87d279db7eb7'
/// </code>
/// <para>
/// Returns the SQL Agent Shared Schedules with the UID
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgentSchedule -SqlInstance sql2016 -Schedule "Maintenance10min","Maintenance60min"
/// </code>
/// <para>
/// Returns the "Maintenance10min" &amp; "Maintenance60min" schedules from the sql2016 SQL Server instance
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Agent, Schedule
/// Author: Chris McKeown (@devopsfu), devopsfu.com
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaAgentSchedule" />
[Cmdlet(VerbsCommon.Get, "DbaAgentSchedule")]
public sealed class GetDbaAgentScheduleCommand : DbaInstanceCmdlet
{
    // Positions follow the pinned function's automatic positional binding: every non-switch
    // parameter in declaration order.

    /// <para>
    /// The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.
    /// </para>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
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
    /// Specifies one or more schedule names to retrieve from the SQL Agent shared schedules collection.
    /// Use this when you need to examine specific schedules by their display names, such as checking timing details for maintenance windows or job execution patterns.
    /// Accepts multiple schedule names and supports wildcards for pattern matching.
    /// </para>
    [Parameter(Position = 2)]
    public string[]? Schedule { get; set; }

    /// <para>
    /// Specifies the GUID-based unique identifier of one or more shared schedules to retrieve.
    /// Use this when you need to target schedules by their immutable identifiers, particularly useful for automation scripts or when schedule names might change.
    /// Each shared schedule has a persistent UID that remains constant even if the schedule is renamed.
    /// </para>
    [Parameter(Position = 3)]
    public string[]? ScheduleUid { get; set; }

    /// <para>
    /// Specifies the numeric identifier of one or more shared schedules to retrieve from SQL Agent.
    /// Use this when you know the internal ID numbers of specific schedules, often obtained from previous queries or database system tables.
    /// Schedule IDs are assigned sequentially by SQL Server and remain constant unless the schedule is deleted and recreated.
    /// </para>
    [Parameter(Position = 4)]
    [PsAgentLogIntArrayCast]
    public int[]? Id { get; set; }

    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    // PS: $defaults, with "Name as ScheduleName" resolved by Select-DefaultView to the alias name.
    private static readonly string[] DefaultView =
    {
        "ComputerName", "InstanceName", "SqlInstance", "ScheduleName", "ActiveEndDate", "ActiveEndTimeOfDay",
        "ActiveStartDate", "ActiveStartTimeOfDay", "DateCreated", "FrequencyInterval", "FrequencyRecurrenceFactor",
        "FrequencyRelativeIntervals", "FrequencySubDayInterval", "FrequencySubDayTypes", "FrequencyTypes", "IsEnabled",
        "JobCount", "Description", "ScheduleUid",
    };

    // The pinned process block has no Test-FunctionInterrupt check; a Stop-Function -Continue
    // throws out of the command only under -EnableException.
    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential } catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            // Upstream correction azure-unsupported: SQL Server Agent and msdb do not exist in Azure SQL Database, so the
            // connection refuses it as Connect-DbaInstance -AzureUnsupported does instead of failing on the Agent read.
            Server? server = ConnectInstance(instance, "Failure", azureUnsupported: true);
            if (server is null)
            {
                continue;
            }

            // PS: if ($server.Edition -like 'Express*') { Stop-Function -Message "$($server.Edition) does not support SQL Server Agent. Skipping $server." -Continue }
            string? edition = server.Edition;
            if (edition is not null && edition.StartsWith("Express", StringComparison.OrdinalIgnoreCase))
            {
                StopFunction(edition + " does not support SQL Server Agent. Skipping " + server + ".", continueLoop: true);
                continue;
            }

            // PS: $server.JobServer.SharedSchedules.Refresh()
            JobServer jobServer = server.JobServer;
            jobServer.SharedSchedules.Refresh();

            // PS: if ($Schedule -or $ScheduleUid -or $Id) { each active filter appends its matches in collection order } else { the whole collection }
            List<SmoAgentJobSchedule> selected = new();
            bool byName = FilterHelper.IsActive(Schedule);
            bool byUid = FilterHelper.IsActive(ScheduleUid);
            bool byId = FilterHelper.IsActive(Id);
            if (byName || byUid || byId)
            {
                if (byName)
                {
                    // PS: Where-Object { $_.Name -in $Schedule }
                    // Upstream correction schedule-wildcards: the help documents wildcards for -Schedule, so a value with
                    // * or ? that is not the real name of a shared schedule also matches as a case-insensitive pattern
                    // (WildcardNameFilter, rule E+); every other value keeps the pinned -in comparison.
                    List<string> names = new();
                    foreach (SmoAgentJobSchedule schedule in jobServer.SharedSchedules)
                    {
                        names.Add(schedule.Name);
                    }
                    WildcardNameMatcher nameFilter = WildcardNameFilter.CreateMatcher(Schedule!, true, ScheduleNameEquals, names);
                    foreach (SmoAgentJobSchedule schedule in jobServer.SharedSchedules)
                    {
                        if (nameFilter.Matches(schedule.Name))
                        {
                            selected.Add(schedule);
                        }
                    }
                }
                if (byUid)
                {
                    // PS: Where-Object { $_.ScheduleUid -in $ScheduleUid } - each string -eq the Guid, compared as text.
                    foreach (SmoAgentJobSchedule schedule in jobServer.SharedSchedules)
                    {
                        if (ContainsValue(ScheduleUid!, schedule.ScheduleUid))
                        {
                            selected.Add(schedule);
                        }
                    }
                }
                if (byId)
                {
                    // PS: Where-Object { $_.Id -in $Id }
                    foreach (SmoAgentJobSchedule schedule in jobServer.SharedSchedules)
                    {
                        if (Array.IndexOf(Id!, schedule.ID) >= 0)
                        {
                            selected.Add(schedule);
                        }
                    }
                }
            }
            else
            {
                foreach (SmoAgentJobSchedule schedule in jobServer.SharedSchedules)
                {
                    selected.Add(schedule);
                }
            }

            foreach (SmoAgentJobSchedule schedule in selected)
            {
                string description = GetScheduleDescription(schedule);

                // PS: Add-Member -Force for ComputerName, InstanceName, SqlInstance and Description, then
                // Select-DefaultView, whose "Name as ScheduleName" adds the alias with Add-Member -Force.
                PSObject output = PSObject.AsPSObject(schedule);
                foreach (string name in new[] { "ComputerName", "InstanceName", "SqlInstance", "Description", "ScheduleName" })
                {
                    output.Properties.Remove(name);
                }
                OutputHelper.AddInstanceProperties(output, server);
                output.Properties.Add(new PSNoteProperty("Description", description));
                OutputHelper.AddAliasProperty(output, "ScheduleName", "Name");
                OutputHelper.SetDefaultDisplayPropertySet(output, DefaultView);
                WriteObject(output);
            }
        }
    }

    // PS: $value -in $values is $item -eq $value for each item, the item on the left: a string item
    // compares the value as text, case-insensitively.
    private static bool ContainsValue(string[] values, object? value)
    {
        foreach (string item in values)
        {
            if (LanguagePrimitives.Equals(item, value, true, CultureInfo.InvariantCulture))
            {
                return true;
            }
        }
        return false;
    }

    // The pinned -in comparison of one -Schedule value and a schedule name.
    private static bool ScheduleNameEquals(object? value, string name)
    {
        return LanguagePrimitives.Equals(value, name, true, CultureInfo.InvariantCulture);
    }

    // PS: the begin block's Get-ScheduleDescription, clause by clause.
    private static string GetScheduleDescription(SmoAgentJobSchedule schedule)
    {
        // PS: $datetimeFormat = (Get-Culture).DateTimeFormat; Get-Date ... -Format formats with the current culture.
        CultureInfo culture = CultureInfo.CurrentCulture;
        DateTimeFormatInfo format = culture.DateTimeFormat;
        string startDate = schedule.ActiveStartDate.ToString(format.ShortDatePattern, culture);
        string startTime = TimeOfDay(schedule.ActiveStartTimeOfDay, format, culture);
        string endDate = schedule.ActiveEndDate.ToString(format.ShortDatePattern, culture);
        string endTime = TimeOfDay(schedule.ActiveEndTimeOfDay, format, culture);

        int frequencyType = (int)schedule.FrequencyTypes;
        int interval = schedule.FrequencyInterval;
        int recurrence = schedule.FrequencyRecurrenceFactor;
        StringBuilder description = new();

        // PS: the first switch on FrequencyTypes.
        if (frequencyType == 1)
        {
            description.Append("Occurs on " + startDate + " at " + startTime);
        }
        if (frequencyType == 4 || frequencyType == 8 || frequencyType == 16 || frequencyType == 32)
        {
            description.Append("Occurs every ");
        }
        if (frequencyType == 64)
        {
            description.Append("Start automatically when SQL Server Agent starts ");
        }
        if (frequencyType == 128)
        {
            description.Append("Start whenever the CPUs become idle");
        }

        // PS: the second switch on FrequencyTypes.
        if (frequencyType == 4)
        {
            if (interval == 1)
            {
                description.Append("day ");
            }
            else if (interval > 1)
            {
                description.Append(Text(interval) + " day(s) ");
            }
        }
        if (frequencyType == 8)
        {
            if (recurrence == 1)
            {
                description.Append("week on ");
            }
            else if (recurrence > 1)
            {
                description.Append(Text(recurrence) + " week(s) on ");
            }
            description.Append(WeekDays(interval));
            description.Append(' ');
        }
        if (frequencyType == 16)
        {
            if (recurrence == 1)
            {
                description.Append("month ");
            }
            else if (recurrence > 1)
            {
                description.Append(Text(recurrence) + " month(s) ");
            }
            description.Append("on day " + Text(interval) + " of that month ");
        }
        if (frequencyType == 32)
        {
            switch ((int)schedule.FrequencyRelativeIntervals)
            {
                case 1: description.Append("first "); break;
                case 2: description.Append("second "); break;
                case 4: description.Append("third "); break;
                case 8: description.Append("fourth "); break;
                case 16: description.Append("last "); break;
            }
            switch (interval)
            {
                case 1: description.Append("Sunday "); break;
                case 2: description.Append("Monday "); break;
                case 3: description.Append("Tuesday "); break;
                case 4: description.Append("Wednesday "); break;
                case 5: description.Append("Thursday "); break;
                case 6: description.Append("Friday "); break;
                case 7: description.Append("Saturday "); break;
                case 8: description.Append("Day "); break;
                case 9: description.Append("Weekday "); break;
                case 10: description.Append("Weekend day "); break;
            }
            description.Append("of every " + Text(recurrence) + " month(s) ");
        }

        // PS: if ($currentschedule.FrequencyTypes -notin 64, 128) { ... }
        if (frequencyType != 64 && frequencyType != 128)
        {
            int subDayType = (int)schedule.FrequencySubDayTypes;
            if (subDayType == 0 || subDayType == 1)
            {
                description.Append("at " + startTime + ". ");
            }
            else
            {
                string subDayInterval = Text(schedule.FrequencySubDayInterval);
                switch (subDayType)
                {
                    case 2: description.Append("every " + subDayInterval + " second(s) "); break;
                    case 4: description.Append("every " + subDayInterval + " minute(s) "); break;
                    case 8: description.Append("every " + subDayInterval + " hour(s) "); break;
                }
                description.Append("between " + startTime + " and " + endTime + ". ");
            }

            if (schedule.ActiveEndDate.Year == 9999)
            {
                description.Append("Schedule will be used starting on " + startDate + ".");
            }
            else
            {
                description.Append("Schedule will used between " + startDate + " and " + endDate + ".");
            }
        }

        return description.ToString();
    }

    // PS: Get-Date ($timeOfDay.ToString()) -Format $datetimeFormat.LongTimePattern - the "hh:mm:ss" text binds
    // to -Date as that time today.
    private static string TimeOfDay(TimeSpan timeOfDay, DateTimeFormatInfo format, CultureInfo culture)
    {
        return DateTime.Today.Add(timeOfDay).ToString(format.LongTimePattern, culture);
    }

    // PS: the weekly while/switch (1) loop: each pass takes every remaining bit from 64 down to 1 in turn,
    // then the named days are joined in Monday-to-Sunday array order.
    private static string WeekDays(int frequencyInterval)
    {
        string?[] days = new string?[7];
        int remaining = frequencyInterval;
        while (remaining > 0)
        {
            if (remaining - 64 >= 0) { days[5] = "Saturday"; remaining -= 64; }
            if (remaining - 32 >= 0) { days[4] = "Friday"; remaining -= 32; }
            if (remaining - 16 >= 0) { days[3] = "Thursday"; remaining -= 16; }
            if (remaining - 8 >= 0) { days[2] = "Wednesday"; remaining -= 8; }
            if (remaining - 4 >= 0) { days[1] = "Tuesday"; remaining -= 4; }
            if (remaining - 2 >= 0) { days[0] = "Monday"; remaining -= 2; }
            if (remaining - 1 >= 0) { days[6] = "Sunday"; remaining -= 1; }
        }

        List<string> named = new();
        foreach (string? day in days)
        {
            if (day is not null)
            {
                named.Add(day);
            }
        }
        return string.Join(", ", named);
    }

    // PS: "$(...)" of an int.
    private static string Text(int value)
    {
        return value.ToString(CultureInfo.InvariantCulture);
    }
}
