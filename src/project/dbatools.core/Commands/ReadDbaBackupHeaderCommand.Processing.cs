#nullable enable

using System;
using System.Collections;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Data;
using System.Management.Automation;
using System.Threading;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

public sealed partial class ReadDbaBackupHeaderCommand
{
    private sealed class HeaderWorkItem
    {
        public string File = string.Empty;
        public string DeviceTypeText = "FILE";
        public DataTable? Result;
        public readonly List<ErrorRecord> Errors = new();
        // Volatile: set by the worker thread after Result/Errors are written; the emission
        // loop below polls it from the pipeline thread.
        public volatile bool Completed;
        public bool Emitted;
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // Extract fullnames from the file system objects
        List<string> pathStrings = new();
        foreach (object pathItem in Path)
        {
            object? fullName = PsProperty.Get(pathItem, "FullName");
            pathStrings.Add(fullName is not null ? RestoreUtility.PsStringify(fullName) : RestoreUtility.PsStringify(pathItem));
        }
        // Group by filename (Group-Object: case-insensitive keys, first-seen casing kept)
        List<string> pathGroup = new();
        HashSet<string> seen = new(StringComparer.OrdinalIgnoreCase);
        foreach (string p in pathStrings)
        {
            if (seen.Add(p))
                pathGroup.Add(p);
        }

        int pathCount = pathGroup.Count;
        WriteMessage(MessageLevel.Verbose, $"{pathCount} unique files to scan.");
        WriteMessage(MessageLevel.Verbose, "Checking accessibility for all the files.");

        // Test-DbaPath returns a bare bool for a single scalar path and objects for arrays;
        // the PS source passed the group through unchanged, so the scalar shape is preserved.
        object pathArg = pathCount == 1 ? pathGroup[0] : (object)pathGroup.ToArray();
        Hashtable testPathParms = new()
        {
            ["SqlInstance"] = _server,
            ["Path"] = pathArg
        };
        var testPath = NestedCommand.Invoke(this, "Test-DbaPath", testPathParms);

        List<HeaderWorkItem> workItems = new();
        foreach (string file in pathGroup)
        {
            string deviceType;
            if (file.StartsWith("http", StringComparison.OrdinalIgnoreCase) || file.StartsWith("s3", StringComparison.OrdinalIgnoreCase))
                deviceType = "URL";
            else
                deviceType = "FILE";

            bool fileExists;
            if (pathCount == 1)
            {
                fileExists = LanguagePrimitives.IsTrue(testPath.Count == 1 ? testPath[0] : testPath);
            }
            else
            {
                bool matchExists = false;
                foreach (PSObject entry in testPath)
                {
                    if (PsString.Eq(RestoreUtility.PsStringify(PsProperty.Get(entry, "FilePath")), file))
                    {
                        matchExists = LanguagePrimitives.IsTrue(PsProperty.Get(entry, "FileExists"));
                        break;
                    }
                }
                fileExists = matchExists;
            }

            if (fileExists || deviceType == "URL")
            {
                WriteMessage(MessageLevel.Verbose, $"Scanning file {file}.");
                workItems.Add(new HeaderWorkItem { File = file, DeviceTypeText = deviceType });
            }
            else
            {
                WriteMessage(MessageLevel.Warning, $"File {file} does not exist or access denied. The SQL Server service account may not have access to the source directory.");
            }
        }

        if (workItems.Count == 0)
            return;

        // PS used a runspace pool (min 1, max 10): there is internal SQL Server queue for the
        // restore operations. 10 threads seem to perform best. Same cap here.
        ConcurrentQueue<HeaderWorkItem> queue = new(workItems);
        int workerCount = Math.Min(10, workItems.Count);
        for (int n = 0; n < workerCount; n++)
        {
            Thread worker = new(() =>
            {
                while (queue.TryDequeue(out HeaderWorkItem? item))
                {
                    try
                    {
                        item.Result = ReadHeaderTable(item);
                    }
                    catch (Exception ex)
                    {
                        item.Errors.Add(new ErrorRecord(ex, "dbatools_Read-DbaBackupHeader", ErrorCategory.NotSpecified, item.File));
                    }
                    item.Completed = true;
                }
            })
            {
                IsBackground = true
            };
            worker.Start();
        }

        // PS emission order: poll $threads in LAUNCH order every 500ms and process whatever
        // completed by then — completed-in-launch-order per poll window, NOT completion order
        // (cross-model review 2026-07-07 finding A1).
        int total = workItems.Count;
        int retrieved = 0;
        while (retrieved < total)
        {
            ProgressBridge.Write(this, 1, "Updating",
                status: "Progress",
                currentOperation: $"Scanning Restore headers: {retrieved}/{total}",
                percentComplete: (int)(retrieved / (double)total * 100));

            foreach (HeaderWorkItem completed in workItems)
            {
                if (completed.Emitted || !completed.Completed)
                    continue;
                completed.Emitted = true;
                retrieved++;

                // Check if thread had any errors
                if (completed.Errors.Count > 0)
                {
                    if (completed.DeviceTypeText == "FILE")
                    {
                        StopFunction($"Problem found with {completed.File}.", target: completed.File, errorRecord: completed.Errors[0], continueLoop: true);
                        continue;
                    }
                    else
                    {
                        StopFunction($"Unable to read {completed.File}, check credential {StorageCredential} and network connectivity.", target: completed.File, errorRecord: completed.Errors[0], continueLoop: true);
                        continue;
                    }
                }
                // Process the result of this thread

                DataTable? dataTable = completed.Result;
                if (dataTable is null)
                    continue;

                object? dbVersionRaw = dataTable.Rows.Count > 0 ? dataTable.Rows[0]["DatabaseVersion"] : null;
                string sqlVersion = RestoreUtility.ConvertDbVersionToSqlVersion(RestoreUtility.PsStringify(dbVersionRaw is DBNull ? null : dbVersionRaw));
                foreach (DataRow row in dataTable.Rows)
                {
                    row["SqlVersion"] = sqlVersion;
                    if (PsString.Eq(RestoreUtility.PsStringify(row["BackupName"] is DBNull ? null : row["BackupName"]), "*** INCOMPLETE ***"))
                    {
                        // PS: Stop-Function ... -Continue inside the row loop — it skips to the next
                        // row; the table below still emits. Preserved.
                        StopFunction($"{completed.File} appears to be from a new version of SQL Server than {RestoreUtility.PsStringify(SqlInstance)}, skipping", target: completed.File, continueLoop: true);
                        continue;
                    }
                }
                if (Simple.ToBool())
                {
                    foreach (DataRow row in dataTable.Rows)
                        WriteObject(SelectProperties(row, "DatabaseName", "BackupFinishDate", "RecoveryModel", "BackupSize", "CompressedBackupSize", "DatabaseCreationDate", "UserName", "ServerName", "SqlVersion", "BackupPath"));
                }
                else if (FileList.ToBool())
                {
                    // PS: $dataTable.filelist — member enumeration flattens the per-row arrays.
                    foreach (DataRow row in dataTable.Rows)
                    {
                        if (row["FileList"] is IEnumerable files and not string)
                        {
                            foreach (object file in files)
                                WriteObject(file);
                        }
                    }
                }
                else
                {
                    foreach (DataRow row in dataTable.Rows)
                        WriteObject(row);
                }
            }

            if (retrieved < total)
            {
                if (CancellationToken.IsCancellationRequested)
                    return;
                Thread.Sleep(500);
            }
        }
        // The PS source closes its runspace pool and restores the default runspace here; the
        // worker threads above exit on their own once the queue drains.
    }

    private DataTable ReadHeaderTable(HeaderWorkItem item)
    {
        // Copy existing connection to create an independent TSQL session
        Server server = new(_server!.ConnectionContext.Copy());
        Restore restore = new();

        if (item.DeviceTypeText == "URL")
        {
            restore.CredentialName = StorageCredential;
        }

        DeviceType deviceType = item.DeviceTypeText == "URL" ? DeviceType.Url : DeviceType.File;
        BackupDeviceItem device = new(item.File, deviceType);
        restore.Devices.Add(device);
        DataTable dataTable = restore.ReadBackupHeader(server);
        dataTable.Columns.Add("FileList", typeof(object));
        dataTable.Columns.Add("SqlVersion");
        dataTable.Columns.Add("BackupPath");

        foreach (DataRow row in dataTable.Rows)
        {
            row["BackupPath"] = item.File;

            // The per-row column rebuild below is carried over verbatim from the PS source,
            // including its multi-backupset side effect (later iterations reset values written
            // by earlier ones). Do not "fix" without an owner-approved behavior change.
            object backupsize = row["BackupSize"];
            dataTable.Columns.Remove("BackupSize");
            dataTable.Columns.Add("BackupSize", typeof(Size));
            if (backupsize is not DBNull)
                row["BackupSize"] = ToSize(backupsize);

            object? cbackupsize = dataTable.Columns.Contains("CompressedBackupSize") ? row["CompressedBackupSize"] : null;
            if (dataTable.Columns.Contains("CompressedBackupSize"))
            {
                dataTable.Columns.Remove("CompressedBackupSize");
            }
            dataTable.Columns.Add("CompressedBackupSize", typeof(Size));
            if (cbackupsize is not null && cbackupsize is not DBNull)
                row["CompressedBackupSize"] = ToSize(cbackupsize);

            restore.FileNumber = Convert.ToInt32(row["Position"], System.Globalization.CultureInfo.InvariantCulture);
            // Select-Object does a quick and dirty conversion from datatable to PS object
            row["FileList"] = SelectStar(restore.ReadFileList(server));
        }
        return dataTable;
    }

    private static object[] SelectStar(DataTable table)
    {
        List<object> results = new();
        foreach (DataRow row in table.Rows)
        {
            PSObject source = PSObject.AsPSObject(row);
            PSObject copy = new();
            // Select-Object inserts "Selected.<input type>" ahead of the PSCustomObject names
            // (cross-model review 2026-07-07 finding A2).
            copy.TypeNames.Insert(0, "Selected.System.Data.DataRow");
            foreach (PSPropertyInfo property in source.Properties)
            {
                object? value;
                try { value = property.Value; }
                catch { value = null; }
                copy.Properties.Add(new PSNoteProperty(property.Name, value));
            }
            results.Add(copy);
        }
        return results.ToArray();
    }

    private static PSObject SelectProperties(DataRow row, params string[] names)
    {
        PSObject projected = new();
        // Select-Object inserts "Selected.<input type>" (finding A2).
        projected.TypeNames.Insert(0, "Selected.System.Data.DataRow");
        foreach (string name in names)
        {
            object? value = row.Table.Columns.Contains(name) ? row[name] : null;
            if (value is DBNull)
                value = null;
            projected.Properties.Add(new PSNoteProperty(name, value));
        }
        return projected;
    }

    private static Size ToSize(object value)
    {
        return value switch
        {
            decimal d => d,
            long l => l,
            int i => i,
            double db => db,
            _ => new Size(Convert.ToInt64(value, System.Globalization.CultureInfo.InvariantCulture))
        };
    }
}
