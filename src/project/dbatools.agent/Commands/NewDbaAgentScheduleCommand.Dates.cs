#nullable enable

using System;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;

namespace Dataplat.Dbatools.Commands;

public sealed partial class NewDbaAgentScheduleCommand
{
    private void NormalizeDatesAndTimes()
    {
        if (!TryDate(StartDate, "start", DateTime.Today.ToString("yyyyMMdd", CultureInfo.CurrentCulture), out string startDate, out _activeStartDate))
            return;
        StartDate = startDate;
        if (!TryDate(EndDate, "end", "99991231", out string endDate, out _activeEndDate))
            return;
        EndDate = endDate;
        if (_activeEndDate < _activeStartDate)
        {
            StopFunction(String.Format("End date {0} cannot be before start date {1}.", EndDate, StartDate), target: SqlInstance);
            return;
        }
        if (!TryTime(StartTime, "start", "000000", out string startTime, out _activeStartTime))
            return;
        StartTime = startTime;
        if (!TryTime(EndTime, "end", "235959", out string endTime, out _activeEndTime))
            return;
        EndTime = endTime;
    }

    private bool TryDate(string? supplied, string label, string defaultValue, out string text, out DateTime value)
    {
        value = default;
        if (!TryDefault(supplied, label, "date", defaultValue, out text))
            return false;
        try
        {
            // The pin consumes three substrings, permitting trailing text after yyyyMMdd.
            value = new DateTime(LanguagePrimitives.ConvertTo<int>(text.Substring(0, 4)),
                LanguagePrimitives.ConvertTo<int>(text.Substring(4, 2)), LanguagePrimitives.ConvertTo<int>(text.Substring(6, 2)));
            return true;
        }
        catch (Exception)
        {
            StopFunction(String.Format("{0} date {1} needs to be a valid date with format yyyyMMdd.", Capitalize(label), text), target: SqlInstance);
            return false;
        }
    }

    private bool TryTime(string? supplied, string label, string defaultValue, out string text, out TimeSpan value)
    {
        value = default;
        if (!TryDefault(supplied, label, "time", defaultValue, out text))
            return false;
        try
        {
            // TimeSpan normalizes overflow just as the source constructor does.
            value = new TimeSpan(LanguagePrimitives.ConvertTo<int>(text.Substring(0, 2)),
                LanguagePrimitives.ConvertTo<int>(text.Substring(2, 2)), LanguagePrimitives.ConvertTo<int>(text.Substring(4, 2)));
            return true;
        }
        catch (Exception)
        {
            StopFunction(String.Format("{0} time {1} needs to be a valid time with format HHmmss.", Capitalize(label), text), target: SqlInstance);
            return false;
        }
    }

    private bool TryDefault(string? supplied, string label, string kind, string defaultValue, out string text)
    {
        text = supplied ?? String.Empty;
        if (!String.IsNullOrEmpty(text))
            return true;
        if (!_useDefaults)
        {
            StopFunction(String.Format("Please enter {0} {1} {2} or use -Force to use defaults.", label == "end" ? "an" : "a", label, kind), target: SqlInstance);
            return false;
        }
        text = defaultValue;
        WriteMessage(MessageLevel.Verbose, String.Format("{0} {1} was not set. Force is being used. Setting it to {2}", Capitalize(label), kind, text));
        return true;
    }

    private static string Capitalize(string text)
    {
        return Char.ToUpperInvariant(text[0]) + text.Substring(1);
    }
}
