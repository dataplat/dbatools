#nullable enable

using System;
using System.Globalization;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

internal static class AgentCategoryNames
{
    internal static bool Contains(string[]? names, string name)
    {
        foreach (string candidate in names ?? Array.Empty<string>())
        {
            if (LanguagePrimitives.Equals(candidate, name, true, CultureInfo.InvariantCulture))
                return true;
        }
        return false;
    }
}
