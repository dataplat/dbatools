#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using Dataplat.Dbatools.Database;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Commands;

public sealed partial class GetDbaBackupInformationCommand
{
    // The Import branch accumulates across process invocations in the PS source (no reset),
    // so piping several xml paths re-emits earlier content. Preserved.
    private readonly List<object?> _importGroupResults = new();

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        List<object?> groupResults = new();
        bool importing = TestBound("Import") && Import.ToBool();
        if (importing)
        {
            foreach (object f in Path)
            {
                string file = RestoreUtility.PsStringify(f);
                if (System.IO.File.Exists(file) || System.IO.Directory.Exists(file))
                {
                    Hashtable importParms = new() { ["Path"] = file };
                    foreach (PSObject imported in NestedCommand.Invoke(this, "Import-Clixml", importParms))
                        _importGroupResults.Add(imported);
                    foreach (object? group in _importGroupResults)
                    {
                        PsProperty.Set(group!, "FirstLsn", PsLsn.ToBigInt(PsProperty.Get(group, "FirstLSN")));
                        PsProperty.Set(group!, "CheckpointLSN", PsLsn.ToBigInt(PsProperty.Get(group, "CheckpointLSN")));
                        PsProperty.Set(group!, "DatabaseBackupLsn", PsLsn.ToBigInt(PsProperty.Get(group, "DatabaseBackupLsn")));
                        PsProperty.Set(group!, "LastLsn", PsLsn.ToBigInt(PsProperty.Get(group, "LastLsn")));
                    }
                }
                else
                {
                    WriteMessage(MessageLevel.Warning, $"{file} does not exist or is unreadable");
                }
            }
            groupResults = _importGroupResults;
        }
        else
        {
            List<object?> files = new();

            // Detect cloud storage URLs (Azure http:// or S3 s3://)
            string firstPath = Path.Length > 0 ? RestoreUtility.PsStringify(Path[0]) : "";
            // PS -match is case-insensitive (cross-model review 2026-07-07 finding A3).
            if (System.Text.RegularExpressions.Regex.IsMatch(firstPath, "^https?://", System.Text.RegularExpressions.RegexOptions.IgnoreCase) || System.Text.RegularExpressions.Regex.IsMatch(firstPath, "^s3://", System.Text.RegularExpressions.RegexOptions.IgnoreCase))
            {
                _noXpDirTreeEffective = true;
            }
            if (!_noXpDirTreeEffective)
            {
                foreach (object fRaw in Path)
                {
                    object f = fRaw;
                    string fText = RestoreUtility.PsStringify(f);
                    if (System.IO.Path.GetExtension(fText).Length > 1)
                    {
                        if (!PsProperty.Has(f, "FullName"))
                        {
                            // PS: $f = $f | Select-Object *, @{ Name = "FullName"; Expression = { $f } }
                            PSObject wrapped = new();
                            PSObject source = PSObject.AsPSObject(f);
                            foreach (PSPropertyInfo property in source.Properties)
                            {
                                object? value;
                                try { value = property.Value; }
                                catch { value = null; }
                                wrapped.Properties.Add(new PSNoteProperty(property.Name, value));
                            }
                            wrapped.Properties.Add(new PSNoteProperty("FullName", f));
                            f = wrapped;
                        }
                        WriteMessage(MessageLevel.Verbose, $"Testing a single file {fText} ");
                        Hashtable testParms = new()
                        {
                            ["Path"] = RestoreUtility.PsStringify(PsProperty.Get(f, "FullName")),
                            ["SqlInstance"] = _server
                        };
                        Collection<PSObject> exists = NestedCommand.Invoke(this, "Test-DbaPath", testParms);
                        if (exists.Count > 0 && LanguagePrimitives.IsTrue(exists.Count == 1 ? exists[0] : exists))
                        {
                            files.Add(f);
                        }
                        else
                        {
                            WriteMessage(MessageLevel.Verbose, $"{_server!.Name} cannot 'see' file {RestoreUtility.PsStringify(PsProperty.Get(f, "FullName"))}");
                        }
                    }
                    else if (MaintenanceSolution.ToBool())
                    {
                        if (IgnoreLogBackup.ToBool() && (System.IO.Path.GetDirectoryName(fText) ?? "").EndsWith("LOG", StringComparison.OrdinalIgnoreCase))
                        {
                            WriteMessage(MessageLevel.Verbose, "Skipping Log Backups as requested");
                        }
                        else
                        {
                            WriteMessage(MessageLevel.Verbose, "OLA - Getting folder contents");
                            try
                            {
                                files.AddRange(XpDirTreeScanner.Scan(this, _server!, fText, noRecurse: NoXpDirRecurse.ToBool(), enableException: false));
                            }
                            catch (Exception ex)
                            {
                                ErrorRecord record = ex is InnerCommandException ice ? ice.FirstRecord : new ErrorRecord(ex, "dbatools_Get-DbaBackupInformation", ErrorCategory.NotSpecified, _server!.Name);
                                StopFunction($"Failure on {_server!.Name}", target: _server.Name, errorRecord: record, continueLoop: true);
                                continue;
                            }
                        }
                    }
                    else
                    {
                        WriteMessage(MessageLevel.Verbose, $"Testing a folder {fText}");
                        List<PSObject> check;
                        try
                        {
                            check = XpDirTreeScanner.Scan(this, _server!, fText, noRecurse: NoXpDirRecurse.ToBool(), enableException: true);
                            files.AddRange(check);
                        }
                        catch (Exception ex)
                        {
                            ErrorRecord record = ex is InnerCommandException ice ? ice.FirstRecord : new ErrorRecord(ex, "dbatools_Get-DbaBackupInformation", ErrorCategory.NotSpecified, _server!.Name);
                            StopFunction($"Failure on {_server!.Name}", target: _server.Name, errorRecord: record, continueLoop: true);
                            continue;
                        }
                        if (check.Count == 0)
                        {
                            WriteMessage(MessageLevel.Verbose, $"Nothing returned from {fText}");
                        }
                    }
                }
            }
            else
            {
                foreach (object f in Path)
                {
                    string fText = RestoreUtility.PsStringify(f);
                    WriteMessage(MessageLevel.VeryVerbose, $"Not using sql for {fText}");
                    object baseObject = f is PSObject psf ? psf.BaseObject : f;
                    if (baseObject is System.IO.FileSystemInfo fsInfo)
                    {
                        bool isContainer = fsInfo is System.IO.DirectoryInfo;
                        if (isContainer && !MaintenanceSolution.ToBool())
                        {
                            WriteMessage(MessageLevel.VeryVerbose, $"folder {fsInfo.FullName}");
                            Hashtable gciParms = new()
                            {
                                ["Path"] = fsInfo.FullName,
                                ["File"] = true,
                                ["Recurse"] = DirectoryRecurse.ToBool()
                            };
                            foreach (PSObject item in NestedCommand.Invoke(this, "Get-ChildItem", gciParms))
                                files.Add(item);
                        }
                        else if (isContainer && MaintenanceSolution.ToBool())
                        {
                            // PS quirk preserved: with IgnoreLogBackup this skips every folder
                            // that does NOT end in LOG (the -notlike is inverted in the source).
                            if (IgnoreLogBackup.ToBool() && !fText.EndsWith("LOG", StringComparison.OrdinalIgnoreCase))
                            {
                                WriteMessage(MessageLevel.Verbose, "Skipping Log backups for Maintenance backups");
                            }
                            else
                            {
                                Hashtable gciParms = new()
                                {
                                    ["Path"] = fsInfo.FullName,
                                    ["File"] = true,
                                    ["Recurse"] = DirectoryRecurse.ToBool()
                                };
                                foreach (PSObject item in NestedCommand.Invoke(this, "Get-ChildItem", gciParms))
                                    files.Add(item);
                            }
                        }
                        else if (MaintenanceSolution.ToBool())
                        {
                            Hashtable gciParms = new()
                            {
                                ["Path"] = fsInfo.FullName,
                                ["Recurse"] = DirectoryRecurse.ToBool()
                            };
                            foreach (PSObject item in NestedCommand.Invoke(this, "Get-ChildItem", gciParms))
                                files.Add(item);
                        }
                        else
                        {
                            WriteMessage(MessageLevel.VeryVerbose, "File");
                            files.Add(fsInfo.FullName);
                        }
                    }
                    else
                    {
                        if (MaintenanceSolution.ToBool())
                        {
                            // Use forward slashes for URLs (Azure https:// or S3 s3://), backslashes for file system paths
                            string separator = System.Text.RegularExpressions.Regex.IsMatch(fText, "^https?://", System.Text.RegularExpressions.RegexOptions.IgnoreCase) || System.Text.RegularExpressions.Regex.IsMatch(fText, "^s3://", System.Text.RegularExpressions.RegexOptions.IgnoreCase) ? "/" : "\\";
                            files.AddRange(XpDirTreeScanner.Scan(this, _server!, $"{fText}{separator}FULL", noRecurse: true, enableException: false));
                            files.AddRange(XpDirTreeScanner.Scan(this, _server!, $"{fText}{separator}DIFF", noRecurse: true, enableException: false));
                            files.AddRange(XpDirTreeScanner.Scan(this, _server!, $"{fText}{separator}LOG", noRecurse: true, enableException: false));
                        }
                        else
                        {
                            WriteMessage(MessageLevel.VeryVerbose, "File");
                            files.Add(f);
                        }
                    }
                }
            }

            if (MaintenanceSolution.ToBool() && IgnoreLogBackup.ToBool())
            {
                WriteMessage(MessageLevel.Verbose, "Skipping Log Backups as requested");
                files = FilterOutFolder(files, "LOG");
            }

            if (MaintenanceSolution.ToBool() && IgnoreDiffBackup.ToBool())
            {
                WriteMessage(MessageLevel.Verbose, "Skipping Differential Backups as requested");
                files = FilterOutFolder(files, "DIFF");
            }

            Collection<PSObject>? fileDetails = null;
            if (files.Count > 0)
            {
                WriteMessage(MessageLevel.Verbose, $"Reading backup headers of {files.Count} files");
                try
                {
                    Hashtable headerParms = new()
                    {
                        ["SqlInstance"] = _server,
                        ["Path"] = files.ToArray(),
                        ["StorageCredential"] = StorageCredential,
                        ["EnableException"] = true
                    };
                    fileDetails = NestedCommand.Invoke(this, "Read-DbaBackupHeader", headerParms);
                }
                catch (Exception ex)
                {
                    ErrorRecord record = new(ex, "dbatools_Get-DbaBackupInformation", ErrorCategory.NotSpecified, _server!.Name);
                    StopFunction($"Failure on {_server!.Name}", target: _server.Name, errorRecord: record, continueLoop: true);
                    // PS: Stop-Function -Continue at process level; this invocation ends here.
                    return;
                }
            }

            // Group-Object -Property BackupSetGUID (case-insensitive keys, first-seen order)
            Dictionary<string, List<PSObject>> groups = new(StringComparer.OrdinalIgnoreCase);
            List<string> groupOrder = new();
            if (fileDetails is not null)
            {
                foreach (PSObject detail in fileDetails)
                {
                    string key = RestoreUtility.PsStringify(PsProperty.Get(detail, "BackupSetGUID"));
                    if (!groups.TryGetValue(key, out List<PSObject>? bucket))
                    {
                        bucket = new List<PSObject>();
                        groups.Add(key, bucket);
                        groupOrder.Add(key);
                    }
                    bucket.Add(detail);
                }
            }

            foreach (string key in groupOrder)
            {
                List<PSObject> group = groups[key];
                PSObject first = group[0];
                object? dbLsn = PsProperty.Get(first, "DatabaseBackupLSN");
                if (!PsOps.IsTrue(dbLsn))
                {
                    dbLsn = 0;
                }
                string typeDescription = RestoreUtility.PsStringify(PsProperty.Get(first, "BackupTypeDescription"));
                string? description = typeDescription switch
                {
                    _ when PsString.Eq(typeDescription, "Database") => "Full",
                    _ when PsString.Eq(typeDescription, "Database Differential") => "Differential",
                    _ when PsString.Eq(typeDescription, "Transaction Log") => "Log",
                    _ when PsString.Eq(typeDescription, "File or Filegroup") => "File",
                    _ when PsString.Eq(typeDescription, "File Differential") => "Differential File",
                    _ when PsString.Eq(typeDescription, "Partial Database") => "Partial Full",
                    _ when PsString.Eq(typeDescription, "Partial Differential") => "Partial Differential",
                    _ => typeDescription
                };
                if (string.IsNullOrEmpty(description))
                {
                    PSObject? header = null;
                    try
                    {
                        Hashtable headerParms = new()
                        {
                            ["SqlInstance"] = _server,
                            ["Path"] = Path,
                            ["EnableException"] = true
                        };
                        Collection<PSObject> reread = NestedCommand.Invoke(this, "Read-DbaBackupHeader", headerParms);
                        header = reread.Count > 0 ? reread[0] : null;
                    }
                    catch (Exception ex)
                    {
                        ErrorRecord record = new(ex, "dbatools_Get-DbaBackupInformation", ErrorCategory.NotSpecified, _server!.Name);
                        StopFunction($"Failure on {_server!.Name}", target: _server.Name, errorRecord: record, continueLoop: true);
                        continue;
                    }
                    object? backupType = PsProperty.Get(header, "BackupType");
                    if (PsOps.Eq(backupType, 1))
                        description = "Full";
                    else if (PsOps.Eq(backupType, 2))
                        description = "Differential";
                    else if (PsOps.Eq(backupType, 3))
                        description = "Log";
                }

                BackupHistory historyObject = new();
                historyObject.ComputerName = RestoreUtility.PsStringify(PsProperty.Get(first, "MachineName"));
                string instanceName = RestoreUtility.PsStringify(PsProperty.Get(first, "ServiceName"));
                string serverNameValue = RestoreUtility.PsStringify(PsProperty.Get(first, "ServerName"));
                if (instanceName == "" && serverNameValue.Contains("\\"))
                {
                    instanceName = serverNameValue.Split('\\')[1];
                }
                else if (instanceName == "")
                {
                    instanceName = "MSSQLSERVER";
                }
                historyObject.InstanceName = instanceName;
                historyObject.SqlInstance = serverNameValue;
                historyObject.Database = RestoreUtility.PsStringify(PsProperty.Get(first, "DatabaseName"));
                historyObject.UserName = RestoreUtility.PsStringify(PsProperty.Get(first, "UserName"));
                DateTime start = (DateTime)LanguagePrimitives.ConvertTo(PsProperty.Get(first, "BackupStartDate"), typeof(DateTime), System.Globalization.CultureInfo.InvariantCulture);
                DateTime end = (DateTime)LanguagePrimitives.ConvertTo(PsProperty.Get(first, "BackupFinishDate"), typeof(DateTime), System.Globalization.CultureInfo.InvariantCulture);
                historyObject.Start = start;
                historyObject.End = end;
                historyObject.Duration = new DbaTimeSpan(end - start);
                List<string> backupPaths = new();
                foreach (PSObject detail in group)
                    backupPaths.Add(RestoreUtility.PsStringify(PsProperty.Get(detail, "BackupPath")));
                historyObject.Path = backupPaths.ToArray();
                historyObject.FileList = BuildFileList(group);
                // PS: $group.Group[0].BackupSize.Byte — a null cell (multi-set header quirk in
                // Read-DbaBackupHeader) null-propagates to a null Size, exactly like PS.
                historyObject.TotalSize = AsSize(PsProperty.Get(PsProperty.Get(first, "BackupSize"), "Byte"));
                historyObject.CompressedBackupSize = AsSize(PsProperty.Get(PsProperty.Get(first, "CompressedBackupSize"), "Byte"));
                historyObject.Type = description ?? "";
                historyObject.BackupSetId = RestoreUtility.PsStringify(PsProperty.Get(first, "BackupSetGUID"));
                historyObject.DeviceType = "Disk";
                historyObject.FullName = backupPaths.ToArray();
                historyObject.Position = (int)LanguagePrimitives.ConvertTo(PsProperty.Get(first, "Position") ?? 0, typeof(int), System.Globalization.CultureInfo.InvariantCulture);
                historyObject.FirstLsn = PsLsn.ToBigInt(PsProperty.Get(first, "FirstLSN"));
                historyObject.DatabaseBackupLsn = PsLsn.ToBigInt(dbLsn);
                historyObject.CheckpointLsn = PsLsn.ToBigInt(PsProperty.Get(first, "CheckpointLSN"));
                historyObject.LastLsn = PsLsn.ToBigInt(PsProperty.Get(first, "LastLsn"));
                historyObject.SoftwareVersionMajor = (int)LanguagePrimitives.ConvertTo(PsProperty.Get(first, "SoftwareVersionMajor") ?? 0, typeof(int), System.Globalization.CultureInfo.InvariantCulture);
                // Member enumeration over the group: one file keeps the scalar, striped sets
                // space-join on assignment to the string field, exactly like PS.
                List<object?> recoveryModels = new();
                foreach (PSObject detail in group)
                    recoveryModels.Add(PsProperty.Get(detail, "RecoveryModel"));
                historyObject.RecoveryModel = recoveryModels.Count == 1
                    ? RestoreUtility.PsStringify(recoveryModels[0])
                    : RestoreUtility.PsStringify(recoveryModels.ToArray());
                historyObject.IsCopyOnly = LanguagePrimitives.IsTrue(PsProperty.Get(first, "IsCopyOnly"));
                object? lastFork = PsProperty.Get(first, "LastRecoveryForkGUID");
                if (lastFork is not null)
                {
                    historyObject.LastRecoveryForkGUID = (Guid)LanguagePrimitives.ConvertTo(lastFork, typeof(Guid), System.Globalization.CultureInfo.InvariantCulture);
                }
                groupResults.Add(historyObject);
            }
        }

        if (TestBound("SourceInstance"))
        {
            List<object?> filtered = new();
            foreach (object? group in groupResults)
            {
                if (PsOps.In(PsProperty.Get(group, "InstanceName"), SourceInstance))
                    filtered.Add(group);
            }
            groupResults = filtered;
        }

        if (TestBound("DatabaseName"))
        {
            List<object?> filtered = new();
            foreach (object? group in groupResults)
            {
                if (PsOps.In(PsProperty.Get(group, "Database"), DatabaseName))
                    filtered.Add(group);
            }
            groupResults = filtered;
        }
        if (Anonymise.ToBool())
        {
            foreach (object? group in groupResults)
            {
                PsProperty.Set(group!, "ComputerName", GetHashString(RestoreUtility.PsStringify(PsProperty.Get(group, "ComputerName"))));
                PsProperty.Set(group!, "InstanceName", GetHashString(RestoreUtility.PsStringify(PsProperty.Get(group, "InstanceName"))));
                PsProperty.Set(group!, "SqlInstance", GetHashString(RestoreUtility.PsStringify(PsProperty.Get(group, "SqlInstance"))));
                PsProperty.Set(group!, "Database", GetHashString(RestoreUtility.PsStringify(PsProperty.Get(group, "Database"))));
                PsProperty.Set(group!, "UserName", GetHashString(RestoreUtility.PsStringify(PsProperty.Get(group, "UserName"))));
                PsProperty.Set(group!, "Path", GetHashString(RestoreUtility.PsStringify(PsProperty.Get(group, "Path"))));
                PsProperty.Set(group!, "FullName", GetHashString(RestoreUtility.PsStringify(PsProperty.Get(group, "FullName"))));
                // The anonymised FileList projection drops Size, exactly like the PS Select-Object.
                List<PSObject> anonymised = new();
                if (PsProperty.Get(group, "FileList") is IEnumerable fileList and not string)
                {
                    foreach (object? file in fileList)
                    {
                        PSObject entry = new();
                        // Select-Object inserts "Selected.<input type>" (cross-model review finding A4).
                        entry.TypeNames.Insert(0, "Selected.System.Management.Automation.PSCustomObject");
                        entry.Properties.Add(new PSNoteProperty("FileType", PsProperty.Get(file, "FileType")));
                        entry.Properties.Add(new PSNoteProperty("LogicalName", GetHashString(RestoreUtility.PsStringify(PsProperty.Get(file, "LogicalName")))));
                        entry.Properties.Add(new PSNoteProperty("PhysicalName", GetHashString(RestoreUtility.PsStringify(PsProperty.Get(file, "PhysicalName")))));
                        anonymised.Add(entry);
                    }
                }
                PsProperty.Set(group!, "FileList", anonymised.ToArray());
            }
        }
        if (TestBound("ExportPath") && ExportPath is not null)
        {
            Hashtable exportParms = new()
            {
                ["Path"] = ExportPath,
                ["Depth"] = 5,
                ["NoClobber"] = NoClobber.ToBool()
            };
            NestedCommand.Invoke(this, "Export-Clixml", exportParms, groupResults.ToArray());
            if (!PassThru.ToBool())
            {
                return;
            }
        }
        foreach (object? group in SortByEndDescending(groupResults))
            WriteObject(group);
    }

    private static List<object?> FilterOutFolder(List<object?> files, string folder)
    {
        List<object?> kept = new();
        foreach (object? file in files)
        {
            string fullName = RestoreUtility.PsStringify(PsProperty.Get(file, "FullName"));
            if (fullName.IndexOf($"\\{folder}\\", StringComparison.OrdinalIgnoreCase) < 0
                && fullName.IndexOf($"/{folder}/", StringComparison.OrdinalIgnoreCase) < 0)
            {
                kept.Add(file);
            }
        }
        return kept;
    }

    // group.Group.FileList | Select-Object FileType/LogicalName/PhysicalName/[dbasize]Size -Unique
    private static PSObject[] BuildFileList(List<PSObject> group)
    {
        List<PSObject> projected = new();
        HashSet<string> seen = new(StringComparer.Ordinal);
        foreach (PSObject detail in group)
        {
            if (PsProperty.Get(detail, "FileList") is not IEnumerable files || files is string)
                continue;
            foreach (object? file in files)
            {
                object? fileType = PsProperty.Get(file, "Type");
                object? logicalName = PsProperty.Get(file, "LogicalName");
                object? physicalName = PsProperty.Get(file, "PhysicalName");
                object? sizeRaw = PsProperty.Get(file, "Size");
                Size? size = sizeRaw is null ? null : sizeRaw as Size ?? new Size((long)LanguagePrimitives.ConvertTo(sizeRaw, typeof(long), System.Globalization.CultureInfo.InvariantCulture));
                string dedupeKey = $"{RestoreUtility.PsStringify(fileType)}{RestoreUtility.PsStringify(logicalName)}{RestoreUtility.PsStringify(physicalName)}{RestoreUtility.PsStringify(size)}";
                if (!seen.Add(dedupeKey))
                    continue;
                PSObject entry = new();
                // Select-Object inserts "Selected.<input type>" (cross-model review finding A4).
                entry.TypeNames.Insert(0, "Selected.System.Management.Automation.PSCustomObject");
                entry.Properties.Add(new PSNoteProperty("FileType", fileType));
                entry.Properties.Add(new PSNoteProperty("LogicalName", logicalName));
                entry.Properties.Add(new PSNoteProperty("PhysicalName", physicalName));
                entry.Properties.Add(new PSNoteProperty("Size", size));
                projected.Add(entry);
            }
        }
        return projected.ToArray();
    }

    private static Size? AsSize(object? bytes)
    {
        if (bytes is null || bytes is DBNull)
            return null;
        if (bytes is Size size)
            return size;
        return new Size((long)LanguagePrimitives.ConvertTo(bytes, typeof(long), System.Globalization.CultureInfo.InvariantCulture));
    }

    private static List<object?> SortByEndDescending(List<object?> groupResults)
    {
        List<object?> sorted = new(groupResults);
        // Stable descending sort by End (Sort-Object parity).
        List<KeyValuePair<int, object?>> keyed = new();
        for (int n = 0; n < sorted.Count; n++)
            keyed.Add(new KeyValuePair<int, object?>(n, sorted[n]));
        keyed.Sort((a, b) =>
        {
            int compare = PsOps.Compare(PsProperty.Get(b.Value, "End"), PsProperty.Get(a.Value, "End"));
            return compare != 0 ? compare : a.Key.CompareTo(b.Key);
        });
        List<object?> result = new();
        foreach (KeyValuePair<int, object?> pair in keyed)
            result.Add(pair.Value);
        return result;
    }
}
