#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Linq;
using System.Management.Automation;
using System.Numerics;
using System.Text;
using Dataplat.Dbatools.Message;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>The T-SQL of Get-DbaDbBackupHistory, as the pinned function composes it.</summary>
public sealed partial class GetDbaDbBackupHistoryCommand
{
    // 2014 introduced encryption.
    private const string EncryptedBackupColumns = @"
                backupset.backup_size AS TotalSize,
                backupset.compressed_backup_size as CompressedBackupSize,
                encryptor_thumbprint as EncryptorThumbprint,
                encryptor_type as EncryptorType,
                key_algorithm AS KeyAlgorithm";

    // 2008 introduced compressed_backup_size.
    private const string CompressedBackupColumns = @"
                backupset.backup_size AS TotalSize,
                backupset.compressed_backup_size as CompressedBackupSize,
                NULL as EncryptorThumbprint,
                NULL as EncryptorType,
                NULL AS KeyAlgorithm";

    // {0} the database literal, {1} the -Since filter, {2} the -RecoveryFork filter.
    private const string ForkCheckTemplate = @"
                            SELECT
                                database_name,
                                MIN(database_backup_lsn) AS 'FirstLsn',
                                MAX(database_backup_lsn) AS 'FinalLsn',
                                MIN(backup_start_date) AS 'MinDate',
                                MAX(backup_finish_date) AS 'MaxDate',
                                last_recovery_fork_guid 'RecFork',
                                COUNT(1) AS 'backupcount'
                            FROM msdb.dbo.backupset
                            WHERE database_name={0}
                            {1}
                            {2}
                            GROUP BY database_name, last_recovery_fork_guid
                        ";

    // The pin's recap for future editors: rank over last_lsn and finish date, never backup_set_id or dates alone, because
    // LSN is the source of truth and times carry DST; filter on the database_guid and recovery fork of the newest backup,
    // because a dropped and recreated database or a restore of an old backup leaves last_lsn out of order (issue #6730).
    // {0} the LSN column, {1} the backup columns, {2} the database literal, {3} and {4} the two types, {5} copy-only,
    // {6} device type, {7} -Since, {8} -RecoveryFork, {9} mirror. {8} also bounds the newest backup, so that an older fork
    // can be asked for: only the newest fork could ever pass the outer filter otherwise.
    private const string LastTemplate = @"SELECT
                        a.BackupSetRank,
                        a.Server,
                        '' AS AvailabilityGroupName,
                        a.[Database],
                        a.DatabaseId,
                        a.Username,
                        a.Start,
                        a.[End],
                        a.Duration,
                        a.[Path],
                        a.Type,
                        a.TotalSize,
                        a.CompressedBackupSize,
                        a.MediaSetId,
                        a.BackupSetID,
                        a.Software,
                        a.position,
                        a.first_lsn,
                        a.database_backup_lsn,
                        a.checkpoint_lsn,
                        a.last_lsn,
                        a.first_lsn AS 'FirstLSN',
                        a.database_backup_lsn AS 'DatabaseBackupLsn',
                        a.checkpoint_lsn AS 'CheckpointLsn',
                        a.last_lsn AS 'LastLsn',
                        a.software_major_version,
                        a.DeviceType,
                        a.is_copy_only,
                        a.last_recovery_fork_guid,
                        a.recovery_model,
                        a.EncryptorThumbprint,
                        a.EncryptorType,
                        a.KeyAlgorithm
                    FROM (
                        SELECT
                        RANK() OVER (ORDER BY backupset.{0} DESC, backupset.backup_finish_date DESC) AS 'BackupSetRank',
                        backupset.database_name AS [Database],
                        (SELECT database_id FROM sys.databases WHERE name = backupset.database_name) AS DatabaseId,
                        backupset.user_name AS Username,
                        backupset.backup_start_date AS Start,
                        backupset.server_name AS [Server],
                        backupset.backup_finish_date AS [End],
                        DATEDIFF(SECOND, backupset.backup_start_date, backupset.backup_finish_date) AS Duration,
                        mediafamily.physical_device_name AS Path,
                        {1},
                        CASE backupset.type
                        WHEN 'L' THEN 'Log'
                        WHEN 'D' THEN 'Full'
                        WHEN 'F' THEN 'File'
                        WHEN 'I' THEN 'Differential'
                        WHEN 'G' THEN 'Differential File'
                        WHEN 'P' THEN 'Partial Full'
                        WHEN 'Q' THEN 'Partial Differential'
                        ELSE NULL
                        END AS Type,
                        backupset.media_set_id AS MediaSetId,
                        mediafamily.media_family_id AS mediafamilyid,
                        backupset.backup_set_id AS BackupSetID,
                        CASE mediafamily.device_type
                        WHEN 2 THEN 'Disk'
                        WHEN 102 THEN 'Permanent Disk Device'
                        WHEN 5 THEN 'Tape'
                        WHEN 105 THEN 'Permanent Tape Device'
                        WHEN 6 THEN 'Pipe'
                        WHEN 106 THEN 'Permanent Pipe Device'
                        WHEN 7 THEN 'Virtual Device'
                        WHEN 9 THEN 'URL'
                        ELSE 'Unknown'
                        END AS DeviceType,
                        backupset.position,
                        backupset.first_lsn,
                        backupset.database_backup_lsn,
                        backupset.checkpoint_lsn,
                        backupset.last_lsn,
                        backupset.software_major_version,
                        mediaset.software_name AS Software,
                        backupset.is_copy_only,
                        backupset.last_recovery_fork_guid,
                        backupset.recovery_model
                        FROM msdb.dbo.backupmediafamily AS mediafamily
                        JOIN msdb.dbo.backupmediaset AS mediaset ON mediafamily.media_set_id = mediaset.media_set_id
                        JOIN msdb.dbo.backupset AS backupset ON backupset.media_set_id = mediaset.media_set_id
                        JOIN (
                            SELECT TOP 1 database_name, database_guid, last_recovery_fork_guid
                            FROM msdb.dbo.backupset
                            WHERE database_name = {2}
                            {8}
                            ORDER BY backup_finish_date DESC
                            ) AS last_guids ON last_guids.database_name = backupset.database_name AND last_guids.database_guid = backupset.database_guid AND last_guids.last_recovery_fork_guid = backupset.last_recovery_fork_guid
                    WHERE (type = '{3}' OR type = '{4}')
                    {5}
                    {6}
                    {7}
                    {8}
                    {9}
                    ) AS a
                    WHERE a.BackupSetRank = 1
                    ORDER BY a.Type;
                    ";

    // {0} the backup columns.
    private const string FlatColumnsTemplate = @"
                    SELECT
                        '' AS AvailabilityGroupName,
                        backupset.database_name AS [Database],
                        (SELECT database_id FROM sys.databases WHERE name = backupset.database_name) AS DatabaseId,
                        backupset.user_name AS Username,
                        backupset.server_name AS [server],
                        backupset.backup_start_date AS [Start],
                        backupset.backup_finish_date AS [End],
                        DATEDIFF(SECOND, backupset.backup_start_date, backupset.backup_finish_date) AS Duration,
                        mediafamily.physical_device_name AS Path,
                        {0},
                        CASE backupset.type
                            WHEN 'L' THEN 'Log'
                            WHEN 'D' THEN 'Full'
                            WHEN 'F' THEN 'File'
                            WHEN 'I' THEN 'Differential'
                            WHEN 'G' THEN 'Differential File'
                            WHEN 'P' THEN 'Partial Full'
                            WHEN 'Q' THEN 'Partial Differential'
                            ELSE NULL
                        END AS Type,
                        backupset.media_set_id AS MediaSetId,
                        mediafamily.media_family_id AS MediaFamilyId,
                        backupset.backup_set_id AS BackupSetId,
                        CASE mediafamily.device_type
                            WHEN 2 THEN 'Disk'
                            WHEN 102 THEN 'Permanent Disk Device'
                            WHEN 5 THEN 'Tape'
                            WHEN 105 THEN 'Permanent Tape Device'
                            WHEN 6 THEN 'Pipe'
                            WHEN 106 THEN 'Permanent Pipe Device'
                            WHEN 7 THEN 'Virtual Device'
                            WHEN 9 THEN 'URL'
                            ELSE 'Unknown'
                        END AS DeviceType,
                        backupset.position,
                        backupset.first_lsn,
                        backupset.database_backup_lsn,
                        backupset.checkpoint_lsn,
                        backupset.last_lsn,
                        backupset.first_lsn AS 'FirstLSN',
                        backupset.database_backup_lsn AS 'DatabaseBackupLsn',
                        backupset.checkpoint_lsn AS 'CheckpointLsn',
                        backupset.last_lsn AS 'LastLsn',
                        backupset.software_major_version,
                        mediaset.software_name AS Software,
                        backupset.is_copy_only,
                        backupset.last_recovery_fork_guid,
                        backupset.recovery_model";

    private const string FlatFrom = @" FROM msdb.dbo.backupmediafamily mediafamily
                INNER JOIN msdb.dbo.backupmediaset mediaset ON mediafamily.media_set_id = mediaset.media_set_id
                INNER JOIN msdb.dbo.backupset backupset ON backupset.media_set_id = mediaset.media_set_id";

    // {0} one or more backup set ids joined by the separator below. <> 8 eliminates data files that no longer exist.
    private const string FileListTemplate = @"CREATE TABLE #BackupSetIds ( backup_set_id INT ); INSERT INTO #BackupSetIds( backup_set_id ) VALUES ({0}); SELECT bf.backup_set_id, file_type AS FileType, logical_name AS LogicalName, physical_name AS PhysicalName
                    FROM msdb.dbo.backupfile bf
                    JOIN #BackupSetIds bs
                        ON bs.backup_set_id = bf.backup_set_id
                    WHERE [state] <> 8;
                    DROP TABLE #BackupSetIds;";

    private const string FileListSeparator = ");INSERT INTO #BackupSetIds( backup_set_id ) VALUES (";

    /// <summary>What separates the pin's default form from its recursive call for the -Last logs.</summary>
    private sealed class FlatQuery
    {
        public IReadOnlyCollection<string>? Names;
        public bool AllColumns;
        public bool IncludeMirror;
        public bool IgnoreDiff;
        public string LsnSort = "last_lsn";
        public IReadOnlyCollection<string> BackupTypes = Array.Empty<string>();
        public BigInteger LastLsn;
    }

    /// <summary>
    /// The -LastFull, -LastDiff and -LastLog form for a set of databases, one ranked statement each. A multi-fork
    /// report is written for every form but -LastFull, whose fork check has nothing else to give.
    /// </summary>
    private void CollectLast(HistorySource source, IEnumerable<string> names, string first, string second,
        bool includeMirror, string lsnSort, bool lastFull, Action<HistoryItem> sink)
    {
        string since = String.Concat("AND ", SinceCondition());
        string fork = String.IsNullOrEmpty(RecoveryFork) ? String.Empty : String.Format("AND backupset.last_recovery_fork_guid ='{0}'", RecoveryFork);
        string copyOnly = IncludeCopyOnly.ToBool() ? String.Empty : " AND is_copy_only='0' ";
        string mirror = includeMirror ? String.Empty : " AND mediafamily.mirror='0' ";
        string device = HasDeviceFilter() ? String.Format("AND mediafamily.device_type {0}", DeviceFilter()) : String.Empty;

        StringBuilder sql = new();
        foreach (string name in names)
        {
            WriteMessage(MessageLevel.Verbose, String.Format("Processing {0}", name), name);
            if (!lastFull)
                ReportForks(source.Server, name, since, fork);
            sql.Append(LastStatement(lsnSort, source.BackupColumns, name, first, second, copyOnly, device, since, fork, mirror));
        }
        CollectHistory(source, sql.ToString(), sink);
    }

    /// <summary>One database's ranked -Last statement; Get-DbaLastBackup's nested reads compose theirs here too.</summary>
    internal static string LastStatement(string lsnSort, string backupColumns, string name, string first, string second,
        string copyOnly, string device, string since, string fork, string mirror)
    {
        return String.Format(CultureInfo.InvariantCulture, LastTemplate, lsnSort, backupColumns, SqlText(name), first, second, copyOnly, device, since, fork, mirror);
    }

    /// <summary>The recovery fork check of one database.</summary>
    internal static string ForkCheckStatement(string name, string since, string fork)
    {
        return String.Format(CultureInfo.InvariantCulture, ForkCheckTemplate, SqlText(name), since, fork);
    }

    /// <summary>The backup columns the instance's version has.</summary>
    internal static string BackupColumnsFor(Server server)
    {
        return server.VersionMajor >= 12 ? EncryptedBackupColumns : CompressedBackupColumns;
    }

    private void ReportForks(Server server, string name, string since, string fork)
    {
        DataSet? data = RunQuery(server, ForkCheckStatement(name, since, fork), "ExecuteWithResults");
        if (data is null)
            return;
        foreach (KeyValuePair<MessageLevel, string> message in ForkMessages(AllRows(data), name, server.Name))
            WriteMessage(message.Key, message.Value);
    }

    /// <summary>What a fork check's rows report: nothing for one fork, else a verbose line and a warning per fork.</summary>
    internal static List<KeyValuePair<MessageLevel, string>> ForkMessages(List<DataRow> rows, string name, string serverName)
    {
        List<KeyValuePair<MessageLevel, string>> messages = new();
        if (rows.Count < 2)
            return messages;
        messages.Add(new KeyValuePair<MessageLevel, string>(MessageLevel.Verbose,
            String.Format("Found backups from multiple recovery forks for {0} on {1}, this may affect your results", name, serverName)));
        foreach (DataRow row in rows)
        {
            messages.Add(new KeyValuePair<MessageLevel, string>(MessageLevel.Warning, String.Format("Between {0}/{1} and {2}/{3} {4} was on Recovery Fork GUID {5} ({6} backups)",
                ToText(row["MinDate"]), ToText(row["FirstLsn"]), ToText(row["MaxDate"]), ToText(row["FinalLsn"]),
                ToText(row["database_name"]), ToText(row["RecFork"]), ToText(row["backupcount"]))));
        }
        return messages;
    }

    private string BuildFlatQuery(HistorySource source, FlatQuery query)
    {
        List<string> where = new();
        if (query.Names is not null)
            where.Add(String.Format("database_name IN ({0})", query.Names.Count == 0 ? "''" : String.Join(",", query.Names.Select(SqlText))));
        if (!IncludeCopyOnly.ToBool())
            where.Add("is_copy_only='0'");
        if (!query.IncludeMirror)
            where.Add("mediafamily.mirror='0'");
        if (query.IgnoreDiff)
            where.Add("backupset.type not in ('I','G','Q')");
        where.Add(SinceCondition());
        if (!String.IsNullOrEmpty(RecoveryFork))
            where.Add(String.Format("backupset.last_recovery_fork_guid ='{0}'", RecoveryFork));
        if (HasDeviceFilter())
            where.Add(String.Format("mediafamily.device_type {0}", DeviceFilter()));
        if (query.BackupTypes.Count > 0)
            where.Add(String.Format("backupset.type IN ({0})", String.Join(",", query.BackupTypes.Select(code => String.Format("'{0}'", code)))));
        if (!query.LastLsn.IsZero)
            where.Add(String.Format("backupset.last_lsn > {0}", query.LastLsn.ToString(CultureInfo.InvariantCulture)));

        string select = query.AllColumns ? "SELECT * " : String.Format(CultureInfo.InvariantCulture, FlatColumnsTemplate, source.BackupColumns);
        return String.Format("{0} {1}  WHERE  {2} ORDER BY backupset.{3} DESC", select, FlatFrom, String.Join(" AND ", where), query.LsnSort);
    }

    private string SinceCondition() => SinceCondition((DateTime)_since!);

    /// <summary>The -Since filter for one date.</summary>
    internal static string SinceCondition(DateTime since)
    {
        string text = since.ToString("yyyy-MM-ddTHH:mm:ss", CultureInfo.InvariantCulture);
        return String.Format("backupset.backup_finish_date >= CONVERT(datetime,'{0}',126)", text);
    }

    /// <summary>The default -Since, 1970-01-01, as the pin parses it.</summary>
    internal static DateTime DefaultSince => DateTime.ParseExact("1970-01-01", "yyyy-MM-dd", CultureInfo.InvariantCulture);

    // The pin's if ($deviceTypeFilter): one empty string is false.
    private bool HasDeviceFilter() => LanguagePrimitives.IsTrue(_deviceTypeFilter.ToArray());

    private string DeviceFilter() => String.Format("IN ({0})", String.Join(",", _deviceTypeFilter.Select(SqlText)));

    private List<string>? ReadHistoryNames(Server server)
    {
        DataSet? data = RunQuery(server, HistoryNamesSql, "ExecuteWithResults");
        return data is null ? null : HistoryNames(data);
    }

    internal const string HistoryNamesSql = "SELECT DISTINCT database_name FROM msdb.dbo.backupset WHERE database_name IS NOT NULL";

    internal static List<string> HistoryNames(DataSet data) => AllRows(data).Select(row => ToText(row["database_name"])).ToList();

    /// <summary>Caller text as a Unicode T-SQL literal, for database_name is nvarchar.</summary>
    private static string SqlText(string text) => String.Concat("N'", text.Replace("'", "''"), "'");
}
