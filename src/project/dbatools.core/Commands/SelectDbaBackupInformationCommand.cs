#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;
using Dataplat.Dbatools.Message;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Filters backup history to identify the minimum backup chain needed for point-in-time
/// database recovery. Port of public/Select-DbaBackupInformation.ps1; surface pinned by
/// migration/baselines/Select-DbaBackupInformation.json.
/// </summary>
[Cmdlet(VerbsCommon.Select, "DbaBackupInformation")]
[OutputType(typeof(Dataplat.Dbatools.Database.BackupHistory))]
public sealed class SelectDbaBackupInformationCommand : DbaBaseCmdlet
{
    /// <summary>Backup history records from Get-DbaBackupInformation.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public object? BackupHistory { get; set; }

    /// <summary>The specific point in time to restore the database to.</summary>
    [Parameter(Position = 1)]
    [PsDateTimeCast]
    public DateTime RestoreTime { get; set; } = DateTime.Now.AddMonths(1);

    /// <summary>Excludes transaction log backups from the restore chain.</summary>
    [Parameter]
    public SwitchParameter IgnoreLogs { get; set; }

    /// <summary>Excludes differential backups from the restore chain.</summary>
    [Parameter]
    public SwitchParameter IgnoreDiffs { get; set; }

    /// <summary>Filters results to only include backup chains for the specified database names.</summary>
    [Parameter(Position = 2)]
    public string[]? DatabaseName { get; set; }

    /// <summary>Filters results to only include backups from the specified server or availability group names.</summary>
    [Parameter(Position = 3)]
    public string[]? ServerName { get; set; }

    /// <summary>Output from Get-RestoreContinuableDatabase for resuming interrupted restores.</summary>
    [Parameter(Position = 4)]
    public object? ContinuePoints { get; set; }

    /// <summary>Output from Get-DbaDbRestoreHistory -Last for the target database.</summary>
    [Parameter(Position = 5)]
    public object? LastRestoreType { get; set; }

    private readonly List<object?> _internalHistory = new();
    private bool _ignoreFull;
    // PS mutates the function-scope $IgnoreDiffs inside the continue block, and the mutated
    // value LEAKS into later database iterations (cross-model review 2026-07-07 finding A6).
    private bool _ignoreDiffs;
    private bool _continue;

    protected override void BeginProcessing()
    {
        _ignoreFull = false;
        _ignoreDiffs = IgnoreDiffs.ToBool();
        if (TestBound("ContinuePoints") && ContinuePoints is not null)
        {
            WriteMessage(MessageLevel.Verbose, "ContinuePoints provided so setting up for a continue");
            _ignoreFull = true;
            _continue = true;
            if (TestBound("DatabaseName"))
            {
                List<object?> continueDatabases = CollectMember(ContinuePoints, "Database");
                List<string> kept = new();
                foreach (string name in DatabaseName ?? Array.Empty<string>())
                {
                    if (PsOps.In(name, continueDatabases))
                        kept.Add(name);
                }
                DatabaseName = kept.Count == 0 ? null : kept.ToArray();

                // PS computes $DroppedDatabases FROM THE ALREADY-FILTERED $DatabaseName
                // (assignment order), so it is provably always $null: the guarded
                // "$DroppedDatabases.join(',')" verbose line — which WOULD crash, join()
                // not being a method — is unreachable dead code. Nothing to emit or throw.
            }
            else
            {
                List<object?> continueDatabases = CollectMember(ContinuePoints, "Database");
                List<string> names = new();
                foreach (object? entry in continueDatabases)
                    names.Add(RestoreUtility.PsStringify(entry));
                DatabaseName = names.Count == 0 ? null : names.ToArray();
            }
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // PS: $internalHistory += $BackupHistory — array input concatenates (flattens one level).
        object? input = BackupHistory is PSObject psInput ? psInput.BaseObject : BackupHistory;
        if (input is IEnumerable items and not string)
        {
            foreach (object? item in items)
                _internalHistory.Add(item);
        }
        else if (BackupHistory is not null)
        {
            _internalHistory.Add(BackupHistory);
        }
    }

    protected override void EndProcessing()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (object? history in _internalHistory)
        {
            if (history is not null && !PsProperty.Has(history, "RestoreTime"))
            {
                PsProperty.AddNote(history, "RestoreTime", RestoreTime);
            }
        }
        if (TestBound("DatabaseName") && PsOps.IsTrue(DatabaseName))
        {
            WriteMessage(MessageLevel.Verbose, "Filtering by DatabaseName");
            //  $InternalHistory = $InternalHistory | Where-Object {$_.Database -in $DatabaseName}
        }

        List<object?> internalHistory = _internalHistory;

        // Check for AGs
        if (TestBound("ServerName"))
        {
            int agCount = 0;
            foreach (object? history in internalHistory)
            {
                // PS: $_.AvailabilityGroupName -ne '' — null counts as "not empty" here.
                if (!PsOps.Eq(PsProperty.Get(history, "AvailabilityGroupName"), ""))
                    agCount++;
            }
            if (agCount != 0)
            {
                WriteMessage(MessageLevel.Verbose, "Dealing with Availabilitygroups");
                List<object?> filtered = new();
                foreach (object? history in internalHistory)
                {
                    if (PsOps.In(PsProperty.Get(history, "AvailabilityGroupName"), ServerName))
                        filtered.Add(history);
                }
                internalHistory = filtered;
            }
            else
            {
                WriteMessage(MessageLevel.Verbose, "Filtering by ServerName");
                List<object?> filtered = new();
                foreach (object? history in internalHistory)
                {
                    if (PsOps.In(PsProperty.Get(history, "InstanceName"), ServerName))
                        filtered.Add(history);
                }
                internalHistory = filtered;
            }
        }

        // Select-Object -Property Database -unique: case-sensitive, first-seen order.
        List<string> databases = new();
        HashSet<string> seenDatabases = new(StringComparer.Ordinal);
        foreach (object? history in internalHistory)
        {
            string database = RestoreUtility.PsStringify(PsProperty.Get(history, "Database"));
            if (seenDatabases.Add(database))
                databases.Add(database);
        }
        if (_continue && databases.Count > 1 && (DatabaseName?.Length ?? 0) > 1)
        {
            StopFunction("Cannot perform continuing restores on multiple databases with renames, exiting");
            return;
        }

        // These leak across loop iterations in the PS source (no per-iteration scoping); preserved.
        object logBaseLsnRaw = System.Numerics.BigInteger.Zero;
        bool logBaseLsnAssigned = false;
        object? firstRecoveryForkId = null;

        foreach (string database in databases)
        {
            //Cope with restores renaming the db
            // $database = the name of database in the backups being scanned
            // $databasefilter = the name of the database the backups are being restore to/against
            object? databaseFilter;
            if (DatabaseName is not null)
            {
                databaseFilter = DatabaseName;
            }
            else
            {
                databaseFilter = database;
            }

            if (_continue)
            {
                //Test if Database is in a continuing state and the LSN to continue from:
                if (PsOps.In(databaseFilter, CollectMember(ContinuePoints, "Database")))
                {
                    WriteMessage(MessageLevel.Verbose, $"{database} in ContinuePoints, will attempt to continue");
                    _ignoreFull = true;
                    //Check what the last backup restored was
                    object? lastType = FirstMemberWhere(LastRestoreType, "Database", databaseFilter, "RestoreType");
                    if (PsOps.Eq(lastType, "log"))
                    {
                        //log Backup last restored, so diffs cannot be used
                        _ignoreDiffs = true;
                    }
                    else
                    {
                        //Last restore was a diff or full, so can restore diffs or logs
                        _ignoreDiffs = false;
                    }
                }
                else
                {
                    WriteMessage(MessageLevel.Warning, $"{database} not in ContinuePoints, will attempt normal restore");
                }
            }

            List<object?> dbHistory = new();
            List<object?> databaseHistory = new();
            foreach (object? history in internalHistory)
            {
                if (PsOps.Eq(PsProperty.Get(history, "Database"), database))
                    databaseHistory.Add(history);
            }

            object? full = null;
            //For a standard restore, work out the full backup
            if (!_ignoreFull)
            {
                full = SortByProperty(FilterTypeBefore(databaseHistory, RestoreTime, "Full", "Database"), true, "LastLsn").FirstOrDefault();
                if (PsOps.IsTrue(PsProperty.Get(full, "FullName")))
                {
                    PsProperty.Set(full!, "FullName", CollectFullNames(databaseHistory, PsProperty.Get(full, "BackupSetID"), "Full", "Database"));
                }
                else
                {
                    StopFunction("Fullname property not found. This could mean that a full backup could not be found or the command must be re-run with the -Continue switch.");
                    return;
                }
                dbHistory.Add(full);
            }
            else if (_ignoreFull && !_ignoreDiffs)
            {
                //Fake the Full backup
                WriteMessage(MessageLevel.Verbose, "Continuing, so setting a fake full backup from the existing database");
                PSObject fake = new();
                fake.Properties.Add(new PSNoteProperty("CheckpointLSN", FirstMemberWhere(ContinuePoints, "Database", databaseFilter, "differential_base_lsn")));
                full = fake;
            }

            if (!_ignoreDiffs)
            {
                WriteMessage(MessageLevel.Verbose, "processing diffs");
                List<object?> diffCandidates = new();
                foreach (object? history in FilterTypeBefore(databaseHistory, RestoreTime, "Differential", "Database Differential"))
                {
                    if (PsOps.Eq(PsProperty.Get(history, "DatabaseBackupLSN"), PsProperty.Get(full, "CheckpointLSN")))
                        diffCandidates.Add(history);
                }
                object? diff = SortByProperty(diffCandidates, true, "LastLsn").FirstOrDefault();
                if (diff is not null)
                {
                    if (PsOps.IsTrue(PsProperty.Get(diff, "FullName")))
                    {
                        PsProperty.Set(diff, "FullName", CollectFullNames(databaseHistory, PsProperty.Get(diff, "BackupSetID"), "Differential", "Database Differential"));
                    }
                    else
                    {
                        StopFunction("Fullname property not found. This could mean that a full backup could not be found or the command must be re-run with the -Continue switch.");
                        return;
                    }
                    dbHistory.Add(diff);
                }
            }

            //Sort out the LSN for the log restores
            object? newestInChain = SortByProperty(dbHistory, true, "LastLsn").FirstOrDefault();
            if (PsProperty.Get(newestInChain, "LastLsn") is not null)
            {
                //We have history so use this
                logBaseLsnRaw = PsLsn.ToBigInt(PsProperty.Get(newestInChain, "LastLsn"));
                logBaseLsnAssigned = true;
                firstRecoveryForkId = PsProperty.Get(full, "FirstRecoveryForkID");
                WriteMessage(MessageLevel.Verbose, $"Found LogBaseLsn: {logBaseLsnRaw} and FirstRecoveryForkID: {RestoreUtility.PsStringify(firstRecoveryForkId)}");
            }
            else
            {
                WriteMessage(MessageLevel.Verbose, "No full or diff, so attempting to pull from Continue informmation");
                try
                {
                    object? redoStart = FirstMemberWhere(ContinuePoints, "Database", databaseFilter, "redo_start_lsn");
                    if (redoStart is null)
                    {
                        // PS: [BigInt]$null assignment throws, landing in the catch below.
                        throw new PSInvalidCastException("Cannot convert null to type \"System.Numerics.BigInteger\".");
                    }
                    logBaseLsnRaw = PsLsn.ToBigInt(redoStart);
                    logBaseLsnAssigned = true;
                    firstRecoveryForkId = FirstMemberWhere(ContinuePoints, "Database", databaseFilter, "FirstRecoveryForkID");
                    WriteMessage(MessageLevel.Verbose, $"Found LogBaseLsn: {logBaseLsnRaw} and FirstRecoveryForkID: {RestoreUtility.PsStringify(firstRecoveryForkId)} from Continue information");
                }
                catch (Exception ex) when (ex is not InnerCommandException)
                {
                    // PS source has no return after this Stop-Function: under EnableException it
                    // throws; otherwise the loop body continues with the leaked LogBaseLsn value.
                    StopFunction($"Failed to find LSN or RecoveryForkID for {RestoreUtility.PsStringify(databaseFilter)}", target: databaseFilter, category: ErrorCategory.InvalidOperation);
                }
            }

            if (!IgnoreLogs.ToBool())
            {
                List<object?> filteredLogs = new();
                foreach (object? history in databaseHistory)
                {
                    // PS: $_.LastLSN -ge $LogBaseLsn — the LEFT operand's type drives conversion,
                    // so BigInteger histories compare numerically and string-typed (deserialized)
                    // histories compare as strings, both preserved via LanguagePrimitives.
                    if (PsString.In(RestoreUtility.PsStringify(PsProperty.Get(history, "Type")), "Log", "Transaction Log")
                        && PsOps.Compare(PsProperty.Get(history, "Start"), RestoreTime) < 0
                        && PsOps.Compare(PsProperty.Get(history, "LastLSN"), logBaseLsnRaw) >= 0
                        && !PsOps.Eq(PsProperty.Get(history, "FirstLSN"), PsProperty.Get(history, "LastLSN")))
                    {
                        filteredLogs.Add(history);
                    }
                }
                _ = logBaseLsnAssigned;
                List<object?> sortedLogs = SortByProperty(filteredLogs, false, "LastLsn", "FirstLsn");

                // Group-Object -Property BackupSetID: case-insensitive keys, first-seen order.
                Dictionary<string, List<object?>> groups = new(StringComparer.OrdinalIgnoreCase);
                List<string> groupOrder = new();
                foreach (object? log in sortedLogs)
                {
                    string key = RestoreUtility.PsStringify(PsProperty.Get(log, "BackupSetID"));
                    if (!groups.TryGetValue(key, out List<object?>? bucket))
                    {
                        bucket = new List<object?>();
                        groups.Add(key, bucket);
                        groupOrder.Add(key);
                    }
                    bucket.Add(log);
                }
                foreach (string key in groupOrder)
                {
                    List<object?> group = groups[key];
                    object? log = group[0];
                    PsProperty.Set(log!, "FullName", FlattenMember(group, "FullName"));
                    dbHistory.Add(log);
                }
                // Get Last T-log

                List<object?> lastLogCandidates = new();
                foreach (object? history in databaseHistory)
                {
                    if (PsString.In(RestoreUtility.PsStringify(PsProperty.Get(history, "Type")), "Log", "Transaction Log")
                        && PsOps.Compare(PsProperty.Get(history, "End"), RestoreTime) >= 0
                        && PsOps.Compare(PsProperty.Get(history, "DatabaseBackupLSN"), PsProperty.Get(full, "CheckpointLSN")) >= 0)
                    {
                        lastLogCandidates.Add(history);
                    }
                }
                object? lastLog = SortByProperty(lastLogCandidates, false, "LastLsn", "FirstLsn").FirstOrDefault();
                if (lastLog is not null)
                {
                    List<object?> sameSet = new();
                    foreach (object? history in databaseHistory)
                    {
                        if (PsOps.Eq(PsProperty.Get(history, "BackupSetID"), PsProperty.Get(lastLog, "BackupSetID")))
                            sameSet.Add(history);
                    }
                    PsProperty.Set(lastLog, "FullName", FlattenMember(sameSet, "FullName"));
                }
                // PS: $dbHistory += $lastLog — when no last log matched, Select-Object -First 1
                // returned AutomationNull, and += with AutomationNull appends NOTHING
                // (empirically verified on the lab, 2026-07-07). Only a real match appends.
                if (lastLog is not null)
                {
                    dbHistory.Add(lastLog);
                }
            }
            foreach (object? item in dbHistory)
                WriteObject(item);
        }
    }

    private List<object?> FilterTypeBefore(List<object?> databaseHistory, DateTime restoreTime, params string[] types)
    {
        List<object?> matches = new();
        foreach (object? history in databaseHistory)
        {
            if (PsString.In(RestoreUtility.PsStringify(PsProperty.Get(history, "Type")), types)
                && PsOps.Compare(PsProperty.Get(history, "End"), restoreTime) <= 0)
            {
                matches.Add(history);
            }
        }
        return matches;
    }

    private static object? CollectFullNames(List<object?> databaseHistory, object? backupSetId, params string[] types)
    {
        List<object?> matches = new();
        foreach (object? history in databaseHistory)
        {
            if (PsString.In(RestoreUtility.PsStringify(PsProperty.Get(history, "Type")), types)
                && PsOps.Eq(PsProperty.Get(history, "BackupSetID"), backupSetId))
            {
                matches.Add(history);
            }
        }
        return FlattenMember(matches, "FullName");
    }

    // Member enumeration (.Property over a collection): flattens one level; a single result
    // stays scalar, exactly like PS.
    private static object? FlattenMember(List<object?> items, string propertyName)
    {
        List<object?> values = new();
        foreach (object? item in items)
        {
            object? value = PsProperty.Get(item, propertyName);
            if (value is IEnumerable nested and not string)
            {
                foreach (object? inner in nested)
                    values.Add(inner);
            }
            else if (value is not null)
            {
                values.Add(value);
            }
        }
        if (values.Count == 1)
            return values[0];
        return values.ToArray();
    }

    private static List<object?> CollectMember(object? source, string propertyName)
    {
        List<object?> values = new();
        object? unwrapped = source is PSObject psSource ? psSource.BaseObject : source;
        if (unwrapped is IEnumerable items and not string)
        {
            foreach (object? item in items)
                values.Add(PsProperty.Get(item, propertyName));
        }
        else if (source is not null)
        {
            values.Add(PsProperty.Get(source, propertyName));
        }
        return values;
    }

    // (X | Where-Object { $_.Database -eq $filter }).<Member> — first the filter, then member
    // enumeration collapsed to the scalar-or-array shape the PS call sites consume.
    private static object? FirstMemberWhere(object? source, string matchProperty, object? matchValue, string memberName)
    {
        List<object?> matches = new();
        object? unwrapped = source is PSObject psSource ? psSource.BaseObject : source;
        if (unwrapped is IEnumerable items and not string)
        {
            foreach (object? item in items)
            {
                if (PsOps.Eq(PsProperty.Get(item, matchProperty), matchValue))
                    matches.Add(item);
            }
        }
        else if (source is not null)
        {
            if (PsOps.Eq(PsProperty.Get(source, matchProperty), matchValue))
                matches.Add(source);
        }
        object? flat = FlattenMember(matches, memberName);
        return flat is object[] { Length: 0 } ? null : flat;
    }

    private static List<object?> SortByProperty(List<object?> items, bool descending, params string[] properties)
    {
        IOrderedEnumerable<object?>? ordered = null;
        foreach (string property in properties)
        {
            string local = property;
            if (ordered is null)
            {
                ordered = descending
                    ? items.OrderByDescending(x => PsProperty.Get(x, local), PsComparer.Instance)
                    : items.OrderBy(x => PsProperty.Get(x, local), PsComparer.Instance);
            }
            else
            {
                ordered = descending
                    ? ordered.ThenByDescending(x => PsProperty.Get(x, local), PsComparer.Instance)
                    : ordered.ThenBy(x => PsProperty.Get(x, local), PsComparer.Instance);
            }
        }
        return ordered is null ? new List<object?>(items) : ordered.ToList();
    }

    private sealed class PsComparer : IComparer<object?>
    {
        public static readonly PsComparer Instance = new();

        public int Compare(object? x, object? y)
        {
            return PsOps.Compare(x, y);
        }
    }
}
