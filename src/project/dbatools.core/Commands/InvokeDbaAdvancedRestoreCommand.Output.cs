#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

public sealed partial class InvokeDbaAdvancedRestoreCommand
{
    // The finally-block result object of the PS source: property names, order, and values
    // reproduced exactly (BP-602), display set per the Select-DefaultView call.
    private void EmitRestoreResult(object? backup, List<object?> backups, string database, bool withReplace, bool restoreComplete, Restore restore, string? script, object? exitError, DateTime fileRestoreStartTime, DateTime databaseRestoreStartTime)
    {
        string pathSep = RestoreUtility.GetPathSep(_server);
        List<string> physicalNames = FlattenMemberStrings(PsProperty.Get(backup, "FileList"), "PhysicalName");

        // (Split-Path ... -Parent | Sort-Object -Unique).Replace('\', $pathSep) -Join ','
        List<string> parents = new();
        foreach (string physicalName in physicalNames)
        {
            parents.Add(System.IO.Path.GetDirectoryName(physicalName) ?? "");
        }
        string restoreDirectory = string.Join(",", SortUnique(parents).ConvertAll(p => p.Replace("\\", pathSep)));

        List<string> fullNames = FlattenToStrings(PsProperty.Get(backup, "FullName"));
        int fullNameCount = fullNames.Count;

        Size? compressedBackupSize = null;
        object? compressedBackupSizeMb = null;
        if (PsProperty.Has(backup, "CompressedBackupSize"))
        {
            long sum = MeasureByteSum(PsProperty.Get(backup, "CompressedBackupSize"));
            compressedBackupSize = new Size((long)(sum / (double)Math.Max(fullNameCount, 1)));
            compressedBackupSizeMb = Math.Round(sum / (double)Math.Max(fullNameCount, 1) / 1048576d, 2);
        }

        Size? backupSize = null;
        object? backupSizeMb = null;
        if (PsProperty.Has(backup, "TotalSize"))
        {
            long sum = MeasureByteSum(PsProperty.Get(backup, "TotalSize"));
            backupSize = new Size((long)(sum / (double)Math.Max(fullNameCount, 1)));
            backupSizeMb = Math.Round(sum / (double)Math.Max(fullNameCount, 1) / 1048576d, 2);
        }

        // RestoredFile: leaf names, sorted unique, comma-joined.
        List<string> leaves = new();
        foreach (string physicalName in physicalNames)
        {
            leaves.Add(System.IO.Path.GetFileName(physicalName));
        }
        string restoredFile = string.Join(",", SortUnique(leaves));

        // BackupFileRaw: every FullName across the whole backup set for this database.
        List<string> backupFileRaw = new();
        foreach (object? entry in backups)
        {
            backupFileRaw.AddRange(FlattenToStrings(PsProperty.Get(entry, "FullName")));
        }

        object restoreTargetTime = RestoreTime < DateTime.Now ? RestoreTime : (object)"Latest";

        PSObject result = new();
        result.Properties.Add(new PSNoteProperty("ComputerName", SmoServerExtensions.GetComputerName(_server)));
        result.Properties.Add(new PSNoteProperty("InstanceName", RestoreUtility.PsStringify(SmoServerExtensions.GetPSProperty(_server!, "ServiceName"))));
        result.Properties.Add(new PSNoteProperty("SqlInstance", SmoServerExtensions.GetDomainInstanceName(_server)));
        result.Properties.Add(new PSNoteProperty("Database", PsProperty.Get(backup, "Database")));
        result.Properties.Add(new PSNoteProperty("DatabaseName", PsProperty.Get(backup, "Database")));
        result.Properties.Add(new PSNoteProperty("DatabaseOwner", _server!.ConnectionContext.TrueLogin));
        result.Properties.Add(new PSNoteProperty("Owner", _server.ConnectionContext.TrueLogin));
        result.Properties.Add(new PSNoteProperty("NoRecovery", restore.NoRecovery));
        result.Properties.Add(new PSNoteProperty("WithReplace", withReplace));
        result.Properties.Add(new PSNoteProperty("KeepReplication", KeepReplication.ToBool()));
        result.Properties.Add(new PSNoteProperty("RestoreComplete", restoreComplete));
        result.Properties.Add(new PSNoteProperty("BackupFilesCount", fullNameCount));
        result.Properties.Add(new PSNoteProperty("RestoredFilesCount", physicalNames.Count));
        result.Properties.Add(new PSNoteProperty("BackupSizeMB", backupSizeMb));
        result.Properties.Add(new PSNoteProperty("CompressedBackupSizeMB", compressedBackupSizeMb));
        result.Properties.Add(new PSNoteProperty("BackupFile", string.Join(",", fullNames)));
        result.Properties.Add(new PSNoteProperty("RestoredFile", restoredFile));
        result.Properties.Add(new PSNoteProperty("RestoredFileFull", string.Join(",", physicalNames)));
        result.Properties.Add(new PSNoteProperty("RestoreDirectory", restoreDirectory));
        result.Properties.Add(new PSNoteProperty("BackupSize", backupSize));
        result.Properties.Add(new PSNoteProperty("CompressedBackupSize", compressedBackupSize));
        result.Properties.Add(new PSNoteProperty("BackupStartTime", PsProperty.Get(backup, "Start")));
        result.Properties.Add(new PSNoteProperty("BackupEndTime", PsProperty.Get(backup, "End")));
        result.Properties.Add(new PSNoteProperty("RestoreTargetTime", restoreTargetTime));
        result.Properties.Add(new PSNoteProperty("Script", script));
        result.Properties.Add(new PSNoteProperty("BackupFileRaw", backupFileRaw.ToArray()));
        result.Properties.Add(new PSNoteProperty("FileRestoreTime", NewTimeSpanSeconds((DateTime.Now - fileRestoreStartTime).TotalSeconds)));
        result.Properties.Add(new PSNoteProperty("DatabaseRestoreTime", NewTimeSpanSeconds((DateTime.Now - databaseRestoreStartTime).TotalSeconds)));
        result.Properties.Add(new PSNoteProperty("ExitError", exitError));

        OutputHelper.SetDefaultDisplayPropertySet(result,
            "ComputerName", "InstanceName", "SqlInstance", "BackupFile", "BackupFilesCount", "BackupSize", "CompressedBackupSize", "Database", "Owner", "DatabaseRestoreTime", "FileRestoreTime", "NoRecovery", "RestoreComplete", "RestoredFile", "RestoredFilesCount", "Script", "RestoreDirectory", "WithReplace");

        WriteObject(result);
    }

    // [PSCustomObject]@{Bytes = $x.Byte} | Measure-Object -Property Bytes -Sum: a null value
    // measures to 0, a Size measures to its byte count.
    private static long MeasureByteSum(object? sizeValue)
    {
        object? bytes = PsProperty.Get(sizeValue, "Byte");
        if (bytes is null)
            return 0;
        return (long)LanguagePrimitives.ConvertTo(bytes, typeof(long), System.Globalization.CultureInfo.InvariantCulture);
    }

    // New-TimeSpan -Seconds <double>: the parameter is Int32, so PS converts with banker's rounding.
    private static TimeSpan NewTimeSpanSeconds(double totalSeconds)
    {
        return new TimeSpan(0, 0, (int)Math.Round(totalSeconds, MidpointRounding.ToEven));
    }

    // Sort-Object -Unique: case-insensitive ascending sort with case-insensitive dedupe.
    private static List<string> SortUnique(List<string> values)
    {
        List<string> sorted = new(values);
        sorted.Sort(StringComparer.CurrentCultureIgnoreCase);
        List<string> unique = new();
        foreach (string value in sorted)
        {
            if (unique.Count == 0 || !string.Equals(unique[unique.Count - 1], value, StringComparison.CurrentCultureIgnoreCase))
                unique.Add(value);
        }
        return unique;
    }

    private static List<string> FlattenMemberStrings(object? collection, string propertyName)
    {
        List<string> results = new();
        if (collection is PSObject psCollection)
            collection = psCollection.BaseObject;
        if (collection is IEnumerable items and not string)
        {
            foreach (object? item in items)
            {
                object? value = PsProperty.Get(item, propertyName);
                if (value is IEnumerable nested and not string)
                {
                    foreach (object? inner in nested)
                    {
                        if (inner is not null)
                            results.Add(RestoreUtility.PsStringify(inner));
                    }
                }
                else if (value is not null)
                {
                    results.Add(RestoreUtility.PsStringify(value));
                }
            }
        }
        else if (collection is not null)
        {
            object? value = PsProperty.Get(collection, propertyName);
            if (value is not null)
                results.Add(RestoreUtility.PsStringify(value));
        }
        return results;
    }
}
