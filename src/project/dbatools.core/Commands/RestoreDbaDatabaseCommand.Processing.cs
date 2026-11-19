#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

public sealed partial class RestoreDbaDatabaseCommand
{
    protected override void BeginProcessing()
    {
        DestinationDataDirectory = RestoreUtility.PsString(DestinationDataDirectory);
        DestinationLogDirectory = RestoreUtility.PsString(DestinationLogDirectory);
        DestinationFileStreamDirectory = RestoreUtility.PsString(DestinationFileStreamDirectory);
        DestinationFilePrefix = RestoreUtility.PsString(DestinationFilePrefix);
        RestoredDatabaseNamePrefix = RestoreUtility.PsString(RestoredDatabaseNamePrefix);
        StandbyDirectory = RestoreUtility.PsString(StandbyDirectory);
        ExecuteAs = RestoreUtility.PsString(ExecuteAs);
        StorageCredential = RestoreUtility.PsString(StorageCredential);
        DestinationFileSuffix = RestoreUtility.PsString(DestinationFileSuffix);
        StopMark = RestoreUtility.PsString(StopMark);
        StopAtLsn = RestoreUtility.PsString(StopAtLsn);
        PageRestoreTailFolder = RestoreUtility.PsString(PageRestoreTailFolder);
        _databaseName = DatabaseName;
        _withReplace = WithReplace.ToBool();

        WriteMessage(MessageLevel.InternalComment, "Starting");
        WriteMessage(MessageLevel.Debug, $"Parameters bound: {string.Join(", ", MyInvocation.BoundParameters.Keys)}");

        //region Validation
        try
        {
            SmoConnectionRequest request = new()
            {
                Instance = SqlInstance,
                SqlCredential = SqlCredential,
                Database = "master"
            };
            _restoreInstance = ConnectionService.GetServer(request);
            SetActiveConnection(_restoreInstance.ConnectionContext);
        }
        catch (Exception ex)
        {
            ErrorRecord record = new(ex, "dbatools_Restore-DbaDatabase", ErrorCategory.ConnectionError, SqlInstance);
            StopFunction("Failure", target: SqlInstance, errorRecord: record, category: ErrorCategory.ConnectionError);
            return;
        }

        if (PsOps.Eq(_restoreInstance.DatabaseEngineEdition, "SqlManagedInstance"))
        {
            WriteMessage(MessageLevel.Verbose, "Restore target is a Managed Instance, restricted feature set available");
            // The "StandbyDirecttory" entry reproduces the PS source list verbatim (typo included).
            string[] miParams = { "DestinationDataDirectory", "DestinationLogDirectory", "DestinationFileStreamDirectory", "XpDirTree", "FileMapping", "UseDestinationDefaultDirectories", "ReuseSourceFolderStructure", "DestinationFilePrefix", "StandbyDirecttory", "ReplaceDbNameInFile", "KeepCDC" };
            foreach (string miParam in miParams)
            {
                if (TestBound(miParam))
                {
                    // Write-Message -Level Warning "Restoring to a Managed SQL Instance, parameter $MiParm is not supported"
                    StopFunction($"The parameter {miParam} cannot be used with a Managed SQL Instance", category: ErrorCategory.InvalidArgument);
                    return;
                }
            }
        }

        if (ParameterSetName == "Restore")
        {
            _useDestinationDefaultDirectories = true;
            int paramCount = 0;

            if (TestBound("FileMapping"))
            {
                paramCount += 1;
            }
            if (TestBound("ExecuteAs"))
            {
                Hashtable loginParms = new()
                {
                    ["SqlInstance"] = _restoreInstance,
                    ["Login"] = ExecuteAs
                };
                Collection<PSObject> login = NestedCommand.Invoke(this, "Get-DbaLogin", loginParms);
                if (login.Count == 0)
                {
                    StopFunction($"You specified a Login to execute the restore, but the login '{ExecuteAs}' does not exist", category: ErrorCategory.InvalidArgument);
                    return;
                }
            }
            if (TestBound("ReuseSourceFolderStructure"))
            {
                paramCount += 1;
            }
            if (TestBound("DestinationDataDirectory"))
            {
                paramCount += 1;
            }
            if (paramCount > 1)
            {
                StopFunction("You've specified incompatible Location parameters. Please only specify one of FileMapping, ReuseSourceFolderStructure or DestinationDataDirectory", category: ErrorCategory.InvalidArgument);
                return;
            }
            if (ReplaceDbNameInFile.ToBool() && !TestBound("DatabaseName"))
            {
                StopFunction("To use ReplaceDbNameInFile you must specify DatabaseName", category: ErrorCategory.InvalidArgument);
                return;
            }

            if (TestBound("DestinationLogDirectory") && TestBound("ReuseSourceFolderStructure"))
            {
                StopFunction("The parameters DestinationLogDirectory and UseDestinationDefaultDirectories are mutually exclusive", category: ErrorCategory.InvalidArgument);
                return;
            }
            if (TestBound("DestinationLogDirectory") && !TestBound("DestinationDataDirectory"))
            {
                StopFunction("The parameter DestinationLogDirectory can only be specified together with DestinationDataDirectory", category: ErrorCategory.InvalidArgument);
                return;
            }
            if (TestBound("DestinationFileStreamDirectory") && TestBound("ReuseSourceFolderStructure"))
            {
                StopFunction("The parameters DestinationFileStreamDirectory and UseDestinationDefaultDirectories are mutually exclusive", category: ErrorCategory.InvalidArgument);
                return;
            }
            if (TestBound("DestinationFileStreamDirectory") && !TestBound("DestinationDataDirectory"))
            {
                StopFunction("The parameter DestinationFileStreamDirectory can only be specified together with DestinationDataDirectory", category: ErrorCategory.InvalidArgument);
                return;
            }
            if (TestBound("ReuseSourceFolderStructure") && TestBound("UseDestinationDefaultDirectories"))
            {
                StopFunction("The parameters UseDestinationDefaultDirectories and ReuseSourceFolderStructure cannot both be applied ", category: ErrorCategory.InvalidArgument);
                return;
            }

            if (FileMapping is not null || ReuseSourceFolderStructure.ToBool() || DestinationDataDirectory != "")
            {
                _useDestinationDefaultDirectories = false;
            }
            if ((MaxTransferSize % 65536) != 0 || MaxTransferSize > 4194304)
            {
                StopFunction("MaxTransferSize value must be a multiple of 64kb and no greater than 4MB", category: ErrorCategory.InvalidArgument);
                return;
            }
            if (BlockSize != 0)
            {
                if (BlockSize is not (512 or 1024 or 2048 or 4096 or 8192 or 16384 or 32768 or 65536))
                {
                    StopFunction("Block size must be one of 0.5kb,1kb,2kb,4kb,8kb,16kb,32kb,64kb", category: ErrorCategory.InvalidArgument);
                    return;
                }
            }
            if (StandbyDirectory != "")
            {
                Hashtable standbyParms = new()
                {
                    ["Path"] = StandbyDirectory,
                    ["SqlInstance"] = _restoreInstance
                };
                Collection<PSObject> standbyOk = NestedCommand.Invoke(this, "Test-DbaPath", standbyParms);
                if (!(standbyOk.Count > 0 && LanguagePrimitives.IsTrue(standbyOk.Count == 1 ? standbyOk[0] : standbyOk)))
                {
                    // PS interpolates the never-assigned $SqlServer variable here — it renders empty.
                    StopFunction($" cannot see the specified Standby Directory {StandbyDirectory}", target: SqlInstance);
                    return;
                }
            }
            if (KeepCDC.ToBool() && (NoRecovery.ToBool() || StandbyDirectory != ""))
            {
                StopFunction("KeepCDC cannot be specified with Norecovery or Standby as it needs recovery to work", category: ErrorCategory.InvalidArgument);
                return;
            }
            if (Continue.ToBool())
            {
                WriteMessage(MessageLevel.Verbose, "Called with continue, so assume we have an existing db in norecovery");
                _withReplace = true;
                _continuePoints = RestoreUtility.GetRestoreContinuableDatabase(this, _restoreInstance);
                Hashtable historyParms = new()
                {
                    ["SqlInstance"] = _restoreInstance,
                    ["Last"] = true
                };
                Collection<PSObject> lastRestore = NestedCommand.Invoke(this, "Get-DbaDbRestoreHistory", historyParms);
                _lastRestoreType = lastRestore;
            }
            if (!TestBound("DatabaseName"))
            {
                _pipeDatabaseName = true;
            }
            if (OutputScriptOnly.ToBool() && VerifyOnly.ToBool())
            {
                StopFunction("The switches OutputScriptOnly and VerifyOnly cannot both be specified at the same time, stopping", category: ErrorCategory.InvalidArgument);
                return;
            }
        }

        if (StatementTimeout == 0)
        {
            WriteMessage(MessageLevel.Verbose, "Changing statement timeout to infinity");
        }
        else
        {
            WriteMessage(MessageLevel.Verbose, $"Changing statement timeout to ({StatementTimeout}) minutes");
        }
        _restoreInstance.ConnectionContext.StatementTimeout = StatementTimeout * 60;
        //endregion Validation

        if (_useDestinationDefaultDirectories)
        {
            Hashtable defaultPathParms = new() { ["SqlInstance"] = _restoreInstance };
            Collection<PSObject> defaultPath = NestedCommand.Invoke(this, "Get-DbaDefaultPath", defaultPathParms);
            PSObject? paths = defaultPath.Count > 0 ? defaultPath[0] : null;
            DestinationDataDirectory = RestoreUtility.PsStringify(PsProperty.Get(paths, "Data"));
            DestinationLogDirectory = RestoreUtility.PsStringify(PsProperty.Get(paths, "Log"));
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        if (_restoreInstance!.VersionMajor == 8 && !TrustDbBackupHistory.ToBool())
        {
            foreach (object file in Path)
            {
                Hashtable scanParms = new()
                {
                    ["SqlInstance"] = _restoreInstance,
                    ["Path"] = file
                };
                Collection<PSObject> bh = NestedCommand.Invoke(this, "Get-DbaBackupInformation", scanParms);
                // PS re-enters itself with the caller's bound parameters, TrustDbBackupHistory
                // forced on and Path replaced by the scanned history.
                Hashtable bound = new();
                foreach (KeyValuePair<string, object> parameter in MyInvocation.BoundParameters)
                    bound[parameter.Key] = parameter.Value;
                bound["TrustDbBackupHistory"] = true;
                bound["Path"] = bh;
                NestedCommand.InvokeStreamed(this, "Restore-DbaDatabase", bound, Array.Empty<object>());
            }
            // Flag function interrupt to silently not execute end
            _skipEnd = true;
            return;
        }
        if (ParameterSetName.StartsWith("Restore", StringComparison.OrdinalIgnoreCase))
        {
            if (_pipeDatabaseName)
            {
                _databaseName = new object[] { "" };
            }
            WriteMessage(MessageLevel.Verbose, "ParameterSet  = Restore");
            bool trusted = TrustDbBackupHistory.ToBool();
            if (!trusted && Path.Length > 0)
            {
                object firstBase = Path[0] is PSObject psFirst ? psFirst.BaseObject : Path[0];
                trusted = firstBase.GetType().ToString() == "Dataplat.Dbatools.Database.BackupHistory";
            }
            if (trusted)
            {
                foreach (object fRaw in Path)
                {
                    object f = fRaw;
                    WriteMessage(MessageLevel.Verbose, "Trust Database Backup History Set");
                    if (!PsProperty.Has(f, "BackupPath"))
                    {
                        // PS logs $_ here (not $f); outside a pipeline it renders empty.
                        WriteMessage(MessageLevel.Verbose, "adding BackupPath - ");
                        f = SelectStarPlus(f, "BackupPath", PsProperty.Get(f, "FullName"));
                    }
                    if (!PsProperty.Has(f, "DatabaseName"))
                    {
                        f = SelectStarPlus(f, "DatabaseName", PsProperty.Get(f, "Database"));
                    }
                    if (!PsProperty.Has(f, "Database"))
                    {
                        f = SelectStarPlus(f, "Database", PsProperty.Get(f, "DatabaseName"));
                    }
                    if (!PsProperty.Has(f, "BackupSetGUID"))
                    {
                        f = SelectStarPlus(f, "BackupSetGUID", PsProperty.Get(f, "BackupSetID"));
                    }
                    object? backupPathValue = PsProperty.Get(f, "BackupPath");
                    string backupPathText = RestoreUtility.PsStringify(backupPathValue);
                    if (backupPathText.StartsWith("http", StringComparison.OrdinalIgnoreCase) || backupPathText.StartsWith("s3", StringComparison.OrdinalIgnoreCase))
                    {
                        if (StorageCredential != "")
                        {
                            WriteMessage(MessageLevel.Verbose, "At least one cloud storage backup passed in with a credential, assume correct");
                            WriteMessage(MessageLevel.Verbose, "Storage Account Identity access means striped backups cannot be restore");
                        }
                        else
                        {
                            string matchInput;
                            if (backupPathValue is IList { Count: > 1 } backupPathList)
                            {
                                matchInput = RestoreUtility.PsStringify(backupPathList[0]);
                            }
                            else
                            {
                                matchInput = backupPathText;
                            }
                            // PS -match is case-insensitive (cross-model review 2026-07-07 finding B3).
                            System.Text.RegularExpressions.Match match = System.Text.RegularExpressions.Regex.Match(matchInput, "(http|https|s3)://[^/]*/[^/]*", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
                            Hashtable credParms = new()
                            {
                                ["SqlInstance"] = _restoreInstance,
                                ["Name"] = match.Value.Trim('/')
                            };
                            Collection<PSObject> credential = NestedCommand.Invoke(this, "Get-DbaCredential", credParms);
                            if (credential.Count > 0 && LanguagePrimitives.IsTrue(credential.Count == 1 ? credential[0] : credential))
                            {
                                WriteMessage(MessageLevel.Verbose, $"We have a credential to use with {backupPathText}");
                            }
                            else
                            {
                                StopFunction("A URL to a backup has been passed in, but no credential can be found to access it");
                                return;
                            }
                        }
                    }
                    // Fix #5036 by implementing a deep copy of the FileList
                    PsProperty.Set(f, "FileList", DeepCopyFileList(PsProperty.Get(f, "FileList")));
                    object withServerName = SelectStarPlus(f, "ServerName", PsProperty.Get(f, "SqlInstance"));
                    object? startAsDateTime;
                    try
                    {
                        startAsDateTime = LanguagePrimitives.ConvertTo(PsProperty.Get(f, "Start"), typeof(DateTime), System.Globalization.CultureInfo.InvariantCulture);
                    }
                    catch
                    {
                        // -as [DateTime] yields null when the conversion fails.
                        startAsDateTime = null;
                    }
                    object finalRecord = SelectStarPlus(withServerName, "BackupStartDate", startAsDateTime);
                    _backupHistory.Add(finalRecord);
                }
            }
            else
            {
                List<object?> files = new();
                foreach (object f in Path)
                {
                    object baseObject = f is PSObject psf ? psf.BaseObject : f;
                    if (baseObject is System.IO.FileSystemInfo fsInfo)
                    {
                        files.Add(fsInfo.FullName);
                    }
                    else
                    {
                        files.Add(f);
                    }
                }
                List<string> fileTexts = new();
                foreach (object? file in files)
                    fileTexts.Add(RestoreUtility.PsStringify(file));
                WriteMessage(MessageLevel.Verbose, $"Unverified input, full scans - {string.Join(";", fileTexts)}");
                Hashtable scanParms = new()
                {
                    ["SqlInstance"] = _restoreInstance,
                    ["SqlCredential"] = SqlCredential,
                    ["Path"] = files.ToArray(),
                    ["DirectoryRecurse"] = DirectoryRecurse.ToBool(),
                    ["MaintenanceSolution"] = MaintenanceSolutionBackup.ToBool(),
                    ["IgnoreDiffBackup"] = IgnoreDiffBackup.ToBool(),
                    ["IgnoreLogBackup"] = IgnoreLogBackup.ToBool(),
                    ["StorageCredential"] = StorageCredential,
                    ["NoXpDirRecurse"] = NoXpDirRecurse.ToBool()
                };
                foreach (PSObject item in NestedCommand.Invoke(this, "Get-DbaBackupInformation", scanParms))
                    _backupHistory.Add(item);
            }
            if (ParameterSetName == "RestorePage")
            {
                Hashtable tailParms = new()
                {
                    ["SqlInstance"] = _restoreInstance,
                    ["Path"] = PageRestoreTailFolder
                };
                Collection<PSObject> tailOk = NestedCommand.Invoke(this, "Test-DbaPath", tailParms);
                if (!(tailOk.Count > 0 && LanguagePrimitives.IsTrue(tailOk.Count == 1 ? tailOk[0] : tailOk)))
                {
                    StopFunction($"Instance {_restoreInstance.Name} cannot read {PageRestoreTailFolder}, cannot proceed", target: PageRestoreTailFolder);
                    return;
                }
                _withReplace = true;
            }
        }
        else if (ParameterSetName == "Recovery")
        {
            int leakCount = _recoveryDatabaseLeak is null ? 0 : 1;
            WriteMessage(MessageLevel.Verbose, $"{leakCount} databases to recover");
            foreach (object? databaseRaw in DatabaseName ?? Array.Empty<object>())
            {
                string database = RestoreUtility.PsStringify(databaseRaw);
                //We've got an object, try the normal options Database, DatabaseName, Name
                if (PsProperty.Has(databaseRaw, "Database"))
                {
                    database = RestoreUtility.PsStringify(PsProperty.Get(databaseRaw, "Database"));
                }
                else if (PsProperty.Has(databaseRaw, "DatabaseName"))
                {
                    database = RestoreUtility.PsStringify(PsProperty.Get(databaseRaw, "DatabaseName"));
                }
                else if (PsProperty.Has(databaseRaw, "Name"))
                {
                    database = RestoreUtility.PsStringify(PsProperty.Get(databaseRaw, "Name"));
                }
                _recoveryDatabaseLeak = database;
                Microsoft.SqlServer.Management.Smo.Database? smoDatabase = _restoreInstance.Databases[database];
                WriteMessage(MessageLevel.Verbose, $"existence - {RestoreUtility.PsStringify(smoDatabase?.State)}");
                if (!PsOps.Eq(smoDatabase?.State, "Existing"))
                {
                    WriteMessage(MessageLevel.Warning, $"{database} does not exist on {_restoreInstance.Name}");
                    continue;
                }

                string status = RestoreUtility.PsStringify(smoDatabase!.Status);
                if (!PsString.In(status, "Restoring", "Normal, Standby"))
                {
                    WriteMessage(MessageLevel.Warning, $"{database} on {_restoreInstance.Name} state [{status}] is not a valid state. Valid state is Restoring or Standby");
                    continue;
                }
                bool restoreComplete = true;
                // BP-102: bracket quoting via QuoteIdentifier (byte-identical for plain names).
                string recoverSql = $"RESTORE DATABASE {new Microsoft.Data.SqlClient.SqlCommandBuilder().QuoteIdentifier(database)} WITH RECOVERY";
                WriteMessage(MessageLevel.Verbose, $"Recovery Sql Query - {recoverSql}");
                object? exitError = null;
                try
                {
                    _restoreInstance.ConnectionContext.ExecuteWithResults(recoverSql);
                }
                catch (Exception ex)
                {
                    restoreComplete = false;
                    exitError = ex.InnerException;
                    WriteMessage(MessageLevel.Warning, $"Failed to recover {database} on {_restoreInstance.Name}, \n {RestoreUtility.PsStringify(exitError)}");
                }
                finally
                {
                    PSObject result = new();
                    result.Properties.Add(new PSNoteProperty("SqlInstance", SqlInstance));
                    result.Properties.Add(new PSNoteProperty("DatabaseName", database));
                    result.Properties.Add(new PSNoteProperty("RestoreComplete", restoreComplete));
                    result.Properties.Add(new PSNoteProperty("Scripts", recoverSql));
                    WriteObject(result);
                }
            }
        }
    }

    // $f | Select-Object *, @{ Name = <name>; Expression = { <value> } } — a property-bag copy
    // with one appended note property.
    private static object SelectStarPlus(object source, string propertyName, object? value)
    {
        PSObject copy = new();
        PSObject wrapped = PSObject.AsPSObject(source);
        foreach (PSPropertyInfo property in wrapped.Properties)
        {
            object? propertyValue;
            try { propertyValue = property.Value; }
            catch { propertyValue = null; }
            copy.Properties.Add(new PSNoteProperty(property.Name, propertyValue));
        }
        copy.Properties.Add(new PSNoteProperty(propertyName, value));
        return copy;
    }

    private static object? DeepCopyFileList(object? fileList)
    {
        if (fileList is PSObject psList)
            fileList = psList.BaseObject;
        if (fileList is not IEnumerable items || fileList is string)
            return fileList;
        List<PSObject> copies = new();
        foreach (object? item in items)
        {
            if (item is null)
                continue;
            PSObject copy = new();
            foreach (PSPropertyInfo property in PSObject.AsPSObject(item).Properties)
            {
                object? propertyValue;
                try { propertyValue = property.Value; }
                catch { propertyValue = null; }
                copy.Properties.Add(new PSNoteProperty(property.Name, propertyValue));
            }
            copies.Add(copy);
        }
        return copies.ToArray();
    }
}
