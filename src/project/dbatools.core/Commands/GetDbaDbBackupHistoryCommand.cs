#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Management.Automation;
using System.Numerics;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves backup history records from MSDB for analysis and compliance reporting.
/// </summary>
/// <para>
/// Queries the MSDB database backup tables to extract detailed backup history information including file paths, sizes, compression ratios, and LSN sequences. Essential for compliance auditing, disaster recovery planning, and troubleshooting backup issues without having to manually query system tables. The function automatically groups striped backup sets into single objects and excludes copy-only backups by default, making the output more practical for restoration scenarios. You can filter results by database name, backup type, date range, or retrieve only the most recent backup chains needed for point-in-time recovery.
/// </para>
/// <para>
/// Reference: http://www.sqlhub.com/2011/07/find-your-backup-history-in-sql-server.html
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbBackupHistory -SqlInstance SqlInstance2014a
/// </code>
/// <para>
/// Returns server name, database, username, backup type, date for all database backups still in msdb history on SqlInstance2014a. This may return many rows; consider using filters that are included in other examples.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $cred = Get-Credential sqladmin
/// Get-DbaDbBackupHistory -SqlInstance SqlInstance2014a -SqlCredential $cred
/// </code>
/// <para>
/// Does the same as above but connect to SqlInstance2014a as SQL user "sqladmin"
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbBackupHistory -SqlInstance SqlInstance2014a -Database db1, db2 -Since ([DateTime]'2016-07-01 10:47:00')
/// </code>
/// <para>
/// Returns backup information only for databases db1 and db2 on SqlInstance2014a since July 1, 2016 at 10:47 AM.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014, pubs -Force | Format-Table
/// </code>
/// <para>
/// Returns information only for AdventureWorks2014 and pubs and formats the results as a table.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014 -Last
/// </code>
/// <para>
/// Returns information about the most recent full, differential and log backups for AdventureWorks2014 on sql2014.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014 -Last -DeviceType Disk
/// </code>
/// <para>
/// Returns information about the most recent full, differential and log backups for AdventureWorks2014 on sql2014, but only for backups to disk.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014 -Last -DeviceType 148,107
/// </code>
/// <para>
/// Returns information about the most recent full, differential and log backups for AdventureWorks2014 on sql2014, but only for backups with device_type 148 and 107.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014 -LastFull
/// </code>
/// <para>
/// Returns information about the most recent full backup for AdventureWorks2014 on sql2014.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014 -Type Full
/// </code>
/// <para>
/// Returns information about all Full backups for AdventureWorks2014 on sql2014.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaRegServer -SqlInstance sql2016 | Get-DbaDbBackupHistory
/// </code>
/// <para>
/// Returns database backup information for every database on every server listed in the Central Management Server on sql2016.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbBackupHistory -SqlInstance SqlInstance2014a, sql2016 -Force
/// </code>
/// <para>
/// Returns detailed backup history for all databases on SqlInstance2014a and sql2016.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbBackupHistory -SqlInstance sql2016 -Database db1 -RecoveryFork 38e5e84a-3557-4643-a5d5-eed607bef9c6 -Last
/// </code>
/// <para>
/// If db1 has multiple recovery forks, specifying the RecoveryFork GUID will restrict the search to that fork.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: DisasterRecovery, Backup
/// Author: Chrissy LeMaire (@cl) | Stuart Moore (@napalmgram)
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaDbBackupHistory" />
[Cmdlet(VerbsCommon.Get, "DbaDbBackupHistory", DefaultParameterSetName = "Default")]
public sealed partial class GetDbaDbBackupHistoryCommand : DbaInstanceCmdlet
{
    /// <para>
    /// The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.
    /// </para>
    [Parameter(Mandatory = true, ValueFromPipeline = true)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <para>
    /// Credential object used to connect to the SQL Server instance as a different user. This can be a Windows or SQL Server account. Windows users are determined by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.
    /// </para>
    [Parameter]
    public override PSCredential? SqlCredential { get; set; }

    /// <para>
    /// Specifies one or more databases to include in the backup history search. Accepts wildcards for pattern matching.
    /// Use this when you need backup history for specific databases rather than all databases on the instance.
    /// </para>
    [Parameter]
    public object[]? Database { get; set; }

    /// <para>
    /// Specifies one or more databases to exclude from the backup history search.
    /// Useful when you want history for most databases but need to skip system databases or specific user databases.
    /// </para>
    [Parameter]
    public object[]? ExcludeDatabase { get; set; }

    /// <para>
    /// Includes copy-only backups in the results, which are normally excluded by default.
    /// Copy-only backups don't break the backup chain and are commonly used for ad-hoc backups or moving databases to other environments.
    /// </para>
    [Parameter]
    public SwitchParameter IncludeCopyOnly { get; set; }

    /// <para>
    /// Returns all columns from the MSDB backup tables instead of the filtered standard output.
    /// Use this when you need access to additional backup metadata fields for detailed analysis or troubleshooting.
    /// </para>
    [Parameter(ParameterSetName = "NoLast")]
    public SwitchParameter Force { get; set; }

    /// <para>
    /// Filters backup history to only include backups taken after the specified date and time.
    /// Accepts DateTime objects or TimeSpan objects (which get added to the current time). Times are compared using the SQL Server instance's timezone.
    /// Essential for limiting results when dealing with databases that have extensive backup history.
    /// </para>
    [Parameter]
    public PSObject? Since { get; set; }

    /// <para>
    /// Filters results to a specific recovery fork GUID when a database has multiple recovery paths.
    /// Use this when a database has been restored from different backup chains or has experienced recovery fork scenarios, ensuring you get the correct backup sequence.
    /// </para>
    // The pinned ValidateScript accepts a GUID by -match (a trailing newline passes $) or exactly "".
    [Parameter]
    [PsStringCast]
    [ValidatePattern(@"^(\{){0,1}[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}(\}){0,1}$|^\z")]
    public string? RecoveryFork { get; set; }

    /// <para>
    /// Returns the most recent complete backup chain (full, differential, and log backups) needed for point-in-time recovery.
    /// This provides the exact backup sequence you'd need to restore a database to its most current state.
    /// </para>
    [Parameter]
    public SwitchParameter Last { get; set; }

    /// <para>
    /// Returns only the most recent full backup for each database.
    /// Use this to quickly identify the base backup needed for restore operations or to verify when the last full backup was taken.
    /// </para>
    [Parameter]
    public SwitchParameter LastFull { get; set; }

    /// <para>
    /// Returns only the most recent differential backup for each database.
    /// Useful for verifying differential backup schedules or identifying the latest differential backup in a restore scenario.
    /// </para>
    [Parameter]
    public SwitchParameter LastDiff { get; set; }

    /// <para>
    /// Returns only the most recent transaction log backup for each database.
    /// Critical for monitoring log backup frequency and identifying the latest point-in-time recovery option available.
    /// </para>
    [Parameter]
    public SwitchParameter LastLog { get; set; }

    /// <para>
    /// Filters backups by device type such as 'Disk', 'Tape', 'URL', or 'Virtual Device'.
    /// Use this to find backups stored on specific media types, particularly useful when backups go to different destinations like local disk vs cloud storage.
    /// </para>
    [Parameter]
    public string[]? DeviceType { get; set; }

    /// <para>
    /// Returns one object per backup file instead of grouping striped backup sets into single objects.
    /// Use this when you need to see individual backup file details for striped backups or need to analyze backup file distribution.
    /// </para>
    [Parameter]
    public SwitchParameter Raw { get; set; }

    /// <para>
    /// Filters to only include backups with LSNs greater than the specified value, improving query performance on large backup histories.
    /// Use this when you know the LSN range you're interested in, typically when building restore sequences or analyzing backup chains.
    /// </para>
    [Parameter]
    public BigInteger LastLsn { get; set; }

    /// <para>
    /// Includes mirror backup copies in the results, which are excluded by default.
    /// Use this when you need to see all backup copies created through backup mirroring, useful for verifying mirror backup configurations.
    /// </para>
    [Parameter]
    public SwitchParameter IncludeMirror { get; set; }

    /// <para>
    /// Filters results to specific backup types: 'Full', 'Log', 'Differential', 'File', 'Differential File', 'Partial Full', or 'Partial Differential'.
    /// Use this to focus on particular backup types when analyzing backup strategies or troubleshooting specific backup issues.
    /// </para>
    [Parameter]
    [ValidateSet("Full", "Log", "Differential", "File", "Differential File", "Partial Full", "Partial Differential")]
    public string[]? Type { get; set; }

    /// <para>
    /// Deprecated parameter. Use Get-DbaAgBackupHistory instead to retrieve backup history from all replicas in an Availability Group.
    /// This parameter is maintained for backward compatibility but no longer functions.
    /// </para>
    [Parameter]
    public SwitchParameter AgCheck { get; set; }

    /// <para>
    /// Excludes differential backups from the results, showing only full and log backups.
    /// Useful when analyzing backup chains that don't use differential backups or when you want to focus on full and log backup patterns.
    /// </para>
    [Parameter]
    public SwitchParameter IgnoreDiffBackup { get; set; }

    /// <para>
    /// Determines which LSN column to use for sorting results: 'FirstLsn', 'DatabaseBackupLsn', or 'LastLsn' (default).
    /// Use this to control backup ordering when working with complex backup scenarios or when you need results sorted by specific LSN checkpoints.
    /// </para>
    [Parameter]
    [PsStringCast]
    [ValidateSet("FirstLsn", "DatabaseBackupLsn", "LastLsn")]
    public string LsnSort { get; set; } = "LastLsn";

    private static readonly char[] WildcardCharacters = { '*', '?', '[' };

    private const string AgCheckMessage = "Parameter AGCheck is deprecated. This command does not check for history from replicas even if this paramater is not provided. The functionality to also get the history from all replicas if SqlInstance is part on an availability group has been moved to Get-DbaAgBackupHistory.";

    private static readonly Dictionary<string, int> DeviceTypeCodes = new(StringComparer.OrdinalIgnoreCase)
    {
        ["Disk"] = 2,
        ["Permanent Disk Device"] = 102,
        ["Tape"] = 5,
        ["Permanent Tape Device"] = 105,
        ["Pipe"] = 6,
        ["Permanent Pipe Device"] = 106,
        ["Virtual Device"] = 7,
        ["URL"] = 9
    };

    private static readonly Dictionary<string, string> BackupTypeCodes = new(StringComparer.OrdinalIgnoreCase)
    {
        ["Log"] = "L",
        ["Full"] = "D",
        ["File"] = "F",
        ["Differential"] = "I",
        ["Differential File"] = "G",
        ["Partial Full"] = "P",
        ["Partial Differential"] = "Q"
    };

    private static readonly Dictionary<string, string> LsnColumns = new(StringComparer.OrdinalIgnoreCase)
    {
        ["FirstLsn"] = "first_lsn",
        ["DatabaseBackupLsn"] = "database_backup_lsn",
        ["LastLsn"] = "last_lsn"
    };

    private readonly List<string> _deviceTypeFilter = new();
    private readonly List<string> _backupTypeFilter = new();
    private string _internalLsnSort = "last_lsn";

    // The pin's $Since parameter: a TimeSpan becomes a DateTime on the first record and stays one for the run.
    private object? _since;
    private bool _sinceRead;

    /// <summary>The two begin diagnostics and the filters the pin computes once.</summary>
    protected override void BeginProcessing()
    {
        string parameterSet = MyInvocation.BoundParameters.Count > 0 ? ParameterSetName : "Default";
        WriteMessage(MessageLevel.System, String.Format("Active Parameter set: {0}.", parameterSet));
        WriteMessage(MessageLevel.System, String.Format("Bound parameters: {0}", String.Join(", ", MyInvocation.BoundParameters.Keys)));

        foreach (string? device in DeviceType ?? Array.Empty<string>())
        {
            string text = device ?? String.Empty;
            _deviceTypeFilter.Add(DeviceTypeCodes.TryGetValue(text, out int code) ? code.ToString(CultureInfo.InvariantCulture) : text);
        }
        foreach (string type in Type ?? Array.Empty<string>())
            _backupTypeFilter.Add(BackupTypeCodes[type]);
        _internalLsnSort = LsnColumns[LsnSort];
    }

    /// <summary>Reads the history of every instance of the record.</summary>
    protected override void ProcessRecord()
    {
        if (AgCheck.ToBool())
        {
            StopFunction(AgCheckMessage);
            return;
        }
        if (!ResolveSince())
        {
            StopFunction("-Since must be either a DateTime or TimeSpan object.");
            return;
        }

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server server = ConnectInstance(instance, "Failure", 9, azureUnsupported: true);
            if (server is null)
                continue;
            ProcessInstance(new HistorySource(server));
        }
    }

    /// <summary>The -Since value as a DateTime, false when it is neither a DateTime nor a TimeSpan.</summary>
    private bool ResolveSince()
    {
        if (!_sinceRead)
        {
            _since = TestBound("Since") ? Since?.BaseObject : DefaultSince;
            _sinceRead = true;
        }
        if (_since is TimeSpan offset)
            _since = DateTime.Now.Add(offset);
        return _since is DateTime;
    }

    private void ProcessInstance(HistorySource source)
    {
        bool lastForm = LastFull.ToBool() || LastDiff.ToBool() || LastLog.ToBool();
        bool named = (Database?.Length ?? 0) > 0 || (ExcludeDatabase?.Length ?? 0) > 0;
        List<string>? names = new();
        if (Last.ToBool() || lastForm || named)
            names = ResolveNames(source.Server);
        if (names is null)
            return;

        if (Last.ToBool())
        {
            foreach (string name in names)
                WriteChain(source, name);
            return;
        }
        if (lastForm)
        {
            // The last switch given wins, as the pin's three assignments do.
            string first = LastLog.ToBool() ? "L" : LastDiff.ToBool() ? "I" : "D";
            string second = LastLog.ToBool() ? "L" : LastDiff.ToBool() ? "Q" : "P";
            CollectLast(source, names.Distinct(StringComparer.Ordinal), first, second, IncludeMirror.ToBool(), _internalLsnSort, LastFull.ToBool(), Emit);
            return;
        }

        FlatQuery query = new()
        {
            Names = named ? names : null,
            AllColumns = Force.ToBool(),
            IncludeMirror = IncludeMirror.ToBool(),
            IgnoreDiff = IgnoreDiffBackup.ToBool(),
            LsnSort = _internalLsnSort,
            BackupTypes = _backupTypeFilter,
            LastLsn = LastLsn
        };
        CollectHistory(source, BuildFlatQuery(source, query), Emit, Force.ToBool());
    }

    private void Emit(HistoryItem item) => WriteObject(item.Output);

    /// <summary>
    /// The pin's $databases: -Database as given with its wildcards expanded, or every database of the instance, less
    /// -ExcludeDatabase. Null when the history could not be read; that failure has been reported.
    /// </summary>
    private List<string>? ResolveNames(Server server) => ResolveNames(server, Database, ExcludeDatabase, () => ReadHistoryNames(server));

    /// <summary>
    /// ResolveNames for given filters; readHistoryNames reads the names in the history, null when it failed and reported
    /// that. Get-DbaLastBackup's nested reads resolve their names here too.
    /// </summary>
    internal static List<string>? ResolveNames(Server server, object[]? database, object[]? excludeDatabase, Func<List<string>?> readHistoryNames)
    {
        List<string> names = new();
        if (database is not null)
        {
            List<string>? inHistory = null;
            foreach (object item in database)
            {
                string name = ToText(item);
                if (name.IndexOfAny(WildcardCharacters) < 0)
                {
                    names.Add(name);
                    continue;
                }
                inHistory ??= readHistoryNames();
                if (inHistory is null)
                    return null;
                names.AddRange(inHistory.Where(candidate => MatchesName(name, candidate) && !names.Contains(candidate)).ToList());
            }
        }
        else
        {
            foreach (SmoDatabase smoDatabase in server.Databases)
                names.Add(smoDatabase.Name);
        }
        if (LanguagePrimitives.IsTrue(excludeDatabase))
            names.RemoveAll(name => excludeDatabase!.Any(item => LanguagePrimitives.Equals(name, item, true)));
        return names;
    }

    // A database may be named with these, so a value still matches itself exactly, and an unbalanced [ only that way.
    private static bool MatchesName(string pattern, string name)
    {
        if (String.Equals(pattern, name, StringComparison.OrdinalIgnoreCase))
            return true;
        try
        {
            return new WildcardPattern(pattern, WildcardOptions.IgnoreCase).IsMatch(name);
        }
        catch (WildcardPatternException)
        {
            return false;
        }
    }

    /// <summary>
    /// The -Last form: the full, the differential when it continues that full, and the logs after them,
    /// ordered as the pin's Sort-Object LastLsn, Type does.
    /// </summary>
    private void WriteChain(HistorySource source, string name)
    {
        string[] only = { name };
        List<HistoryItem> chain = new();
        List<HistoryItem> full = new();
        CollectLast(source, only, "D", "P", false, "last_lsn", true, full.Add);
        if (full.Count == 0)
        {
            WriteMessage(MessageLevel.Verbose, String.Format("No Full Backup found for database {0}, skipping", name));
            return;
        }
        chain.AddRange(full);
        // Every row of a striped backup set carries the same LSNs and fork.
        HistoryItem fullBackup = full[0];

        List<HistoryItem> differential = new();
        if (!IgnoreDiffBackup.ToBool())
            CollectLast(source, only, "I", "Q", false, "last_lsn", false, differential.Add);

        BigInteger logStart;
        if (differential.Count > 0 && differential[0].LastLsn > fullBackup.LastLsn && differential[0].DatabaseBackupLsn == fullBackup.CheckpointLsn)
        {
            WriteMessage(MessageLevel.Verbose, "Valid Differential backup ");
            chain.AddRange(differential);
            logStart = differential[0].FirstLsn;
        }
        else
        {
            WriteMessage(MessageLevel.Verbose, IgnoreDiffBackup.ToBool() ? "Ignoring Diff backups, so using Full backup FirstLSN" : "No Diff found");
            logStart = fullBackup.FirstLsn;
        }

        bool copyOnly = IncludeCopyOnly.ToBool();
        if (copyOnly)
            WriteMessage(MessageLevel.Verbose, "Copy Only check");

        List<HistoryItem> logs = new();
        FlatQuery query = new()
        {
            Names = only,
            LsnSort = "last_lsn",
            LastLsn = logStart
        };
        CollectHistory(source, BuildFlatQuery(source, query), logs.Add);
        chain.AddRange(logs.Where(log => String.Equals(log.Type, "Log", StringComparison.OrdinalIgnoreCase)
            && log.LastLsn > logStart
            && (copyOnly || log.DatabaseBackupLsn == fullBackup.CheckpointLsn)
            && log.Fork == fullBackup.Fork));

        foreach (HistoryItem backup in chain.OrderBy(entry => entry.LastLsn).ThenBy(entry => entry.Type, StringComparer.CurrentCultureIgnoreCase))
            Emit(backup);
    }

    private static string ToText(object? value) => LanguagePrimitives.ConvertTo<string>(value);
}
