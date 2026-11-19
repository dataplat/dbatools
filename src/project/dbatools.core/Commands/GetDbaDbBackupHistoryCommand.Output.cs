#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Linq;
using System.Management.Automation;
using System.Numerics;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Database;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using DbaSize = Dataplat.Dbatools.Utility.Size;

namespace Dataplat.Dbatools.Commands;

/// <summary>Runs the history queries and shapes their rows.</summary>
public sealed partial class GetDbaDbBackupHistoryCommand
{
    /// <summary>The connected server and what each of its history objects repeats.</summary>
    private sealed class HistorySource
    {
        public readonly Server Server;
        public readonly string BackupColumns;
        public readonly string ComputerName;
        public readonly string InstanceName;
        public readonly string SqlInstanceName;

        public HistorySource(Server server)
        {
            Server = server;
            BackupColumns = server.VersionMajor >= 12 ? EncryptedBackupColumns : CompressedBackupColumns;
            ComputerName = SmoServerExtensions.GetComputerName(server);
            InstanceName = server.ServiceName;
            SqlInstanceName = SmoServerExtensions.GetDomainInstanceName(server);
        }
    }

    /// <summary>One output object and the columns the -Last chain reads, for both output shapes.</summary>
    private sealed class HistoryItem
    {
        public readonly object Output;
        public readonly string Type;
        public readonly BigInteger FirstLsn;
        public readonly BigInteger LastLsn;
        public readonly BigInteger DatabaseBackupLsn;
        public readonly BigInteger CheckpointLsn;
        public readonly Guid Fork;

        public HistoryItem(object output, DataRow row)
        {
            Output = output;
            Type = ToText(Field(row, "Type"));
            FirstLsn = ToLsn(Field(row, "first_lsn"));
            LastLsn = ToLsn(Field(row, "last_lsn"));
            DatabaseBackupLsn = ToLsn(Field(row, "database_backup_lsn"));
            CheckpointLsn = ToLsn(Field(row, "checkpoint_lsn"));
            Fork = ToGuid(Field(row, "last_recovery_fork_guid"));
        }
    }

    /// <summary>
    /// Runs a history statement and hands each output object to the sink: one object per row under -Raw or for all
    /// columns, which a BackupHistory has no field for, otherwise one BackupHistory per backup set.
    /// </summary>
    private void CollectHistory(HistorySource source, string sql, Action<HistoryItem> sink, bool allColumns = false)
    {
        WriteMessage(MessageLevel.Debug, String.Format("SQL Statement: \n{0}", sql));
        WriteMessage(MessageLevel.SomewhatVerbose, String.Format("Executing sql query on {0}.", source.Server));
        DataSet? data = RunQuery(source.Server, sql, "ExecuteWithResults");
        if (data is null)
            return;
        List<DataRow> rows = AllRows(data);

        if (Raw.ToBool() || allColumns)
        {
            WriteMessage(MessageLevel.SomewhatVerbose, "Processing as Raw Output.");
            foreach (DataRow row in rows)
                sink(new HistoryItem(ToRawObject(row), row));
            WriteMessage(MessageLevel.SomewhatVerbose, String.Format("{0} result sets found.", rows.Count));
            return;
        }

        WriteMessage(MessageLevel.SomewhatVerbose, "Processing as grouped output.");
        List<int> order = new();
        Dictionary<int, List<DataRow>> groups = new();
        foreach (DataRow row in rows)
        {
            int backupSetId = Convert.ToInt32(row["BackupSetId"], CultureInfo.InvariantCulture);
            if (!groups.TryGetValue(backupSetId, out List<DataRow>? group))
            {
                group = new List<DataRow>();
                groups[backupSetId] = group;
                order.Add(backupSetId);
            }
            group.Add(row);
        }
        // The pin's Group-Object sorts its groups on PowerShell 7; Windows PowerShell 5.1 keeps first-occurrence order.
        if (Environment.Version.Major != 4)
            order.Sort();
        // $groupedResults.Count on one GroupInfo is that group's own Count.
        int groupCount = order.Count == 1 ? groups[order[0]].Count : order.Count;
        WriteMessage(MessageLevel.SomewhatVerbose, String.Format("{0} result-groups found.", groupCount));
        if (order.Count == 0)
            return;

        Dictionary<int, List<PSObject>>? fileLists = ReadFileLists(source.Server, order);
        if (fileLists is null)
            return;
        foreach (int backupSetId in order)
        {
            fileLists.TryGetValue(backupSetId, out List<PSObject>? files);
            sink(ToHistoryItem(source, groups[backupSetId], files));
        }
    }

    private Dictionary<int, List<PSObject>>? ReadFileLists(Server server, List<int> backupSetIds)
    {
        string values = String.Join(FileListSeparator, backupSetIds.Select(id => id.ToString(CultureInfo.InvariantCulture)));
        string sql = String.Format(CultureInfo.InvariantCulture, FileListTemplate, values);
        WriteMessage(MessageLevel.Debug, String.Format("FileSQL: {0}", sql));
        DataSet? data = RunQuery(server, sql, "Query");
        if (data is null)
            return null;

        Dictionary<int, List<PSObject>> fileLists = new();
        foreach (DataRow row in data.Tables[0].Rows)
        {
            int backupSetId = Convert.ToInt32(row["backup_set_id"], CultureInfo.InvariantCulture);
            if (!fileLists.TryGetValue(backupSetId, out List<PSObject>? files))
            {
                files = new List<PSObject>();
                fileLists[backupSetId] = files;
            }
            PSObject file = new();
            file.TypeNames.Insert(0, "Selected.System.Data.DataRow");
            file.Properties.Add(new PSNoteProperty("FileType", row["FileType"]));
            file.Properties.Add(new PSNoteProperty("LogicalName", row["LogicalName"]));
            file.Properties.Add(new PSNoteProperty("PhysicalName", row["PhysicalName"]));
            files.Add(file);
        }
        return fileLists;
    }

    /// <summary>The pin's Select-Object * less its excluded names, then again with the FullName copy of Path.</summary>
    private static PSObject ToRawObject(DataRow row)
    {
        PSObject output = new();
        output.TypeNames.Insert(0, "Selected.System.Management.Automation.PSCustomObject");
        foreach (DataColumn column in row.Table.Columns)
        {
            if (!String.Equals(column.ColumnName, "BackupSetRank", StringComparison.OrdinalIgnoreCase))
                output.Properties.Add(new PSNoteProperty(column.ColumnName, row[column]));
        }
        output.Properties.Add(new PSNoteProperty("FullName", row.Table.Columns.Contains("Path") ? row["Path"] : null));
        return output;
    }

    private static HistoryItem ToHistoryItem(HistorySource source, List<DataRow> group, List<PSObject>? files)
    {
        DataRow common = group[0];
        DateTime start = group.Min(row => ToDate(row["Start"]));
        DateTime end = group.Max(row => ToDate(row["End"]));
        int seconds = group.Max(row => ToInt(row["Duration"]));
        string[] paths = group.Select(row => ToText(row["Path"])).ToArray();
        object total = common["TotalSize"];
        object compressed = common["CompressedBackupSize"];

        BackupHistory history = new()
        {
            ComputerName = source.ComputerName,
            InstanceName = source.InstanceName,
            SqlInstance = source.SqlInstanceName,
            Database = ToText(common["Database"]),
            UserName = ToText(common["Username"]),
            Start = start,
            End = end,
            Duration = new DbaTimeSpan(TimeSpan.FromSeconds(seconds)),
            Path = paths,
            TotalSize = ToSize(total),
            CompressedBackupSize = ToSize(compressed),
            CompressionRatio = ToRatio(total, compressed),
            Type = ToText(common["Type"]),
            BackupSetId = ToText(common["BackupSetId"]),
            DeviceType = ToText(common["DeviceType"]),
            Software = ToText(common["Software"]),
            FullName = paths,
            FileList = ToFileList(files),
            Position = ToInt(common["position"]),
            FirstLsn = ToLsn(common["first_lsn"]),
            DatabaseBackupLsn = ToLsn(common["database_backup_lsn"]),
            CheckpointLsn = ToLsn(common["checkpoint_lsn"]),
            LastLsn = ToLsn(common["last_lsn"]),
            SoftwareVersionMajor = ToInt(common["software_major_version"]),
            IsCopyOnly = common["is_copy_only"] is bool copyOnly && copyOnly,
            LastRecoveryForkGUID = ToGuid(common["last_recovery_fork_guid"]),
            RecoveryModel = ToText(common["recovery_model"]),
            EncryptorType = ToText(common["EncryptorType"]),
            EncryptorThumbprint = ToText(common["EncryptorThumbprint"]),
            KeyAlgorithm = ToText(common["KeyAlgorithm"])
        };
        if (common["DatabaseId"] is int databaseId)
            history.DatabaseId = databaseId.ToString(CultureInfo.InvariantCulture);
        return new HistoryItem(history, common);
    }

    /// <summary>
    /// Runs one batch. A failure is the pin's method fault on that call; the instance then gives no output, where the
    /// pin would go on with the rows of its previous statement. Under -Last it ends the command, because the pin would
    /// go on to emit a chain short of the backup that failed, and a restore follows that chain.
    /// </summary>
    private DataSet? RunQuery(Server server, string sql, string method)
    {
        try
        {
            return server.ConnectionContext.ExecuteWithResults(sql);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ErrorRecord record = method == "Query" ? QueryFaultRecord(failure) : ExecuteFaultRecord(failure);
            // caller-try: terminate -- a -Last chain missing a backup is misleading data, and a caller try ends the pin here
            if (EnableException || Last.ToBool())
                ThrowTerminatingError(record); // style-ok: cs-raw-streams pinned statement fault outside Stop-Function
            // caller-try: continue -- read-only; no input dropped, and the next instance or database still runs
            WriteError(record); // style-ok: cs-raw-streams pinned statement fault outside Stop-Function
            return null;
        }
    }

    private static ErrorRecord ExecuteFaultRecord(Exception exception)
    {
        MethodInvocationException fault = new(
            String.Format("Exception calling \"ExecuteWithResults\" with \"1\" argument(s): \"{0}\"", exception.Message), exception);
        return new ErrorRecord(fault, exception.GetType().Name, ErrorCategory.NotSpecified, null);
    }

    /// <summary>
    /// The record of a failed $server.Query: the script method concatenates the messages of the ExecuteWithResults
    /// failure chain and throws that text, which the engine reports as the method fault of "Query".
    /// </summary>
    private static ErrorRecord QueryFaultRecord(Exception exception)
    {
        string message = "";
        Exception inner = exception;
        while (inner.InnerException is not null)
        {
            message += inner.Message;
            inner = inner.InnerException;
        }
        message += inner.Message;
        MethodInvocationException fault = new(
            String.Format("Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", message), new RuntimeException(message));
        return new ErrorRecord(fault, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
    }

    /// <summary>The rows of every result set, as the pin's .Tables.Rows gives them.</summary>
    private static List<DataRow> AllRows(DataSet data)
    {
        List<DataRow> rows = new();
        foreach (DataTable table in data.Tables)
            rows.AddRange(table.Rows.Cast<DataRow>());
        return rows;
    }

    private static object Field(DataRow row, string name) => row.Table.Columns.Contains(name) ? row[name] : DBNull.Value;

    private static BigInteger ToLsn(object value) => value is decimal lsn ? new BigInteger(lsn) : BigInteger.Zero;

    private static Guid ToGuid(object value) => value is Guid guid ? guid : Guid.Empty;

    private static DateTime ToDate(object value) => value is DateTime date ? date : default;

    private static int ToInt(object value) => value is DBNull ? 0 : Convert.ToInt32(value, CultureInfo.InvariantCulture);

    private static DbaSize? ToSize(object value) => value is decimal bytes ? (DbaSize)bytes : null;

    // Learn, backupset: compressed_backup_size is NULL after an msdb upgrade, "which indicates an uncompressed backup".
    private static double ToRatio(object total, object compressed)
    {
        if (total is decimal size && compressed is decimal stored && stored != 0)
            return (double)Math.Round(size / stored, 2);
        return 1;
    }

    // A pipeline result: nothing, the one object, or an array.
    private static object? ToFileList(List<PSObject>? files)
    {
        if (files is null)
            return null;
        if (files.Count == 1)
            return files[0];
        return files.Cast<object>().ToArray();
    }
}
