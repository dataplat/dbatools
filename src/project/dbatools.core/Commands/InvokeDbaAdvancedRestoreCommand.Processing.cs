#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

public sealed partial class InvokeDbaAdvancedRestoreCommand
{
    protected override void EndProcessing()
    {
        if (Interrupted)
        {
            return;
        }
        bool withReplace = WithReplace.ToBool();
        if (Continue.ToBool())
        {
            withReplace = true;
        }
        // $script and $ExitError leak across loop iterations in the PS source; preserved.
        string? script = null;
        object? exitError = null;

        List<string> databases = new();
        HashSet<string> seenDatabases = new(StringComparer.Ordinal);
        foreach (object? history in _internalHistory)
        {
            string database = RestoreUtility.PsStringify(PsProperty.Get(history, "Database"));
            if (seenDatabases.Add(database))
                databases.Add(database);
        }

        foreach (string database in databases)
        {
            DateTime databaseRestoreStartTime = DateTime.Now;
            bool databaseExists = false;
            foreach (Microsoft.SqlServer.Management.Smo.Database existing in _server!.Databases)
            {
                if (PsOps.Eq(existing.Name, database))
                {
                    databaseExists = true;
                    break;
                }
            }
            bool isManagedInstance = PsOps.Eq(_server.DatabaseEngineEdition, "SqlManagedInstance");
            if (databaseExists)
            {
                if (!OutputScriptOnly.ToBool() && !VerifyOnly.ToBool() && !isManagedInstance)
                {
                    if (ShouldProcess($"Killing processes in {database} on {RestoreUtility.PsStringify(SqlInstance)} as it exists and WithReplace specified  \n", "Cannot proceed if processes exist, ", "Database Exists and WithReplace specified, need to kill processes to restore"))
                    {
                        try
                        {
                            WriteMessage(MessageLevel.Verbose, $"Killing processes on {database}");
                            Hashtable stopParms = new()
                            {
                                ["SqlInstance"] = _server,
                                ["Database"] = database,
                                ["WarningAction"] = "SilentlyContinue"
                            };
                            NestedCommand.Invoke(this, "Stop-DbaProcess", stopParms);
                            // BP-102: bracket-quoted identifier (the PS source interpolated the raw name).
                            string quoted = new Microsoft.Data.SqlClient.SqlCommandBuilder().QuoteIdentifier(database);
                            _server.Databases["master"].ExecuteWithResults($"ALTER DATABASE {quoted} SET OFFLINE WITH ROLLBACK IMMEDIATE; ALTER DATABASE {quoted} SET RESTRICTED_USER; ALTER DATABASE {quoted} SET ONLINE WITH ROLLBACK IMMEDIATE");
                            _server.ConnectionContext.Connect();
                        }
                        catch
                        {
                            WriteMessage(MessageLevel.Verbose, $"No processes to kill in {database}");
                        }
                    }
                }
                else if (!OutputScriptOnly.ToBool() && !VerifyOnly.ToBool() && isManagedInstance)
                {
                    if (ShouldProcess($"Dropping {database} on {RestoreUtility.PsStringify(SqlInstance)} as it exists and WithReplace specified  \n", "Cannot proceed if database exist, ", "Database Exists and WithReplace specified, need to drop database to restore"))
                    {
                        try
                        {
                            WriteMessage(MessageLevel.Verbose, $"{RestoreUtility.PsStringify(SqlInstance)} is a Managed instance so dropping database was WithReplace not supported");
                            Hashtable stopParms = new()
                            {
                                ["SqlInstance"] = _server,
                                ["Database"] = database,
                                ["WarningAction"] = "SilentlyContinue"
                            };
                            NestedCommand.Invoke(this, "Stop-DbaProcess", stopParms);
                            Hashtable removeParms = new()
                            {
                                ["SqlInstance"] = _server,
                                ["Database"] = database,
                                ["Confirm"] = false
                            };
                            NestedCommand.Invoke(this, "Remove-DbaDatabase", removeParms);
                            _server.ConnectionContext.Connect();
                        }
                        catch
                        {
                            WriteMessage(MessageLevel.Verbose, $"No processes to kill in {database}");
                        }
                    }
                }
                else if (!withReplace && !VerifyOnly.ToBool())
                {
                    WriteMessage(MessageLevel.Verbose, $"{database} exists and WithReplace not specified, stopping");
                    continue;
                }
            }
            WriteMessage(MessageLevel.Debug, $"WithReplace  = {PsBool.Text(withReplace)}");

            List<object?> backups = new();
            foreach (object? history in _internalHistory)
            {
                if (PsOps.Eq(PsProperty.Get(history, "Database"), database))
                    backups.Add(history);
            }
            backups = SortBackups(backups);
            int backupCnt = 1;
            bool endEntireCommand = false;
            bool breakBackupLoop = false;

            for (int backupIndex = 0; backupIndex < backups.Count; backupIndex++)
            {
                object? backup = backups[backupIndex];
                DateTime fileRestoreStartTime = DateTime.Now;
                Restore restore = new();
                bool isLastBackup = backupIndex == backups.Count - 1;
                if (!isLastBackup || _noRecoveryEffective)
                {
                    restore.NoRecovery = true;
                }
                else if (isLastBackup && StandbyDirectory != "")
                {
                    restore.StandbyFile = StandbyDirectory + "\\" + database + DateTime.Now.ToString("yyyyMMddHHmmss", System.Globalization.CultureInfo.InvariantCulture) + ".bak";
                    WriteMessage(MessageLevel.Verbose, $"Setting standby on last file {restore.StandbyFile}");
                }
                else
                {
                    restore.NoRecovery = false;
                }
                if (!string.IsNullOrEmpty(StopAtLsn))
                {
                    if (StopBefore.ToBool())
                    {
                        restore.StopBeforeMarkName = $"lsn:{StopAtLsn}";
                    }
                    else
                    {
                        restore.StopAtMarkName = $"lsn:{StopAtLsn}";
                    }
                }
                else if (!string.IsNullOrEmpty(StopMark))
                {
                    // PS: an unbound [datetime]$StopAfterDate reads $null (NOT DateTime.MinValue -
                    // lane-B empirical proof on PS 7.6.3, W3-058 reopen 2026-07-16), so the source's
                    // `$null -ne $StopAfterDate` gate skips the AfterDate assignment entirely unless
                    // the parameter was bound; a bound null is impossible ([datetime] rejects it at
                    // binding), so TestBound is exactly the source's gate.
                    if (StopBefore.ToBool())
                    {
                        restore.StopBeforeMarkName = StopMark;
                        if (TestBound(nameof(StopAfterDate)))
                        {
                            // SMO's AfterDate properties are strings; PS coerced the DateTime the same way.
                            restore.StopBeforeMarkAfterDate = (string)LanguagePrimitives.ConvertTo(StopAfterDate, typeof(string), System.Globalization.CultureInfo.InvariantCulture);
                        }
                    }
                    else
                    {
                        restore.StopAtMarkName = StopMark;
                        if (TestBound(nameof(StopAfterDate)))
                        {
                            restore.StopAtMarkAfterDate = (string)LanguagePrimitives.ConvertTo(StopAfterDate, typeof(string), System.Globalization.CultureInfo.InvariantCulture);
                        }
                    }
                }
                else if (RestoreTime > DateTime.Now
                    || PsOps.Compare(PsProperty.Get(backup, "RestoreTime"), DateTime.Now) > 0
                    || EqAnyTruthy(PsProperty.Get(backup, "RecoveryModel"), "Simple"))
                {
                    restore.ToPointInTime = null;
                }
                else
                {
                    object? backupRestoreTime = PsProperty.Get(backup, "RestoreTime");
                    if (!PsOps.Eq(RestoreTime, backupRestoreTime))
                    {
                        DateTime pit = (DateTime)LanguagePrimitives.ConvertTo(backupRestoreTime, typeof(DateTime), System.Globalization.CultureInfo.InvariantCulture);
                        restore.ToPointInTime = pit.ToString("yyyy-MM-ddTHH:mm:ss.fff", System.Globalization.CultureInfo.InvariantCulture);
                    }
                    else
                    {
                        restore.ToPointInTime = RestoreTime.ToString("yyyy-MM-ddTHH:mm:ss.fff", System.Globalization.CultureInfo.InvariantCulture);
                    }
                }

                restore.Database = database;
                if (!isManagedInstance)
                {
                    restore.ReplaceDatabase = withReplace;
                }
                if (MaxTransferSize != 0)
                {
                    restore.MaxTransferSize = MaxTransferSize;
                }
                if (BufferCount != 0)
                {
                    restore.BufferCount = BufferCount;
                }
                if (BlockSize != 0)
                {
                    restore.BlockSize = BlockSize;
                }
                if (Checksum.ToBool())
                {
                    restore.Checksum = true;
                }
                if (Restart.ToBool())
                {
                    restore.Restart = true;
                }
                if (KeepReplication.ToBool())
                {
                    restore.KeepReplication = true;
                }
                if (!Continue.ToBool() && _pages is null)
                {
                    if (PsProperty.Get(backup, "FileList") is IEnumerable fileList and not string)
                    {
                        foreach (object? file in fileList)
                        {
                            RelocateFile moveFile = new();
                            moveFile.LogicalFileName = RestoreUtility.PsStringify(PsProperty.Get(file, "LogicalName"));
                            moveFile.PhysicalFileName = RestoreUtility.PsStringify(PsProperty.Get(file, "PhysicalName"));
                            restore.RelocateFiles.Add(moveFile);
                        }
                    }
                }
                object? backupType = PsProperty.Get(backup, "Type");
                string action;
                if (PsOps.Eq(backupType, "1"))
                    action = "Database";
                else if (PsOps.Eq(backupType, "2"))
                    action = "Log";
                else if (PsOps.Eq(backupType, "5"))
                    action = "Database";
                else if (PsOps.Eq(backupType, "Transaction Log"))
                    action = "Log";
                else
                    action = "Database";

                WriteMessage(MessageLevel.Debug, $"restore action = {action}");
                restore.Action = action == "Log" ? RestoreActionType.Log : RestoreActionType.Database;
                List<string> fullNames = FlattenToStrings(PsProperty.Get(backup, "FullName"));
                foreach (string file in fullNames)
                {
                    WriteMessage(MessageLevel.Debug, $"Adding device {file}");
                    BackupDeviceItem device = new();
                    device.Name = file;
                    if (file.StartsWith("http", StringComparison.OrdinalIgnoreCase) || file.StartsWith("s3", StringComparison.OrdinalIgnoreCase))
                    {
                        device.DeviceType = DeviceType.Url;
                    }
                    else
                    {
                        device.DeviceType = DeviceType.File;
                    }

                    if (PsOps.IsTrue(StorageCredential))
                    {
                        restore.CredentialName = StorageCredential;
                    }

                    restore.FileNumber = (int)LanguagePrimitives.ConvertTo(PsProperty.Get(backup, "Position") ?? 0, typeof(int), System.Globalization.CultureInfo.InvariantCulture);
                    restore.Devices.Add(device);
                }
                WriteMessage(MessageLevel.Verbose, "Performing restore action");
                if (ShouldProcess(RestoreUtility.PsStringify(SqlInstance), $"Restoring {database} to {RestoreUtility.PsStringify(SqlInstance)} based on these files: {string.Join(", ", fullNames)}"))
                {
                    bool restoreComplete = true;
                    try
                    {
                        string? executeAsLogin = null;
                        if (ExecuteAs != "" && backupCnt == 1)
                        {
                            executeAsLogin = ExecuteAs!.Replace("'", "''");
                        }
                        if ((KeepCDC.ToBool() || ErrorBrokerConversations.ToBool()) && restore.NoRecovery == false)
                        {
                            script = ScriptToString(restore.Script(_server));
                            List<string> withOptions = new();
                            if (KeepCDC.ToBool())
                            {
                                withOptions.Add("KEEP_CDC");
                            }
                            if (ErrorBrokerConversations.ToBool())
                            {
                                withOptions.Add("ERROR_BROKER_CONVERSATIONS");
                            }
                            if (script.IndexOf("WITH", StringComparison.OrdinalIgnoreCase) >= 0)
                            {
                                script = script.TrimEnd() + " , " + string.Join(" , ", withOptions);
                            }
                            else
                            {
                                script = script.TrimEnd() + " WITH " + string.Join(" , ", withOptions);
                            }
                            if (executeAsLogin is not null)
                            {
                                script = $"EXECUTE AS LOGIN='{executeAsLogin}'; " + script;
                            }
                            if (!OutputScriptOnly.ToBool())
                            {
                                ProgressBridge.Write(this, 1, $"Restoring {database} to {RestoreUtility.PsStringify(SqlInstance)} - Backup {backupCnt} of {backups.Count}", status: string.Format(System.Globalization.CultureInfo.InvariantCulture, "Progress: {0} %", 0), percentComplete: 0);
                                _server.ConnectionContext.ExecuteNonQuery(script);
                                ProgressBridge.Write(this, 1, $"Restoring {database} to {RestoreUtility.PsStringify(SqlInstance)} - Backup {backupCnt} of {backups.Count}", status: "Complete", completed: true);
                            }
                        }
                        else if (_pages is not null && action == "Database")
                        {
                            script = ScriptToString(restore.Script(_server));
                            script = System.Text.RegularExpressions.Regex.Replace(script, System.Text.RegularExpressions.Regex.Escape("] FROM"), $"] PAGE='{_pages}' FROM");
                            if (!OutputScriptOnly.ToBool())
                            {
                                ProgressBridge.Write(this, 1, $"Restoring {database} to {RestoreUtility.PsStringify(SqlInstance)} - Backup {backupCnt} of {backups.Count}", status: string.Format(System.Globalization.CultureInfo.InvariantCulture, "Progress: {0} %", 0), percentComplete: 0);
                                _server.ConnectionContext.ExecuteNonQuery(script);
                                ProgressBridge.Write(this, 1, $"Restoring {database} to {RestoreUtility.PsStringify(SqlInstance)} - Backup {backupCnt} of {backups.Count}", status: "Complete", completed: true);
                            }
                        }
                        else if (OutputScriptOnly.ToBool())
                        {
                            script = ScriptToString(restore.Script(_server));
                            if (executeAsLogin is not null)
                            {
                                script = $"EXECUTE AS LOGIN='{executeAsLogin}'; " + script;
                            }
                        }
                        else if (VerifyOnly.ToBool())
                        {
                            WriteMessage(MessageLevel.Verbose, "VerifyOnly restore");
                            ProgressBridge.Write(this, 1, $"Verifying {database} backup file on {RestoreUtility.PsStringify(SqlInstance)} - Backup {backupCnt} of {backups.Count}", status: string.Format(System.Globalization.CultureInfo.InvariantCulture, "Progress: {0} %", 0), percentComplete: 0);
                            bool verify = restore.SqlVerify(_server);
                            ProgressBridge.Write(this, 1, $"Verifying {database} backup file on {RestoreUtility.PsStringify(SqlInstance)} - Backup {backupCnt} of {backups.Count}", status: "Complete", completed: true);
                            if (verify)
                            {
                                WriteMessage(MessageLevel.Verbose, "VerifyOnly restore Succeeded");
                                restoreComplete = true;
                                // PS: return "Verify successful" — the string is emitted, the
                                // finally below still emits its result object, then the whole
                                // command ends. Preserved.
                                WriteObject("Verify successful");
                                endEntireCommand = true;
                            }
                            else
                            {
                                WriteMessage(MessageLevel.Warning, "VerifyOnly restore Failed");
                                restoreComplete = false;
                                WriteObject("Verify failed");
                                endEntireCommand = true;
                            }
                        }
                        else
                        {
                            double outerProgress = backupCnt / (double)backups.Count * 100;
                            if (backupCnt == 1)
                            {
                                ProgressBridge.Write(this, 1, $"Restoring {database} to {RestoreUtility.PsStringify(SqlInstance)} - Backup {backupCnt} of {backups.Count}", percentComplete: 0);
                            }
                            ProgressBridge.Write(this, 2, $"Restore {string.Join(",", fullNames)}", percentComplete: 0, parentActivityId: 1);
                            script = ScriptToString(restore.Script(_server));
                            if (executeAsLogin is not null)
                            {
                                ProgressBridge.Write(this, 1, $"Restoring {database} to {RestoreUtility.PsStringify(SqlInstance)} - Backup {backupCnt} of {backups.Count}", status: string.Format(System.Globalization.CultureInfo.InvariantCulture, "Progress: {0} %", 0), percentComplete: 0);
                                script = $"EXECUTE AS LOGIN='{executeAsLogin}'; " + script;
                                _server.ConnectionContext.ExecuteNonQuery(script);
                                ProgressBridge.Write(this, 1, $"Restoring {database} to {RestoreUtility.PsStringify(SqlInstance)} - Backup {backupCnt} of {backups.Count}", status: "Complete", completed: true);
                            }
                            else
                            {
                                string deviceNames = string.Join(",", fullNames);
                                restore.PercentComplete += (sender, e) =>
                                {
                                    ProgressBridge.Write(this, 2, $"Restore {deviceNames}", status: string.Format(System.Globalization.CultureInfo.InvariantCulture, "Progress: {0} %", e.Percent), percentComplete: e.Percent, parentActivityId: 1);
                                };
                                restore.PercentCompleteNotification = 1;
                                restore.SqlRestore(_server);
                                ProgressBridge.Write(this, 2, $"Restore {deviceNames}", parentActivityId: 1, completed: true);
                                RestoreUtility.AddTeppCacheItem(this, (DbaInstanceParameter)LanguagePrimitives.ConvertTo(_server, typeof(DbaInstanceParameter), System.Globalization.CultureInfo.InvariantCulture), "database", database);
                            }
                            ProgressBridge.Write(this, 1, $"Restoring {database} to {RestoreUtility.PsStringify(SqlInstance)} - Backup {backupCnt} of {backups.Count}", status: string.Format(System.Globalization.CultureInfo.InvariantCulture, "Progress: {0:N2} %", outerProgress), percentComplete: (int)outerProgress);
                        }
                    }
                    catch (Exception ex)
                    {
                        WriteMessage(MessageLevel.Verbose, "Failed, Closing Server connection");
                        restoreComplete = false;
                        exitError = ex.InnerException;
                        ErrorRecord record = new(ex, "dbatools_Invoke-DbaAdvancedRestore", ErrorCategory.NotSpecified, database);
                        try
                        {
                            StopFunction($"Failed to restore db {database}, stopping", errorRecord: record, continueLoop: true);
                        }
                        finally
                        {
                            breakBackupLoop = true;
                        }
                    }
                    finally
                    {
                        if (!OutputScriptOnly.ToBool())
                        {
                            EmitRestoreResult(backup, backups, database, withReplace, restoreComplete, restore, script, exitError, fileRestoreStartTime, databaseRestoreStartTime);
                        }
                        else
                        {
                            WriteObject(script);
                        }
                        if (restore.Devices.Count > 0)
                        {
                            restore.Devices.Clear();
                        }
                        WriteMessage(MessageLevel.Verbose, "Closing Server connection");
                        // Parity with the PS source: the pooled connection is dropped after every
                        // file and transparently reopens on next use (deliberate BP-002 deviation).
                        _server.ConnectionContext.Disconnect();
                    }
                }
                if (breakBackupLoop || endEntireCommand)
                {
                    break;
                }
                backupCnt++;
            }
            if (endEntireCommand)
            {
                return;
            }
            ProgressBridge.Write(this, 2, "Finished", completed: true);
            // PS: if ($server.ConnectionContext.exists) — no such property, so this never fires. Preserved.
            if (PsOps.IsTrue(PsProperty.Get(_server.ConnectionContext, "exists")))
            {
                _server.ConnectionContext.Disconnect();
            }
            ProgressBridge.Write(this, 1, "Finished", completed: true);
        }
    }

    // SMO Restore.Script returns a StringCollection; a plain RESTORE scripts to a single
    // batch, which PS member enumeration collapsed to that one string. Multi-batch output
    // (never observed for RESTORE) joins with the $OFS space PS coercion would apply.
    private static string ScriptToString(System.Collections.Specialized.StringCollection scripts)
    {
        if (scripts.Count == 1)
            return scripts[0] ?? "";
        string[] parts = new string[scripts.Count];
        scripts.CopyTo(parts, 0);
        return string.Join(" ", parts);
    }

    private static bool EqAnyTruthy(object? lhs, object? rhs)
    {
        // PS: $backup.RecoveryModel -eq 'Simple' — an array left operand filters and the
        // result's truthiness is "any match".
        if (lhs is PSObject psLhs)
            lhs = psLhs.BaseObject;
        if (lhs is IEnumerable items and not string)
        {
            foreach (object? item in items)
            {
                if (PsOps.Eq(item, rhs))
                    return true;
            }
            return false;
        }
        return PsOps.Eq(lhs, rhs);
    }

    private static List<string> FlattenToStrings(object? value)
    {
        List<string> results = new();
        if (value is PSObject psValue)
            value = psValue.BaseObject;
        if (value is IEnumerable items and not string)
        {
            foreach (object? item in items)
            {
                if (item is not null)
                    results.Add(RestoreUtility.PsStringify(item));
            }
        }
        else if (value is not null)
        {
            results.Add(RestoreUtility.PsStringify(value));
        }
        return results;
    }

    private List<object?> SortBackups(List<object?> backups)
    {
        List<KeyValuePair<int, object?>> keyed = new();
        for (int n = 0; n < backups.Count; n++)
            keyed.Add(new KeyValuePair<int, object?>(n, backups[n]));
        keyed.Sort((a, b) =>
        {
            int byType = PsOps.Compare(PsProperty.Get(a.Value, "Type"), PsProperty.Get(b.Value, "Type"));
            if (byType != 0)
                return byType;
            int byLsn = PsOps.Compare(PsProperty.Get(a.Value, "FirstLsn"), PsProperty.Get(b.Value, "FirstLsn"));
            if (byLsn != 0)
                return byLsn;
            return a.Key.CompareTo(b.Key);
        });
        List<object?> sorted = new();
        foreach (KeyValuePair<int, object?> pair in keyed)
            sorted.Add(pair.Value);
        return sorted;
    }
}
