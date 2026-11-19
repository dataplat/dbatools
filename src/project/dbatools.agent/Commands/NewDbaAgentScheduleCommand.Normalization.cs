#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Message;

namespace Dataplat.Dbatools.Commands;

public sealed partial class NewDbaAgentScheduleCommand
{
    private void NormalizeSchedule()
    {
        _useDefaults = Force.ToBool();
        if (!String.IsNullOrEmpty(FrequencyText) && !ParseFrequencyText())
            return;

        if (String.Equals(Text(FrequencyType), "Daily", StringComparison.OrdinalIgnoreCase) && !LanguagePrimitives.IsTrue(FrequencyInterval))
            FrequencyInterval = new object[] { 1 };
        if (!LanguagePrimitives.IsTrue(Schedule))
        {
            StopFunction("A schedule was not provided! Please provide a schedule name.");
            return;
        }
        _scheduleName = Text(Schedule);
        _frequencyType = Text(FrequencyType).ToLowerInvariant() switch
        {
            "daily" => 4, "weekly" => 8, "monthly" => 16, "monthlyrelative" => 32,
            "agentstart" or "autostart" => 64, "idlecomputer" or "onidle" => 128, _ => 1
        };
        _subdayType = Text(FrequencySubdayType).ToLowerInvariant() switch
        {
            "seconds" or "second" => 2, "minutes" or "minute" => 4,
            "hours" or "hour" => 8, _ => 1
        };
        _relativeInterval = Text(FrequencyRelativeInterval).ToLowerInvariant() switch
        {
            "first" => 1, "second" => 2, "third" => 4, "fourth" => 8, "last" => 16, _ => 0
        };

        if (_frequencyType == 4 &&
            (FilteredIntervalIsTrue(item => LanguagePrimitives.Compare(item, 1, true, CultureInfo.InvariantCulture) < 0) ||
             FilteredIntervalIsTrue(item => LanguagePrimitives.Compare(item, 365, true, CultureInfo.InvariantCulture) >= 0)) &&
            !FilteredIntervalIsTrue(item => LanguagePrimitives.Equals(item, "EveryDay", true, CultureInfo.InvariantCulture)) && !_useDefaults)
        {
            StopFunction("The daily frequency type requires a frequency interval to be between 1 and 365 or 'EveryDay'.", target: SqlInstance);
            return;
        }
        if ((_frequencyType == 16 || _frequencyType == 8) && FrequencyRecurrenceFactor < 1)
        {
            if (!_useDefaults)
            {
                StopFunction(String.Format("The recurrence factor {0} (parameter FrequencyRecurrenceFactor) needs to be at least one when using a weekly or monthly interval.", FrequencyRecurrenceFactor), target: SqlInstance);
                return;
            }
            FrequencyRecurrenceFactor = 1;
            WriteMessage(MessageLevel.Verbose, "Recurrence factor not set for weekly or monthly interval. Setting it to 1.");
        }

        // The pin's subday predicates never reject: its numeric OR ranges are exhaustive,
        // and its hours branch compares a scalar with an array. SQL still validates Create().
        NormalizeInterval();
        if ((_frequencyType == 4 || _frequencyType == 8 || _frequencyType == 32) && _interval < 1)
        {
            if (!_useDefaults)
            {
                StopFunction("Parameter FrequencyInterval must be provided for a recurring schedule.", target: SqlInstance);
                return;
            }
            WriteMessage(MessageLevel.Warning, "Parameter FrequencyInterval must be provided for a recurring schedule. Setting it to first day of the week.");
            _interval = 1;
        }
        NormalizeDatesAndTimes();
    }

    private bool ParseFrequencyText()
    {
        Match match = Regex.Match(FrequencyText!, @"every(\s+(?<interval>\d+))?\s+(?<unit>minute|hour|day|sunday|monday|tuesday|wednesday|thursday|friday|saturday)s?(\s+starting)?(\s+at\s+(?<start>\d\d:\d\d:\d\d))?", RegexOptions.IgnoreCase);
        if (!match.Success)
        {
            StopFunction("FrequencyText can not be parsed.");
            return false;
        }
        string unit = match.Groups["unit"].Value.ToLowerInvariant();
        if (unit == "minute" || unit == "hour" || unit == "day")
        {
            FrequencyType = "Daily";
            if (unit == "minute" || unit == "hour")
            {
                FrequencySubdayType = unit;
                FrequencySubdayInterval = match.Groups["interval"].Success
                    ? LanguagePrimitives.ConvertTo<int>(match.Groups["interval"].Value) : 1;
            }
        }
        else
        {
            FrequencyType = "Weekly";
            FrequencyInterval = new object[] { unit };
        }
        if (match.Groups["start"].Success)
            StartTime = match.Groups["start"].Value.Replace(":", String.Empty);
        if (!LanguagePrimitives.IsTrue(Schedule))
            Schedule = FrequencyText;
        _useDefaults = true;
        return true;
    }

    private void NormalizeInterval()
    {
        if (_frequencyType == 4)
        {
            _interval = 1;
            if (LanguagePrimitives.IsTrue(FrequencyInterval))
            {
                object first = FrequencyInterval![0];
                if (first is PSObject wrapped)
                    first = wrapped.BaseObject;
                if (first is int interval)
                    _interval = interval;
            }
            return;
        }
        foreach (object item in FrequencyInterval ?? Array.Empty<object>())
        {
            string value = Text(item).ToLowerInvariant();
            if (_frequencyType == 8)
            {
                int day = value switch
                {
                    "sunday" or "1" => 1, "monday" or "2" => 2, "tuesday" or "4" => 4,
                    "wednesday" or "8" => 8, "thursday" or "16" => 16,
                    "friday" or "32" => 32, "saturday" or "64" => 64, _ => 0
                };
                if (day > 0)
                    _interval += day;
                else
                    _interval = value switch
                    {
                        "weekdays" or "62" => 62, "weekend" or "65" => 65,
                        "everyday" or "127" => 127, "120" => 120, "121" => 121,
                        "122" => 122, "123" => 123, "124" => 124, "125" => 125, "126" => 126, _ => 0
                    };
            }
            else if (_frequencyType == 16)
            {
                int day = LanguagePrimitives.ConvertTo<int>(item);
                if (day >= 1 && day <= 31)
                    _interval = day;
            }
            else if (_frequencyType == 32)
            {
                _interval += value switch
                {
                    "sunday" or "1" => 1, "monday" or "2" => 2, "tuesday" or "3" => 3,
                    "wednesday" or "4" => 4, "thursday" or "5" => 5, "friday" or "6" => 6,
                    "saturday" or "7" => 7, "day" or "8" => 8,
                    "weekdays" or "9" => 9, "weekendday" or "10" => 10, _ => 0
                };
            }
        }
    }

    private bool FilteredIntervalIsTrue(Func<object, bool> predicate)
    {
        // Comparison operators filter collections; even a matching single zero is false.
        List<object> matches = new();
        foreach (object value in FrequencyInterval ?? Array.Empty<object>())
            if (predicate(value))
                matches.Add(value);
        return LanguagePrimitives.IsTrue(matches.ToArray());
    }

    private static string Text(object? value)
    {
        return LanguagePrimitives.ConvertTo<string>(value);
    }
}
