#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Commands;

/// <summary>Name filters shared by the native Agent commands.</summary>
internal static class AgentNameFilter
{
    /// <summary>
    /// Matches PowerShell's <c>$name -in $names</c>: exact, case-insensitive, no wildcards.
    /// </summary>
    internal static bool ContainsName(string[]? names, string name)
    {
        foreach (string candidate in names ?? Array.Empty<string>())
        {
            if (NameEquals(candidate, name))
                return true;
        }
        return false;
    }

    /// <summary>
    /// The ContainsName comparison, plus documented wildcard patterns (rule E+) when
    /// allowPatterns is set; scope lists every object name of the unfiltered collection.
    /// </summary>
    internal static WildcardNameMatcher CreateMatcher(string[]? names, bool allowPatterns, IEnumerable<string>? scope)
    {
        return WildcardNameFilter.CreateMatcher(names, allowPatterns, NameEquals, scope);
    }

    private static bool NameEquals(object candidate, string name)
    {
        return LanguagePrimitives.Equals(candidate, name, true, CultureInfo.InvariantCulture);
    }
}
