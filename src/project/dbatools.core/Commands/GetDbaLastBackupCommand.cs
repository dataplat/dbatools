#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaLastBackup.ps1 at refs/pins/dbatools-2026-10-22: the databases of each instance, the newest full,
// differential and log backup of each from three nested Get-DbaDbBackupHistory -Last* -IncludeCopyOnly -Raw reads, and a
// status. The nested reads compose their statements through GetDbaDbBackupHistoryCommand's own builders.
/// <summary>Retrieves last backup dates and times for database backup compliance monitoring</summary>
/// <para>
/// Queries msdb backup history to retrieve the most recent full, differential, and transaction log backup dates for each database. This function helps DBAs quickly identify backup gaps and verify compliance with backup policies by showing when each backup type was last performed. The function also calculates elapsed time since each backup and provides status indicators to highlight potential issues, such as databases with no recent backups or transaction log backups that are overdue in full recovery model databases. Default output includes Server, Database, LastFullBackup, LastDiffBackup, and LastLogBackup columns.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaLastBackup -SqlInstance ServerA\sql987
/// </code>
/// <para>
/// Returns a custom object with Server name, Database name, and the date the last time backups were performed.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaLastBackup -SqlInstance ServerA\sql987 | Select-Object *
/// </code>
/// <para>
/// Returns a custom object with Server name, Database name, and the date the last time backups were performed, and also recoverymodel and calculations on how long ago backups were taken and what the status is.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaLastBackup -SqlInstance ServerA\sql987 | Select-Object * | Out-Gridview
/// </code>
/// <para>
/// Returns a gridview displaying ComputerName, InstanceName, SqlInstance, Database, RecoveryModel, LastFullBackup, LastDiffBackup, LastLogBackup, SinceFull, SinceDiff, SinceLog, LastFullBackupIsCopyOnly, LastDiffBackupIsCopyOnly, LastLogBackupIsCopyOnly, DatabaseCreated, DaysSinceDbCreated, Status
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $MyInstances | Get-DbaLastBackup | Where-Object -FilterScript { $_.LastFullBackup.Date -lt (Get-Date).AddDays(-3) } | Format-Table -Property SqlInstance, Database, LastFullBackup
/// </code>
/// <para>
/// Returns all databases on the given instances without a full backup in the last three days.
/// Note that the property LastFullBackup is a custom object, with the subproperty Date of type datetime and therefore suitable for comparison with dates.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaLastBackup -SqlInstance ServerA\sql987 | Where-Object { $_.LastFullBackupIsCopyOnly -eq $true }
/// </code>
/// <para>
/// Filters for the databases that had a copy_only full backup done as the last backup.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaLastBackup -SqlInstance sql2019, sql2019b -ExcludeReplica
/// </code>
/// <para>
/// Returns last backup information for all databases on both instances, excluding availability group databases
/// where the current instance is not the preferred backup replica. This prevents false alerts when secondary
/// replicas appear to have no recent backups because backups are only performed on the preferred replica.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: DisasterRecovery, Backup
/// Author: Klaas Vandenberghe (@PowerDBAKlaas)
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaLastBackup" />
[Cmdlet(VerbsCommon.Get, "DbaLastBackup")]
public sealed class GetDbaLastBackupCommand : DbaInstanceCmdlet
{
    private const string HistoryCommand = "Get-DbaDbBackupHistory";

    private const string NotPreferredSql = "SELECT DB_NAME(database_id) AS DatabaseName FROM sys.databases WHERE sys.fn_hadr_backup_is_preferred_replica(DB_NAME(database_id)) = 0";

    private static readonly string[] DefaultView = { "ComputerName", "InstanceName", "SqlInstance", "Database", "LastFullBackup", "LastDiffBackup", "LastLogBackup" };

    /// <para>
    /// The target SQL Server instance or instances.
    /// </para>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <para>
    /// Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
    /// </para>
    /// <para>
    /// Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
    /// </para>
    /// <para>
    /// For MFA support, please use Connect-DbaInstance.
    /// </para>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <para>
    /// Specifies which databases to check for backup history. Accepts wildcards for pattern matching.
    /// Use this when you need to focus on specific databases rather than scanning all databases on the instance.
    /// Helpful for monitoring critical production databases or troubleshooting backup issues on particular databases.
    /// </para>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <para>
    /// Excludes specific databases from the backup history check. Commonly used to skip system databases or test databases.
    /// Use this when you want to check most databases but exclude certain ones like tempdb, development databases, or databases with known backup exemptions.
    /// </para>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <para>
    /// When this switch is enabled, databases in an AlwaysOn Availability Group where the current SQL Server instance
    /// is not the preferred backup replica are excluded from the results.
    /// This is useful when running Get-DbaLastBackup against multiple servers in an availability group to avoid
    /// false positives where secondary replicas appear to have missing backups because backups are taken on the preferred replica only.
    /// </para>
    [Parameter]
    public SwitchParameter ExcludeReplica { get; set; }

    // PS: $StartOfTime = [DbaTimeSpan](New-TimeSpan -Start ([datetime]0)), once in begin.
    private DbaTimeSpan _startOfTime = null!;

    /// <summary>The begin block's start of time.</summary>
    protected override void BeginProcessing()
    {
        _startOfTime = new DbaTimeSpan(DateTime.Now - new DateTime(0));
    }

    /// <summary>Reports every selected database of each instance.</summary>
    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = ConnectInstance(instance, "Failure", 9);
            if (server is null)
                continue;

            List<SmoDatabase> databases = SelectDatabases(server, instance);
            if (databases.Count == 0)
            {
                WriteMessage(MessageLevel.Verbose, String.Format("No databases remain to process for {0} after filtering", instance));
                continue;
            }

            // Correction azure-backup-history: Azure SQL Database has no msdb, where every nested read failed and each database
            // was reported as never backed up; its automated backups are in sys.dm_database_backups. The service's clock is UTC,
            // the clock of its dates, so the spans and the age count from UtcNow.
            if (server.DatabaseEngineType == DatabaseEngineType.SqlAzureDatabase)
            {
                foreach (SmoDatabase database in databases)
                {
                    Dictionary<string, NewestBackup> newest = ReadAzureBackups(database);
                    WriteMessage(MessageLevel.Verbose, String.Format("Processing {0} on {1}", database, instance));
                    WriteObject(Report(server, database, Find(newest, "D"), Find(newest, "I"), Find(newest, "L"), DateTime.UtcNow));
                }
                continue;
            }

            List<string> names = databases.ConvertAll(database => database.Name);
            List<DataRow> fullHistory = ReadLast(server, names, "LastFull", "D", "P");
            List<DataRow> diffHistory = ReadLast(server, names, "LastDiff", "I", "Q");
            List<DataRow> logHistory = ReadLast(server, names, "LastLog", "L", "L");

            foreach (SmoDatabase database in databases)
            {
                WriteMessage(MessageLevel.Verbose, String.Format("Processing {0} on {1}", database, instance));
                WriteObject(Report(server, database, Newest(fullHistory, database.Name), Newest(diffHistory, database.Name), Newest(logHistory, database.Name), DateTime.Now));
            }
        }
    }

    /// <summary>The newest backup of one type: its finish date and copy-only flag, both null when there is none.</summary>
    private sealed class NewestBackup
    {
        public static readonly NewestBackup None = new(null, null);
        public readonly DateTime? End;
        public readonly object? CopyOnly;

        public NewestBackup(DateTime? end, object? copyOnly)
        {
            End = end;
            CopyOnly = copyOnly;
        }
    }

    private const string AzureBackupsSql = "SELECT backup_type, MAX(backup_finish_date) AS backup_finish_date FROM sys.dm_database_backups GROUP BY backup_type";

    // sys.dm_database_backups through the database's own connection lists that database's backups only. The service takes
    // every one of them itself, and none is copy-only.
    private Dictionary<string, NewestBackup> ReadAzureBackups(SmoDatabase database)
    {
        Dictionary<string, NewestBackup> newest = new(StringComparer.Ordinal);
        DataSet data;
        try
        {
            data = database.ExecuteWithResults(AzureBackupsSql);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ReportFault(ExecuteFaultRecord(failure));
            return newest;
        }
        foreach (DataRow row in data.Tables[0].Rows)
        {
            if (row["backup_finish_date"] is DateTime end)
                newest[(Convert.ToString(row["backup_type"], CultureInfo.InvariantCulture) ?? String.Empty).Trim()] = new NewestBackup(end, false);
        }
        return newest;
    }

    private static NewestBackup Find(Dictionary<string, NewestBackup> newest, string type) => newest.TryGetValue(type, out NewestBackup? backup) ? backup! : NewestBackup.None;

    // PS: $server.Databases less tempdb, Name -In $Database, Name -NotIn $ExcludeDatabase, then the non-preferred replicas.
    private List<SmoDatabase> SelectDatabases(Server server, DbaInstanceParameter instance)
    {
        List<SmoDatabase> available = new();
        foreach (SmoDatabase database in server.Databases)
            available.Add(database);
        // Correction database-wildcards: the pinned help documents wildcards for -Database, which -In never honoured. The
        // instance's own names decide which pattern values are real names and stay literal.
        WildcardNameMatcher included = WildcardNameFilter.CreateMatcher(Database, true,
            (value, name) => LanguagePrimitives.Equals(value, name, true, CultureInfo.InvariantCulture), available.ConvertAll(database => database.Name));

        List<SmoDatabase> selected = new();
        foreach (SmoDatabase database in available)
        {
            if (LanguagePrimitives.Equals(database.Name, "tempdb", true, CultureInfo.InvariantCulture))
                continue;
            if (LanguagePrimitives.IsTrue(Database) && !included.Matches(database.Name))
                continue;
            if (LanguagePrimitives.IsTrue(ExcludeDatabase) && Listed(ExcludeDatabase!, database.Name))
                continue;
            selected.Add(database);
        }

        if (ExcludeReplica.ToBool() && server.IsHadrEnabled)
        {
            WriteMessage(MessageLevel.Verbose, String.Format("Excluding non-preferred backup replicas for {0}", instance));
            DataTable notPreferred;
            try
            {
                notPreferred = server.ConnectionContext.ExecuteWithResults(NotPreferredSql).Tables[0];
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                // Correction replica-read-failure: the pin's failed assignment keeps the names an earlier instance read and
                // excludes them here; this instance's own read failed, so nothing is excluded.
                ReportFault(QueryFaultRecord(failure));
                return selected;
            }
            List<object> names = new();
            foreach (DataRow row in notPreferred.Rows)
                names.Add(row["DatabaseName"]);
            if (LanguagePrimitives.IsTrue(names.ToArray()))
                selected.RemoveAll(database => Listed(names.ToArray(), database.Name));
        }
        return selected;
    }

    // PS: Name -In $values, each value on the left of an -eq with the name, ignoring case.
    private static bool Listed(object[] values, string name)
    {
        foreach (object value in values)
        {
            if (LanguagePrimitives.Equals(value, name, true, CultureInfo.InvariantCulture))
                return true;
        }
        return false;
    }

    /// <summary>
    /// PS: Get-DbaDbBackupHistory -SqlInstance $server -Database $dbs.Name -&lt;form&gt; -IncludeCopyOnly -Raw: its rows, empty
    /// when a read failed and was reported.
    /// </summary>
    private List<DataRow> ReadLast(Server server, List<string> databaseNames, string form, string first, string second)
    {
        WriteAttributedMessage(HistoryCommand, MessageLevel.System, "Active Parameter set: Default.");
        WriteAttributedMessage(HistoryCommand, MessageLevel.System, String.Format("Bound parameters: SqlInstance, Database, {0}, IncludeCopyOnly, Raw", form));

        List<DataRow> rows = new();
        List<string>? names = GetDbaDbBackupHistoryCommand.ResolveNames(server, databaseNames.ToArray(), null, () =>
        {
            DataSet? data = RunNestedQuery(server, GetDbaDbBackupHistoryCommand.HistoryNamesSql);
            return data is null ? null : GetDbaDbBackupHistoryCommand.HistoryNames(data);
        });
        if (names is null)
            return rows;

        string since = String.Concat("AND ", GetDbaDbBackupHistoryCommand.SinceCondition(GetDbaDbBackupHistoryCommand.DefaultSince));
        string columns = GetDbaDbBackupHistoryCommand.BackupColumnsFor(server);
        System.Text.StringBuilder sql = new();
        HashSet<string> seen = new(StringComparer.Ordinal);
        foreach (string name in names)
        {
            if (!seen.Add(name))
                continue;
            WriteAttributedMessage(HistoryCommand, MessageLevel.Verbose, String.Format("Processing {0}", name), name);
            // The pin runs the fork check for -LastFull too (its Get-PSCallStack test never matches), and reports only for the
            // other two forms.
            DataSet? forks = RunNestedQuery(server, GetDbaDbBackupHistoryCommand.ForkCheckStatement(name, since, String.Empty));
            if (form != "LastFull")
            {
                if (forks is not null)
                {
                    foreach (KeyValuePair<MessageLevel, string> message in GetDbaDbBackupHistoryCommand.ForkMessages(AllRows(forks), name, server.Name))
                        WriteAttributedMessage(HistoryCommand, message.Key, message.Value);
                }
            }
            sql.Append(GetDbaDbBackupHistoryCommand.LastStatement("last_lsn", columns, name, first, second, String.Empty, String.Empty, since, String.Empty, " AND mediafamily.mirror='0' "));
        }

        string statement = sql.ToString();
        WriteAttributedMessage(HistoryCommand, MessageLevel.Debug, String.Format("SQL Statement: \n{0}", statement));
        WriteAttributedMessage(HistoryCommand, MessageLevel.SomewhatVerbose, String.Format("Executing sql query on {0}.", server));
        DataSet? history = RunNestedQuery(server, statement);
        if (history is null)
            return rows;
        rows = AllRows(history);
        WriteAttributedMessage(HistoryCommand, MessageLevel.SomewhatVerbose, "Processing as Raw Output.");
        WriteAttributedMessage(HistoryCommand, MessageLevel.SomewhatVerbose, String.Format("{0} result sets found.", rows.Count));
        return rows;
    }

    // The nested command's ExecuteWithResults: a failure is its statement fault, the read then gives nothing.
    private DataSet? RunNestedQuery(Server server, string sql)
    {
        try
        {
            return server.ConnectionContext.ExecuteWithResults(sql);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ReportFault(ExecuteFaultRecord(failure));
            return null;
        }
    }

    /// <summary>
    /// A statement fault of the pin: written and gone on from outside a caller try, caught by one, and the stop under
    /// -EnableException.
    /// </summary>
    private void ReportFault(ErrorRecord fault)
    {
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams a statement fault of the pin, outside Stop-Function
        }
        StatementFault.Surface(this, fault);
    }

    // PS: the per-database block of the process loop.
    private PSObject Report(Server server, SmoDatabase database, NewestBackup lastFull, NewestBackup lastDiff, NewestBackup lastLog, DateTime now)
    {
        DateTime? lastFullBackup = lastFull.End;
        DateTime? lastDiffBackup = lastDiff.End;
        DateTime? lastLogBackup = lastLog.End;

        // PS: [DbaTimeSpan](New-TimeSpan -Start $LastXBackup), else $StartOfTime.
        DbaTimeSpan sinceFull = Since(lastFullBackup, now);
        DbaTimeSpan sinceDiff = Since(lastDiffBackup, now);
        DbaTimeSpan sinceLog = Since(lastLogBackup, now);

        DateTime created = database.CreateDate;
        int daysSinceDbCreated = (now - created).Days;
        object? recoveryModel = RecoveryModelOf(server, database);

        // Correction new-database-status: the pin's $SinceFull_ -eq 0 never holds (DbaTimeSpan.Equals takes only a TimeSpan,
        // and -eq hands it an int or a DbaTimeSpan), so the documented first status was never given; it means no full backup.
        // Correction log-backup-hours: the pin compares the span's hours part, which is 0 for a log backup a whole number of
        // days and under an hour ago, and for no log backup at all when the day's hour is 0; the help says "in the last hour".
        string status;
        if (daysSinceDbCreated < 1 && !lastFullBackup.HasValue)
            status = "New database, not backed up yet";
        else if (sinceFull.Days > 0 && sinceDiff.Days > 0)
            status = "No Full or Diff Back Up in the last day";
        else if (recoveryModel is RecoveryModel model && model == RecoveryModel.Full && sinceLog.TotalHours >= 1)
            status = "No Log Back Up in the last hour";
        else
            status = "OK";

        PSObject result = new();
        OutputHelper.AddInstanceProperties(result, server);
        result.Properties.Add(new PSNoteProperty("Database", database.Name));
        result.Properties.Add(new PSNoteProperty("RecoveryModel", recoveryModel));
        result.Properties.Add(new PSNoteProperty("LastFullBackup", ToDbaDate(lastFullBackup)));
        result.Properties.Add(new PSNoteProperty("LastDiffBackup", ToDbaDate(lastDiffBackup)));
        result.Properties.Add(new PSNoteProperty("LastLogBackup", ToDbaDate(lastLogBackup)));
        // PS: Get-DbaDateOrNull returns $null only for a span -eq 0, which a DbaTimeSpan never is (see the status above).
        result.Properties.Add(new PSNoteProperty("SinceFull", sinceFull));
        result.Properties.Add(new PSNoteProperty("SinceDiff", sinceDiff));
        result.Properties.Add(new PSNoteProperty("SinceLog", sinceLog));
        result.Properties.Add(new PSNoteProperty("LastFullBackupIsCopyOnly", lastFull.CopyOnly));
        result.Properties.Add(new PSNoteProperty("LastDiffBackupIsCopyOnly", lastDiff.CopyOnly));
        result.Properties.Add(new PSNoteProperty("LastLogBackupIsCopyOnly", lastLog.CopyOnly));
        result.Properties.Add(new PSNoteProperty("DatabaseCreated", created));
        result.Properties.Add(new PSNoteProperty("DaysSinceDbCreated", daysSinceDbCreated));
        result.Properties.Add(new PSNoteProperty("Status", status));
        OutputHelper.SetDefaultDisplayPropertySet(result, DefaultView);
        return result;
    }

    // PS: $History | Where-Object Database -EQ $db.Name | Sort-Object -Property End -Descending | Select-Object -First 1.
    private static NewestBackup Newest(List<DataRow> history, string name)
    {
        DataRow? row = NewestRow(history, name);
        return row is null ? NewestBackup.None : new NewestBackup(EndOf(row), CopyOnlyOf(row));
    }

    private static DataRow? NewestRow(List<DataRow> history, string name)
    {
        DataRow? newest = null;
        DateTime newestEnd = DateTime.MinValue;
        foreach (DataRow row in history)
        {
            if (!LanguagePrimitives.Equals(row["Database"], name, true, CultureInfo.InvariantCulture))
                continue;
            DateTime end = row["End"] is DateTime value ? value : DateTime.MinValue;
            if (newest is null || end > newestEnd)
            {
                newest = row;
                newestEnd = end;
            }
        }
        return newest;
    }

    // A backup set's finish date; msdb fills it for every finished backup.
    private static DateTime? EndOf(DataRow row) => row["End"] is DateTime end ? end : (DateTime?)null;

    private static object? CopyOnlyOf(DataRow row) => row["is_copy_only"] is DBNull ? null : row["is_copy_only"];

    private DbaTimeSpan Since(DateTime? backup, DateTime now) => backup.HasValue ? new DbaTimeSpan(now - backup.Value) : _startOfTime;

    private const string AzureRecoveryModelSql = "SELECT recovery_model FROM sys.databases WHERE database_id = DB_ID()";

    // PS: $db.RecoveryModel. Where SMO has no such property (Azure SQL Database: "RecoveryModel: unknown property") the pin
    // reads $null with no record, on both editions (evidence/pin-lastbackup-azure-20261106.txt), and -eq "Full" is false.
    // Correction azure-backup-history: the engine has the value, so it is read from sys.databases through the database's own
    // connection; SMO's RecoveryModel values are sys.databases.recovery_model's.
    private object? RecoveryModelOf(Server server, SmoDatabase database)
    {
        try
        {
            return database.RecoveryModel;
        }
        catch (SmoException) when (server.DatabaseEngineType == DatabaseEngineType.SqlAzureDatabase)
        {
            DataSet data;
            try
            {
                data = database.ExecuteWithResults(AzureRecoveryModelSql);
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                ReportFault(ExecuteFaultRecord(failure));
                return null;
            }
            if (data.Tables[0].Rows.Count == 0 || data.Tables[0].Rows[0]["recovery_model"] is DBNull)
                return null;
            return (RecoveryModel)Convert.ToInt32(data.Tables[0].Rows[0]["recovery_model"], CultureInfo.InvariantCulture);
        }
        catch (SmoException)
        {
            return null;
        }
    }

    // PS: [DbaDateTime]$null is $null.
    private static DbaDateTime? ToDbaDate(DateTime? value) => value.HasValue ? new DbaDateTime(value.Value) : null;

    // PS: .Tables.Rows, the rows of every result set.
    private static List<DataRow> AllRows(DataSet data)
    {
        List<DataRow> rows = new();
        foreach (DataTable table in data.Tables)
        {
            foreach (DataRow row in table.Rows)
                rows.Add(row);
        }
        return rows;
    }

    // The engine's record of a failed ExecuteWithResults call in the nested function: the method fault over the failure.
    private static ErrorRecord ExecuteFaultRecord(Exception failure)
    {
        MethodInvocationException call = new(String.Format("Exception calling \"ExecuteWithResults\" with \"1\" argument(s): \"{0}\"", failure.Message), failure);
        return new ErrorRecord(call, failure.GetType().Name, ErrorCategory.NotSpecified, null);
    }

    // The record of a failed $server.Query: its script method's catch joins the messages of the failure's exception chain
    // and throws that text, which the engine reports as the method fault of "Query".
    private static ErrorRecord QueryFaultRecord(Exception failure)
    {
        System.Text.StringBuilder message = new();
        for (Exception? current = failure; current is not null; current = current.InnerException)
            message.Append(current.Message);
        MethodInvocationException call = new(String.Format("Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", message), new RuntimeException(message.ToString(), failure));
        return new ErrorRecord(call, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
    }
}
