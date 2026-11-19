#nullable enable

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Escapes user-supplied (or WMI-discovered) values before they are embedded inside
/// single-quoted WQL/CIM query-string literals.
///
/// WQL has no parameter mechanism, so BP-101's SqlParameter remedy does not exist for WMI
/// queries — but the same failure mode does: a value containing a single quote breaks or
/// silently rewrites the predicate (WHERE ServiceName = 'O'Brien'), and Windows service names
/// legitimately allow quotes (only '/' and '\' are banned by the SCM). Per
/// migration/specs/best-practices.md BP-105, every value that lands in query text is routed
/// through this one shared helper — escaping is never inlined at the call site.
/// </summary>
internal static class WqlHelper
{
    /// <summary>
    /// Returns <paramref name="value"/> escaped for use inside a single-quoted WQL string
    /// literal. WQL escaping is backslash-based, so the order matters: escape backslash first
    /// ('\' -> '\\'), then the single quote ('\'' -> '\\''). A null or empty value passes
    /// through unchanged, and any value free of quotes and backslashes is returned byte-for-byte
    /// as-is. See BP-105.
    /// </summary>
    internal static string EscapeValue(string value)
    {
        if (string.IsNullOrEmpty(value))
        {
            return value;
        }

        return value.Replace("\\", "\\\\").Replace("'", "\\'");
    }
}
