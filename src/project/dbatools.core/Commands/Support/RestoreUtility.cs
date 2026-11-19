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

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Result shape of Convert-DbaLSN: both representations of the input LSN.
/// </summary>
internal sealed class LsnConversion
{
    public string? Hexadecimal;
    public string? Numeric;
}

/// <summary>
/// Ports of the small private helpers the restore ecosystem calls:
/// Get-DbaPathSep, Convert-DbVersionToSqlVersion, Convert-DbaLSN, Add-TeppCacheItem,
/// plus the PS-semantics coercion helpers the ports lean on (null-to-empty string
/// parameters, array-to-string field assignment).
/// </summary>
internal static class RestoreUtility
{
    /// <summary>
    /// Port of private/functions/Get-DbaPathSep.ps1: the instance path separator, if
    /// exists, or the default one. Over every input the Server? signature can carry,
    /// IsNullOrEmpty matches the source's Length-eq-0 test: PowerShell special-cases
    /// Length on $null (0 since v3), so a null server, a null separator and an empty
    /// separator all take the default there too - probed on both editions. (The
    /// source's [object] parameter additionally admits non-string separators with
    /// their own Length semantics; no caller in either world produces one.) On a
    /// disconnected server the separator read fails BEFORE the default logic in both
    /// worlds - each surfaces its own wrapper type there, unreachable from the
    /// shipped call sites, which all pass a connected server.
    /// </summary>
    internal static string GetPathSep(Server? server)
    {
        string? pathSep = server?.PathSeparator;
        if (string.IsNullOrEmpty(pathSep))
            pathSep = "\\";
        return pathSep!;
    }

    /// <summary>
    /// Port of private/functions/Convert-DbVersionToSqlVersion.ps1: makes db versions
    /// human readable. Unknown versions fall through unchanged, exactly like the PS switch
    /// default. The case labels are QUOTED STRINGS on purpose: the PS switch compares its
    /// integer case literals against the [string] subject with the SUBJECT's type winning,
    /// so only exact digit strings match — "0869", " 869" and "869 " pass through verbatim
    /// (a numeric-parse or trimming rewrite diverges; the TB-014 pins fail it).
    /// </summary>
    internal static string ConvertDbVersionToSqlVersion(string? dbversion)
    {
        // PS binding parity (opus TB-014): an unbound/null-bound [string] is empty in PS,
        // never null — PsString on entry per this file's convention (see PsString doc).
        dbversion = PsString(dbversion);
        return dbversion switch
        {
            "869" => "SQL Server 2017",
            "856" => "SQL Server vNext CTP1",
            "852" => "SQL Server 2016",
            "829" => "SQL Server 2016 Prerelease",
            "782" => "SQL Server 2014",
            "706" => "SQL Server 2012",
            "684" => "SQL Server 2012 CTP1",
            "661" => "SQL Server 2008 R2",
            "660" => "SQL Server 2008 R2",
            "655" => "SQL Server 2008 SP2+",
            "612" => "SQL Server 2005",
            "611" => "SQL Server 2005",
            "539" => "SQL Server 2000",
            "515" => "SQL Server 7.0",
            "408" => "SQL Server 6.5",
            _ => dbversion
        };
    }

    /// <summary>
    /// Port of private/functions/Convert-DbaLSN.ps1. Only the hexadecimal-to-numeric branch
    /// is reachable from the restore ecosystem (Invoke-DbaAdvancedRestore pre-filters pure
    /// numerics), but the numeric-to-hexadecimal branch is carried too, byte-for-byte with
    /// the PS quirks: the string-to-long coercion PS applies inside
    /// [System.Convert]::ToString($str, 16), the len-14 substring off-by-one, and PadLeft
    /// AFTER the base conversion. Returns null after the Stop-Function site fired
    /// (non-EnableException); throws InnerCommandException under EnableException.
    /// Documented divergence (opus TB-011): when a numeric section overflows Int64 the PS
    /// binder raises MethodException where long.Parse raises OverflowException - and the
    /// compiled caller catches only InnerCommandException (the PS caller's bare catch took
    /// anything), so an overflow would escape unhandled. Unreachable today: the sole
    /// caller pre-filters pure numerics away from this helper entirely, and hex sections
    /// are regex-capped at 8 digits.
    /// </summary>
    internal static LsnConversion? ConvertDbaLsn(PSCmdlet host, string lsn, bool enableException)
    {
        const string functionName = "Convert-DbaLSN";
        lsn = PsString(lsn);
        string? hexadecimal = null;
        string? numeric = null;

        if (System.Text.RegularExpressions.Regex.IsMatch(lsn, "^[a-fA-F0-9]{8}:[a-fA-F0-9]{8}:[a-fA-F0-9]{4}$"))
        {
            InnerCommand.Message(host, functionName, enableException, MessageLevel.Verbose, "Hexadecimal LSN passed in, converting to numeric");
            string[] sections = lsn.Split(':');
            string sect1 = Convert.ToInt64(sections[0], 16).ToString(CultureInfo.InvariantCulture);
            string sect2 = Convert.ToInt64(sections[1], 16).ToString(CultureInfo.InvariantCulture).PadLeft(10, '0');
            string sect3 = Convert.ToInt64(sections[2], 16).ToString(CultureInfo.InvariantCulture).PadLeft(5, '0');
            hexadecimal = lsn;
            numeric = sect1 + sect2 + sect3;
        }
        else if (System.Text.RegularExpressions.Regex.IsMatch(lsn, "^[0-9]{15}[0-9]+$"))
        {
            InnerCommand.Message(host, functionName, enableException, MessageLevel.Verbose, "Numeric LSN passed in, converting to Hexadecimal");
            // PS: [System.Convert]::ToString($LSN.Substring(...), 16) binds the (long, int toBase)
            // overload, coercing the digit substring to a long first; '{0:x}' -f <string> leaves
            // the string untouched because System.String is not IFormattable.
            string sect1 = Convert.ToString(long.Parse(lsn.Substring(0, lsn.Length - 15), CultureInfo.InvariantCulture), 16).PadLeft(8, '0');
            // PS quirk preserved: the second section starts at length-14 (not length-15), dropping a digit.
            string sect2 = Convert.ToString(long.Parse(lsn.Substring(lsn.Length - 14, 9), CultureInfo.InvariantCulture), 16).PadLeft(8, '0');
            string sect3 = Convert.ToString(long.Parse(lsn.Substring(lsn.Length - 5, 5), CultureInfo.InvariantCulture), 16).PadLeft(4, '0');
            numeric = lsn;
            hexadecimal = sect1 + ":" + sect2 + ":" + sect3;
        }
        else
        {
            InnerCommand.Stop(host, functionName, enableException, "LSN passed in is neither Numeric nor in the correct hexadecimal format");
            return null;
        }

        return new LsnConversion { Hexadecimal = hexadecimal, Numeric = numeric };
    }

    /// <summary>
    /// Port of private/functions/Add-TeppCacheItem.ps1: adds an item to the TEPP cache.
    /// The whole body is wrapped in the same swallow-to-Debug try/catch as the PS source.
    /// </summary>
    internal static void AddTeppCacheItem(PSCmdlet host, DbaInstanceParameter sqlInstance, string type, string name)
    {
        const string functionName = "Add-TeppCacheItem";
        string? serverName = null;
        try
        {
            if (sqlInstance.InputObject is Server smoServer)
                serverName = smoServer.Name.ToLowerInvariant();
            else
                serverName = sqlInstance.FullSmoName;

            if (TabExpansionHost.Cache[type] is IDictionary typeCache && typeCache.Contains(serverName))
            {
                List<string> existing = new();
                if (typeCache[serverName] is IEnumerable current and not string)
                {
                    foreach (object? entry in current)
                        existing.Add(entry?.ToString() ?? string.Empty);
                }
                else if (typeCache[serverName] != null)
                {
                    existing.Add(typeCache[serverName]!.ToString()!);
                }

                bool alreadyCached = false;
                foreach (string entry in existing)
                {
                    if (string.Equals(entry, name, StringComparison.OrdinalIgnoreCase))
                    {
                        alreadyCached = true;
                        break;
                    }
                }

                if (!alreadyCached)
                {
                    existing.Add(name);
                    // PS: ... + $Name | Sort-Object (default sort: current culture, case-insensitive)
                    existing.Sort(StringComparer.CurrentCultureIgnoreCase);
                    typeCache[serverName] = existing.ToArray();
                    InnerCommand.Message(host, functionName, false, MessageLevel.Debug, $"{name} added to cache for {type} on {serverName}.");
                }
                else
                {
                    InnerCommand.Message(host, functionName, false, MessageLevel.Debug, $"{name} already in cache for {type} on {serverName}.");
                }
            }
            else
            {
                InnerCommand.Message(host, functionName, false, MessageLevel.Debug, $"No cache for {serverName} found.");
            }
        }
        catch (Exception ex)
        {
            InnerCommand.Message(host, functionName, false, MessageLevel.Debug, $"Failed to add {name} to cache for {type} on {serverName}. {ex.Message}");
        }
    }

    /// <summary>
    /// Port of private/functions/Get-RestoreContinuableDatabase.ps1: databases with a
    /// redo_start_lsn (in a state for further restores). The caller always passes a live
    /// connected server, so the helper's Connect-DbaInstance is a pass-through. The SQL 2000
    /// branch is carried verbatim: it only creates a temp table and returns no rows.
    /// </summary>
    internal static object? GetRestoreContinuableDatabase(PSCmdlet host, Server server)
    {
        _ = host;
        string sql;
        if (server.VersionMajor >= 9)
        {
            sql = "SELECT DB_NAME(database_id) AS 'Database', MIN(differential_base_lsn) AS differential_base_lsn, MIN(redo_start_lsn) AS redo_start_lsn, redo_start_fork_guid AS 'FirstRecoveryForkID' FROM sys.master_files WHERE redo_start_lsn IS NOT NULL GROUP BY database_id, redo_start_fork_guid";
        }
        else
        {
            sql = @"
              CREATE TABLE #db_info
                (
                ParentObject NVARCHAR(128) COLLATE database_default ,
                Object       NVARCHAR(128) COLLATE database_default,
                Field        NVARCHAR(128) COLLATE database_default,
                Value        SQL_VARIANT
                )";
        }
        List<System.Data.DataRow> rows = new();
        System.Data.DataSet results = server.ConnectionContext.ExecuteWithResults(sql);
        foreach (System.Data.DataTable table in results.Tables)
        {
            foreach (System.Data.DataRow row in table.Rows)
                rows.Add(row);
        }
        // PowerShell pipeline-assignment shape: the source's `$continuePoints = Get-RestoreContinuableDatabase ...`
        // yields $null for zero rows, the scalar for one, an array for many. The consumer
        // (Select-DbaBackupInformation :124) gates continue mode on `$null -ne $ContinuePoints`,
        // so a non-null EMPTY array would wrongly enter continue mode and LSN-filter every
        // database away when nothing is continuable.
        if (rows.Count == 0)
            return null;
        if (rows.Count == 1)
            return rows[0];
        return rows.ToArray();
    }

    /// <summary>
    /// Port of private/functions/Get-DbaDbPhysicalFile.ps1: fastest way to fetch just the
    /// paths of the physical files for every database on the instance, also for offline
    /// databases. The caller passes its live connected server (Connect pass-through).
    /// The source's bare string throw is ported as RuntimeException (the engine's own
    /// shape for throw "string"). One intentional divergence, genuinely unobservable:
    /// the source reads only the FIRST result table (its Query script method returns
    /// Tables[0]) where this port flattens all tables - identical for the single-SELECT
    /// batches this method builds. The error mask wraps ONLY the query leg, matching
    /// the source's try boundary; failures before it (the version read) are never
    /// replaced by the mask in either world, though each world surfaces its own
    /// wrapper type there (SMO's connection failure here, the engine's
    /// property-getter wrapper in PS) - unreachable from the shipped call site, which
    /// passes an already-connected server.
    /// </summary>
    internal static System.Data.DataRow[] GetDbaDbPhysicalFile(PSCmdlet host, Server server)
    {
        string sql;
        if (server.VersionMajor <= 8)
        {
            sql = "SELECT DB_NAME(dbid) AS name, Name AS LogicalName, filename AS PhysicalName, type FROM sysaltfiles";
        }
        else
        {
            sql = "SELECT DB_NAME(database_id) AS Name, name AS LogicalName, physical_name AS PhysicalName, type FROM sys.master_files";
        }
        InnerCommand.Message(host, "Get-DbaDbPhysicalFile", false, Dataplat.Dbatools.Message.MessageLevel.Debug, sql);
        try
        {
            List<System.Data.DataRow> rows = new();
            System.Data.DataSet results = server.ConnectionContext.ExecuteWithResults(sql);
            foreach (System.Data.DataTable table in results.Tables)
            {
                foreach (System.Data.DataRow row in table.Rows)
                    rows.Add(row);
            }
            return rows.ToArray();
        }
        catch
        {
            // PS: throw "Error enumerating files" - a bare string throw surfaces as
            // RuntimeException, and $Error[0].Exception type + CategoryInfo.Reason are
            // user-observable past the shipped call site.
            throw new RuntimeException("Error enumerating files");
        }
    }

    /// <summary>
    /// PS parameter-binding parity: a [string] parameter that was not bound (or was bound
    /// $null) is an EMPTY string inside a PS function, and the restore ecosystem leans on
    /// '' -ne $x checks everywhere. Apply to every string parameter on entry.
    /// </summary>
    internal static string PsString(string? value)
    {
        return value ?? string.Empty;
    }

    /// <summary>
    /// PS LanguagePrimitives string conversion — what assigning a value (possibly a
    /// collection) to a .NET string field does in PS: collections join with the default
    /// $OFS separator (a space), null becomes empty.
    /// </summary>
    internal static string PsStringify(object? value)
    {
        if (value is null)
            return string.Empty;
        return (string)LanguagePrimitives.ConvertTo(value, typeof(string), CultureInfo.InvariantCulture);
    }
}
