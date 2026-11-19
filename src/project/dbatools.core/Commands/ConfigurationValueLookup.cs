#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Configuration;

namespace Dataplat.Dbatools.Commands;

/// <summary>Shared value lookup for the configuration-value and managed-path getters.</summary>
internal static class ConfigurationValueLookup
{
    internal static object? Read(string fullName, PSCmdlet? caller = null)
    {
        object? value = null;
        if (ConfigurationHost.Configurations.TryGetValue(fullName.ToLowerInvariant(), out Config? config) && config is not null)
            value = config.Value;
        if (value is null)
            return null;

        // Preserve the pinned helper's sequential method calls. The second call
        // sees the Boolean produced by the first conversion when it matches.
        if (MatchesSwitchValue(value, "Mandatory", caller))
            value = true;
        if (MatchesSwitchValue(value, "Optional", caller))
            value = false;
        return value;
    }

    private static bool MatchesSwitchValue(object value, string expected, PSCmdlet? caller)
    {
        try
        {
            PSObject wrapped = PSObject.AsPSObject(value);
            PSMethodInfo? method = wrapped.Methods["ToString"];
            // The two comparisons at pinned :73-74 call only this stored value's own ToString.
            object? result = method is PSScriptMethod || method is PSCodeMethod
                ? method.Invoke() : wrapped.BaseObject.ToString();
            if (result is string text)
                return string.Equals(text, expected, StringComparison.InvariantCultureIgnoreCase);

            if (LanguagePrimitives.GetEnumerable(result) is not IEnumerable items)
                return LanguagePrimitives.Equals(result, expected, true, CultureInfo.InvariantCulture);

            // With a collection on the left, PowerShell -eq returns the matching items.
            List<object?> matches = new();
            foreach (object? item in items)
                if (LanguagePrimitives.Equals(item, expected, true, CultureInfo.InvariantCulture)) matches.Add(item);
            return LanguagePrimitives.IsTrue(matches.ToArray());
        }
        catch (Exception failure) when (caller is not null && failure is not PipelineStoppedException)
        {
            // caller-try: a fault at either pinned if unwinds a caller try or resumes at the next statement.
            ErrorRecord record = failure is MethodInvocationException methodFault
                ? new ErrorRecord(methodFault.ErrorRecord, methodFault)
                : StatementFault.Record(failure, "MethodInvocationException");
            StatementFault.Surface(caller, record);
            return false;
        }
    }
}
