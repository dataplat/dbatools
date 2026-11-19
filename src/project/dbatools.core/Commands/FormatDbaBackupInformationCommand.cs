#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Message;

namespace Dataplat.Dbatools.Commands;

// Port of public/Format-DbaBackupInformation.ps1 at refs/pins/dbatools-2026-10-22.
/// <summary>Modifies backup history metadata to prepare database restores with different names, paths, or locations</summary>
/// <para>Takes backup history objects from Select-DbaBackupInformation and transforms them for restore scenarios where you need to change database names, file locations, or backup paths. This is essential for disaster recovery situations where you're restoring to different servers, renaming databases, or moving files to new storage locations. The function handles all the metadata transformations needed so you don't have to manually edit restore paths and database references before running Restore-DbaDatabase.</para>
/// <list type="alertSet">
///   <item>
///     <term></term>
///     <description>
///       <para>Tags: DisasterRecovery, Backup, Restore</para>
///       <para>Author: Stuart Moore (@napalmgram), stuart-moore.com</para>
///       <para>Website: https://dbatools.io</para>
///       <para>Copyright: (c) 2018 by dbatools, licensed under MIT</para>
///       <para>License: MIT https://opensource.org/licenses/MIT</para>
///     </description>
///   </item>
/// </list>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>$History | Format-DbaBackupInformation -ReplaceDatabaseName NewDb -ReplaceDbNameInFile</code>
///   <para>Changes as database name references to NewDb, both in the database name and any restore paths. Note, this will fail if the BackupHistory object contains backups for more than 1 database</para>
/// </example>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>$History | Format-DbaBackupInformation -ReplaceDatabaseName @{'OldB'='NewDb';'ProdHr'='DevHr'}</code>
///   <para>Will change all occurrences of original database name in the backup history (names and restore paths) using the mapping in the hashtable.</para>
///   <para>In this example any occurrence of OldDb will be replaced with NewDb and ProdHr with DevPR</para>
/// </example>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>$History | Format-DbaBackupInformation -DataFileDirectory 'D:\DataFiles\' -LogFileDirectory 'E:\LogFiles\</code>
///   <para>This example with change the restore path for all data files (everything that is not a log file) to d:\datafiles</para>
///   <para>And all Transaction Log files will be restored to E:\Logfiles</para>
/// </example>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>$History | Format-DbaBackupInformation -RebaseBackupFolder f:\backups</code>
///   <para>This example changes the location that SQL Server will look for the backups. This is useful if you've moved the backups to a different location</para>
/// </example>
/// <seealso href="https://dbatools.io/Format-DbaBackupInformation"/>
[Cmdlet(VerbsCommon.Format, "DbaBackupInformation")]
[OutputType(typeof(Dataplat.Dbatools.Database.BackupHistory))]
public sealed class FormatDbaBackupInformationCommand : DbaBaseCmdlet
{
    /// <para>Backup history objects from Select-DbaBackupInformation that contain metadata about database backups.</para>
    /// <para>Use this to pass backup information that needs to be modified for restore operations to different locations or with different names.</para>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public object[] BackupHistory { get; set; } = null!;

    /// <para>Changes the database name in backup history to prepare for restoring with a different name. Pass a single string to rename one database, or a hashtable to map multiple old names to new names.</para>
    /// <para>Use this when restoring databases to different environments or creating copies with new names.</para>
    /// <para>Database names in file paths are also updated, but logical file names require separate ALTER DATABASE commands after restore.</para>
    [Parameter(Position = 1)]
    public object? ReplaceDatabaseName { get; set; }

    /// <para>Replaces occurrences of the original database name within physical file names with the new database name.</para>
    /// <para>Use this in combination with ReplaceDatabaseName to ensure file names match the new database name and avoid confusion during restore operations.</para>
    [Parameter]
    public SwitchParameter ReplaceDbNameInFile { get; set; }

    /// <para>Sets the destination directory for all data files during restore. This overrides the original file locations stored in the backup.</para>
    /// <para>Use this when restoring to servers with different drive configurations or when consolidating database files to specific storage locations.</para>
    [Parameter(Position = 2)]
    public string? DataFileDirectory { get; set; }

    /// <para>Sets the destination directory specifically for transaction log files during restore. This takes precedence over DataFileDirectory for log files only.</para>
    /// <para>Use this to place log files on separate storage from data files for performance optimization or storage management requirements.</para>
    [Parameter(Position = 3)]
    public string? LogFileDirectory { get; set; }

    /// <para>Sets the destination directory for FileStream data files during restore. This takes precedence over DataFileDirectory for FileStream files only.</para>
    /// <para>Use this when databases contain FileStream data that needs to be stored on specific storage optimized for large file handling.</para>
    [Parameter(Position = 4)]
    public string? DestinationFileStreamDirectory { get; set; }

    /// <para>Adds a prefix to all database names during the restore operation. The prefix is applied after any name replacements from ReplaceDatabaseName.</para>
    /// <para>Use this to create standardized naming conventions like adding environment identifiers (Dev_, Test_, etc.) to restored databases.</para>
    [Parameter(Position = 5)]
    public string? DatabaseNamePrefix { get; set; }

    /// <para>Adds a prefix to the physical file names of all restored database files (both data and log files).</para>
    /// <para>Use this to avoid file name conflicts when restoring to servers that already have files with the same names.</para>
    [Parameter(Position = 6)]
    public string? DatabaseFilePrefix { get; set; }

    /// <para>Adds a suffix to the physical file names of all restored database files (both data and log files).</para>
    /// <para>Use this to create unique file names when restoring multiple copies of the same database or to add version identifiers to restored files.</para>
    [Parameter(Position = 7)]
    public string? DatabaseFileSuffix { get; set; }

    /// <para>Changes the path where SQL Server will look for backup files during the restore operation.</para>
    /// <para>Use this when backup files have been moved to a different location since the backup was created, such as copying backups to a disaster recovery site.</para>
    [Parameter(Position = 8)]
    public string? RebaseBackupFolder { get; set; }

    /// <para>Marks this as part of an ongoing restore sequence that will have additional transaction log backups applied later.</para>
    /// <para>Use this when performing point-in-time recovery scenarios where you need to restore a full backup followed by multiple log backups.</para>
    [Parameter]
    public SwitchParameter Continue { get; set; }

    /// <para>Maps specific logical file names to custom physical file paths during restore. Use hashtable format like @{'LogicalName1'='C:\NewPath\file1.mdf'}.</para>
    /// <para>Use this when you need granular control over where individual database files are restored, overriding directory-based parameters.</para>
    /// <para>Files not specified in the mapping retain their original locations, and this parameter takes precedence over all other file location settings.</para>
    [Parameter(Position = 9)]
    public Hashtable? FileMapping { get; set; }

    /// <para>Specifies the path separator character for file paths. Defaults to backslash (\) for Windows.</para>
    /// <para>Use forward slash (/) when working with Linux SQL Server instances or when backup history contains Unix-style paths.</para>
    [Parameter(Position = 10)]
    public string PathSep { get; set; } = "\\";

    // The pinned -Replace '.$': (?=\n?\z) is what '$' matches without RegexOptions.Multiline.
    private const string LastCharacter = ".(?=\\n?\\z)";

    private string? _replaceDatabaseNameType;

    protected override void BeginProcessing()
    {
        // PS [string] parameters read as '' when unbound; the body leans on '' -ne checks.
        DataFileDirectory = RestoreUtility.PsString(DataFileDirectory);
        LogFileDirectory = RestoreUtility.PsString(LogFileDirectory);
        DestinationFileStreamDirectory = RestoreUtility.PsString(DestinationFileStreamDirectory);
        DatabaseNamePrefix = RestoreUtility.PsString(DatabaseNamePrefix);
        DatabaseFilePrefix = RestoreUtility.PsString(DatabaseFilePrefix);
        DatabaseFileSuffix = RestoreUtility.PsString(DatabaseFileSuffix);
        RebaseBackupFolder = RestoreUtility.PsString(RebaseBackupFolder);
        PathSep = RestoreUtility.PsString(PathSep);

        WriteMessage(MessageLevel.Verbose, "Starting");
        if (ReplaceDatabaseName is not null)
        {
            object replaceValue = ReplaceDatabaseName is PSObject psValue ? psValue.BaseObject : ReplaceDatabaseName;
            // PS quirk preserved: anything whose ToString() is not the hashtable type name
            // counts as a 'single' rename value, not just strings.
            if (replaceValue is string || replaceValue.ToString() != "System.Collections.Hashtable")
            {
                WriteMessage(MessageLevel.Verbose, "String passed in for DB rename");
                _replaceDatabaseNameType = "single";
            }
            else if (replaceValue is Hashtable || replaceValue.ToString() == "System.Collections.Hashtable")
            {
                WriteMessage(MessageLevel.Verbose, "Hashtable passed in for DB rename");
                _replaceDatabaseNameType = "multi";
            }
            else
            {
                WriteMessage(MessageLevel.Verbose, string.Concat("ReplacemenDatabaseName is ", replaceValue.GetType().ToString(), " - ", RestoreUtility.PsStringify(ReplaceDatabaseName)));
            }
        }
        if (TestBound("DataFileDirectory") && DataFileDirectory!.EndsWith(PathSep, StringComparison.Ordinal))
        {
            DataFileDirectory = Regex.Replace(DataFileDirectory, LastCharacter, "");
        }
        if (TestBound("DestinationFileStreamDirectory") && DestinationFileStreamDirectory!.EndsWith(PathSep, StringComparison.Ordinal))
        {
            DestinationFileStreamDirectory = Regex.Replace(DestinationFileStreamDirectory, LastCharacter, "");
        }
        if (TestBound("LogFileDirectory") && LogFileDirectory!.EndsWith(PathSep, StringComparison.Ordinal))
        {
            LogFileDirectory = Regex.Replace(LogFileDirectory, LastCharacter, "");
        }
        if (TestBound("RebaseBackupFolder") && RebaseBackupFolder!.EndsWith(PathSep, StringComparison.Ordinal))
        {
            RebaseBackupFolder = Regex.Replace(RebaseBackupFolder, LastCharacter, "");
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (object history in BackupHistory)
        {
            if (!PsProperty.Has(history, "OriginalDatabase"))
            {
                PsProperty.AddNote(history, "OriginalDatabase", PsProperty.Get(history, "Database"));
            }
            if (!PsProperty.Has(history, "OriginalFileList"))
            {
                // Correction original-filelist-snapshot: the pinned note shared the live FileList,
                // whose entries the loop below changes, so it never held the original paths.
                PsProperty.AddNote(history, "OriginalFileList", "");
                PsProperty.Set(history, "OriginalFileList", SnapshotFileList(PsProperty.Get(history, "FileList")));
            }
            if (!PsProperty.Has(history, "OriginalFullName"))
            {
                // Correction original-fullname-snapshot: the pinned note shared the FullName array
                // that -RebaseBackupFolder rewrites in place.
                PsProperty.AddNote(history, "OriginalFullName", CopyCollection(PsProperty.Get(history, "FullName")));
            }
            if (!PsProperty.Has(history, "IsVerified"))
            {
                PsProperty.AddNote(history, "IsVerified", false);
            }
            string currentType = RestoreUtility.PsStringify(PsProperty.Get(history, "Type"));
            if (PsString.Eq(currentType, "Full"))
            {
                PsProperty.Set(history, "Type", "Database");
            }
            else if (PsString.Eq(currentType, "Differential"))
            {
                PsProperty.Set(history, "Type", "Database Differential");
            }
            else if (PsString.Eq(currentType, "Log"))
            {
                PsProperty.Set(history, "Type", "Transaction Log");
            }

            if (_replaceDatabaseNameType == "single" && RestoreUtility.PsStringify(ReplaceDatabaseName) != "")
            {
                PsProperty.Set(history, "Database", ReplaceDatabaseName is PSObject ps ? ps.BaseObject : ReplaceDatabaseName);
                WriteMessage(MessageLevel.Verbose, "New DbName (String) = " + RestoreUtility.PsStringify(PsProperty.Get(history, "Database")));
            }
            else if (_replaceDatabaseNameType == "multi")
            {
                Hashtable? map = (ReplaceDatabaseName is PSObject psMap ? psMap.BaseObject : ReplaceDatabaseName) as Hashtable;
                object? mapped = map?[RestoreUtility.PsStringify(PsProperty.Get(history, "Database"))];
                if (mapped is not null)
                {
                    PsProperty.Set(history, "Database", mapped);
                    WriteMessage(MessageLevel.Verbose, "New DbName (Hash) = " + RestoreUtility.PsStringify(PsProperty.Get(history, "Database")));
                }
            }
            PsProperty.Set(history, "Database", DatabaseNamePrefix + RestoreUtility.PsStringify(PsProperty.Get(history, "Database")));

            // Capture rename values before entering the ForEach-Object pipeline to ensure correct
            // scoping and to treat both database names literally during file renames
            string originalDb = RestoreUtility.PsStringify(PsProperty.Get(history, "OriginalDatabase"));
            string newDb = RestoreUtility.PsStringify(PsProperty.Get(history, "Database"));

            object? fileListValue = PsProperty.Get(history, "FileList");
            IEnumerable fileList = fileListValue is IEnumerable enumerable and not string
                ? enumerable
                : new object?[] { fileListValue };
            {
                foreach (object? fileRaw in fileList)
                {
                    if (fileRaw is null)
                        continue;
                    object file = fileRaw;
                    if (FileMapping is not null)
                    {
                        object? mappedPath = FileMapping[RestoreUtility.PsStringify(PsProperty.Get(file, "LogicalName"))];
                        if (mappedPath is not null)
                        {
                            PsProperty.Set(file, "PhysicalName", mappedPath);
                        }
                    }
                    else
                    {
                        WriteMessage(MessageLevel.Verbose, " 1 PhysicalName = " + RestoreUtility.PsStringify(PsProperty.Get(file, "PhysicalName")) + " ");

                        // Instead of using [System.IO.FileInfo] which has cross-platform issues,
                        // manually parse the path using both separators to handle Windows paths on Linux and vice versa
                        string originalPath = RestoreUtility.PsStringify(PsProperty.Get(file, "PhysicalName"));

                        // Get just the filename by splitting on both separators
                        string[] pathParts = Regex.Split(originalPath, "[/\\\\]");
                        string fileName = pathParts[pathParts.Length - 1];
                        string baseName = System.IO.Path.GetFileNameWithoutExtension(fileName);
                        string extension = System.IO.Path.GetExtension(fileName);

                        // Handle MacOS returning full path for BaseName
                        if (PathSep.Length > 0)
                        {
                            string[] baseParts = baseName.Split(PathSep.ToCharArray());
                            baseName = baseParts[baseParts.Length - 1];
                        }

                        if (ReplaceDbNameInFile.ToBool())
                        {
                            baseName = Regex.Replace(
                                baseName,
                                Regex.Escape(originalDb),
                                new MatchEvaluator(_ => newDb),
                                RegexOptions.IgnoreCase);
                        }

                        // Determine restore directory based on file type
                        string? restoreDir = null;
                        string fileType = RestoreUtility.PsStringify(PsProperty.Get(file, "Type"));
                        string fileTypeAlt = RestoreUtility.PsStringify(PsProperty.Get(file, "FileType"));
                        if (PsString.Eq(fileType, "D") || PsString.Eq(fileTypeAlt, "D"))
                        {
                            if (DataFileDirectory != "")
                            {
                                restoreDir = DataFileDirectory;
                            }
                        }
                        else if (PsString.Eq(fileType, "L") || PsString.Eq(fileTypeAlt, "L"))
                        {
                            if (LogFileDirectory != "")
                            {
                                restoreDir = LogFileDirectory;
                            }
                            else if (DataFileDirectory != "")
                            {
                                restoreDir = DataFileDirectory;
                            }
                        }
                        else if (PsString.Eq(fileType, "S") || PsString.Eq(fileTypeAlt, "S"))
                        {
                            if (DestinationFileStreamDirectory != "")
                            {
                                restoreDir = DestinationFileStreamDirectory;
                            }
                            else if (DataFileDirectory != "")
                            {
                                restoreDir = DataFileDirectory;
                            }
                        }

                        // Fallback to extracting directory from original path if no destination specified
                        restoreDir ??= Regex.Replace(originalPath, "[/\\\\][^/\\\\]+(?=\\n?\\z)", "");

                        // A URL restore directory (Azure blob, S3) joins with '/' whatever PathSep says.
                        string restorePathSeparator = PathSep;
                        if (Regex.IsMatch(restoreDir, "^[a-z][a-z0-9+.-]*://", RegexOptions.IgnoreCase))
                        {
                            restorePathSeparator = "/";
                            restoreDir = restoreDir.TrimEnd('/');
                        }

                        PsProperty.Set(file, "PhysicalName", restoreDir + restorePathSeparator + DatabaseFilePrefix + baseName + DatabaseFileSuffix + extension);
                        WriteMessage(MessageLevel.Verbose, "PhysicalName = " + RestoreUtility.PsStringify(PsProperty.Get(file, "PhysicalName")) + " ");
                    }
                }
            }

            object? fullNameRaw = PsProperty.Get(history, "FullName");
            string firstFullName = fullNameRaw is IList { Count: > 0 } fullNameList
                ? RestoreUtility.PsStringify(fullNameList[0])
                : fullNameRaw is string s && s.Length > 0 ? s[0].ToString() : "";
            if (RebaseBackupFolder != "" && !Regex.IsMatch(firstFullName, "http", RegexOptions.IgnoreCase))
            {
                WriteMessage(MessageLevel.Verbose, "Rebasing backup files");

                if (fullNameRaw is IList rebaseList)
                {
                    for (int j = 0; j < rebaseList.Count; j++)
                    {
                        System.IO.FileInfo fileInfo = new(RestoreUtility.PsStringify(rebaseList[j]));
                        rebaseList[j] = RebaseBackupFolder + PathSep + System.IO.Path.GetFileNameWithoutExtension(fileInfo.Name) + fileInfo.Extension;
                    }
                }
            }

            WriteObject(history);
        }
    }

    /// <summary>A copy of a collection of the same type (array or cloneable list); anything else as it is.</summary>
    private static object? CopyCollection(object? value)
    {
        return value switch
        {
            Array array => array.Clone(),
            IList and ICloneable cloneable => cloneable.Clone(),
            _ => value,
        };
    }

    /// <summary>The FileList as it is now: a copy of the collection with every entry copied, so later
    /// changes to the live entries do not reach it.</summary>
    private static object? SnapshotFileList(object? fileList)
    {
        switch (fileList)
        {
            case null:
            case string:
                return fileList;
            case Array array when array.GetType().GetElementType()?.IsAssignableFrom(typeof(PSObject)) == true:
                return CopyEntries((IList)array.Clone());
            case IList list when list is not Array && CopyCollection(list) is IList copy && !ReferenceEquals(copy, list) && !copy.IsReadOnly:
                return CopyEntries(copy);
            case IEnumerable entries:
                List<object?> copied = new();
                foreach (object? entry in entries)
                {
                    copied.Add(CopyEntry(entry));
                }
                return copied.ToArray();
            default:
                return CopyEntry(fileList);
        }
    }

    private static IList CopyEntries(IList entries)
    {
        for (int i = 0; i < entries.Count; i++)
        {
            entries[i] = CopyEntry(entries[i]);
        }
        return entries;
    }

    /// <summary>PSObject.Copy() gives a PSCustomObject or deserialized entry its own note properties.</summary>
    private static object? CopyEntry(object? entry)
    {
        return entry is null or string or ValueType ? entry : PSObject.AsPSObject(entry).Copy();
    }
}
