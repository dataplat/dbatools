#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Validates backup history objects to ensure successful database restoration (LSN chain,
/// file accessibility, database conflicts, directory creation). Port of
/// public/Test-DbaBackupInformation.ps1; surface pinned by
/// migration/baselines/Test-DbaBackupInformation.json.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaBackupInformation", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
[OutputType(typeof(Dataplat.Dbatools.Database.BackupHistory))]
public sealed class TestDbaBackupInformationCommand : DbaBaseCmdlet
{
    /// <summary>Backup history objects containing restore chain information, typically from Format-DbaBackupInformation.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public object[] BackupHistory { get; set; } = null!;

    /// <summary>The Sql Server instance that wil be performing the restore.</summary>
    [Parameter(Position = 1)]
    public DbaInstanceParameter? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 2)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Allows restoration over an existing database with the same name.</summary>
    [Parameter]
    public SwitchParameter WithReplace { get; set; }

    /// <summary>Indicates this is a continuation of an existing restore operation.</summary>
    [Parameter]
    public SwitchParameter Continue { get; set; }

    /// <summary>Performs limited validation focusing only on backup file accessibility.</summary>
    [Parameter]
    public SwitchParameter VerifyOnly { get; set; }

    /// <summary>Prevents automatic creation of missing target directories during validation.</summary>
    [Parameter]
    public SwitchParameter OutputScriptOnly { get; set; }

    private Server? _restoreInstance;
    private readonly List<object?> _internalHistory = new();

    protected override void BeginProcessing()
    {
        try
        {
            SmoConnectionRequest request = new()
            {
                Instance = SqlInstance,
                SqlCredential = SqlCredential
            };
            _restoreInstance = ConnectionService.GetServer(request);
            SetActiveConnection(_restoreInstance.ConnectionContext);
        }
        catch (Exception ex)
        {
            ErrorRecord record = new(ex, "dbatools_Test-DbaBackupInformation", ErrorCategory.ConnectionError, SqlInstance);
            StopFunction("Failure", target: SqlInstance, errorRecord: record, category: ErrorCategory.ConnectionError);
            return;
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (object bh in BackupHistory)
        {
            if (!PsProperty.Has(bh, "IsVerified"))
            {
                PsProperty.AddNote(bh, "IsVerified", false);
            }
            _internalHistory.Add(bh);
        }
    }

    protected override void EndProcessing()
    {
        if (Interrupted)
        {
            return;
        }

        // Get-DbaDbPhysicalFile is a PRIVATE dbatools function, invisible to nested command
        // resolution from a binary module — ported as an internal helper instead.
        System.Data.DataRow[] registeredFileCheck = RestoreUtility.GetDbaDbPhysicalFile(this, _restoreInstance!);

        // $InternalHistory.Database | Select-Object -Unique (case-sensitive, first-seen order)
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
            int verificationErrors = 0;
            WriteMessage(MessageLevel.Verbose, $"Testing restore for {database}");
            //Test we're only restoring backups from one database, or hilarity will ensure
            List<object?> dbHistory = new();
            foreach (object? history in _internalHistory)
            {
                if (PsOps.Eq(PsProperty.Get(history, "Database"), database))
                    dbHistory.Add(history);
            }
            // Sort-Object -Property OriginalDatabase -Unique (case-insensitive distinct)
            HashSet<string> originals = new(StringComparer.OrdinalIgnoreCase);
            foreach (object? history in dbHistory)
                originals.Add(RestoreUtility.PsStringify(PsProperty.Get(history, "OriginalDatabase")));
            if (originals.Count > 1)
            {
                WriteMessage(MessageLevel.Warning, $"Trying to restore {database} from multiple sources databases");
                verificationErrors++;
            }
            //Test Db Existance on destination
            Hashtable dbCheckParms = new()
            {
                ["SqlInstance"] = _restoreInstance,
                ["Database"] = database
            };
            Collection<PSObject> dbCheck = NestedCommand.Invoke(this, "Get-DbaDatabase", dbCheckParms);
            // Only do file and db tests if we're not verifing
            WriteMessage(MessageLevel.Verbose, $"VerifyOnly = {PsBool.Text(VerifyOnly.ToBool())}");
            if (!VerifyOnly.ToBool())
            {
                if (dbCheck.Count > 0 && !WithReplace.ToBool() && !Continue.ToBool())
                {
                    WriteMessage(MessageLevel.Warning, $"Database {database} exists, so WithReplace must be specified", target: database);
                    verificationErrors++;
                }

                List<object?> dbFileCheck = new();
                List<object?> otherFileCheck = new();
                foreach (System.Data.DataRow registered in registeredFileCheck)
                {
                    if (PsOps.Eq(PsProperty.Get(registered, "Name"), database))
                        dbFileCheck.Add(PsProperty.Get(registered, "PhysicalName"));
                    else
                        otherFileCheck.Add(PsProperty.Get(registered, "PhysicalName"));
                }

                // Select-Object -ExpandProperty filelist | Select-Object PhysicalName -Unique
                List<string> dbHistoryPhysicalPaths = new();
                HashSet<string> seenPaths = new(StringComparer.Ordinal);
                foreach (object? history in dbHistory)
                {
                    if (PsProperty.Get(history, "FileList") is IEnumerable fileList and not string)
                    {
                        foreach (object? file in fileList)
                        {
                            string physicalName = RestoreUtility.PsStringify(PsProperty.Get(file, "PhysicalName"));
                            if (seenPaths.Add(physicalName))
                                dbHistoryPhysicalPaths.Add(physicalName);
                        }
                    }
                }

                Hashtable historyPathParms = new()
                {
                    ["SqlInstance"] = _restoreInstance,
                    ["Path"] = dbHistoryPhysicalPaths.Count == 1 ? dbHistoryPhysicalPaths[0] : (object)dbHistoryPhysicalPaths.ToArray()
                };
                Collection<PSObject> dbHistoryPhysicalPathsTest = dbHistoryPhysicalPaths.Count > 0
                    ? NestedCommand.Invoke(this, "Test-DbaPath", historyPathParms)
                    : new Collection<PSObject>();
                List<object?> dbHistoryPhysicalPathsExists = new();
                foreach (PSObject entry in dbHistoryPhysicalPathsTest)
                {
                    if (PsOps.Eq(PsProperty.Get(entry, "FileExists"), true))
                        dbHistoryPhysicalPathsExists.Add(PsProperty.Get(entry, "FilePath"));
                }
                string pathSep = RestoreUtility.GetPathSep(_restoreInstance);
                foreach (string path in dbHistoryPhysicalPaths)
                {
                    bool fileExists = false;
                    foreach (PSObject entry in dbHistoryPhysicalPathsTest)
                    {
                        if (PsOps.Eq(PsProperty.Get(entry, "FilePath"), path))
                        {
                            fileExists = PsOps.IsTrue(PsProperty.Get(entry, "FileExists"));
                            break;
                        }
                    }
                    if (fileExists)
                    {
                        if (PsOps.In(path, dbFileCheck))
                        {
                            //If the Files are owned by the db we're restoring check for Continue or WithReplace. If not, then report error otherwise just carry on
                            if (!WithReplace.ToBool() && !Continue.ToBool())
                            {
                                WriteMessage(MessageLevel.Warning, $"File {path} already exists on {RestoreUtility.PsStringify(SqlInstance)} and WithReplace not specified, cannot restore");
                                verificationErrors++;
                            }
                        }
                        else if (PsOps.In(path, otherFileCheck))
                        {
                            WriteMessage(MessageLevel.Warning, $"File {path} already exists on {RestoreUtility.PsStringify(SqlInstance)} and owned by another database, cannot restore");
                            verificationErrors++;
                        }
                        else if (PsOps.In(path, dbHistoryPhysicalPathsExists) && _restoreInstance!.VersionMajor > 8)
                        {
                            WriteMessage(MessageLevel.Warning, $"File {path} already exists on {RestoreUtility.PsStringify(SqlInstance?.ComputerName)}, not owned by any database in {RestoreUtility.PsStringify(SqlInstance)}, will not overwrite.");
                            verificationErrors++;
                        }
                    }
                    else
                    {
                        /*
                        dang, Split-Path converts path separators always using the "current system" settings
                        PS C:> Split-Path -Path '/var/opt/mssql/data/foo.bak' -Parent
                        \var\opt\mssql\data
                        I'm not aware of a safe way to change this so...we do a little hack.
                        */
                        pathSep = RestoreUtility.GetPathSep(_restoreInstance);
                        string parentPath = System.IO.Path.GetDirectoryName(path) ?? "";
                        parentPath = parentPath.Replace('\\', pathSep.Length > 0 ? pathSep[0] : '\\');
                        Hashtable parentParms = new()
                        {
                            ["SqlInstance"] = _restoreInstance,
                            ["Path"] = parentPath
                        };
                        Collection<PSObject> parentTest = NestedCommand.Invoke(this, "Test-DbaPath", parentParms);
                        bool parentExists = parentTest.Count > 0 && LanguagePrimitives.IsTrue(parentTest.Count == 1 ? parentTest[0] : parentTest);
                        if (!parentExists)
                        {
                            if (!OutputScriptOnly.ToBool())
                            {
                                string confirmMessage = $"\n Creating Folder {parentPath} on {RestoreUtility.PsStringify(SqlInstance)} \n";
                                if (ShouldProcess($"{path} on {RestoreUtility.PsStringify(SqlInstance)} \n \n", confirmMessage))
                                {
                                    Hashtable newDirParms = new()
                                    {
                                        ["SqlInstance"] = _restoreInstance,
                                        ["Path"] = parentPath
                                    };
                                    Collection<PSObject> newDir = NestedCommand.Invoke(this, "New-DbaDirectory", newDirParms);
                                    if (LanguagePrimitives.IsTrue(newDir.Count == 1 ? newDir[0] : newDir) && newDir.Count > 0)
                                    {
                                        WriteMessage(MessageLevel.Verbose, $"Created Folder {parentPath} on {RestoreUtility.PsStringify(SqlInstance)}");
                                    }
                                    else
                                    {
                                        WriteMessage(MessageLevel.Warning, $"Failed to create {parentPath} on {RestoreUtility.PsStringify(SqlInstance)}");
                                        verificationErrors++;
                                    }
                                }
                            }
                            else
                            {
                                WriteMessage(MessageLevel.Verbose, $"Parth {parentPath} on {RestoreUtility.PsStringify(SqlInstance)} does not exist");
                            }
                        }
                    }
                }
                //Test for LSN chain
                if (!Continue.ToBool())
                {
                    List<PSObject> chainInput = new();
                    foreach (object? history in dbHistory)
                    {
                        if (history is not null)
                            chainInput.Add(PSObject.AsPSObject(history));
                    }
                    // Test-DbaLsnChain is invoked without -Continue or -EnableException in the PS source.
                    if (!LsnChain.Test(this, chainInput, continueRestore: false, enableException: false))
                    {
                        WriteMessage(MessageLevel.Verbose, "LSN Check failed");
                        verificationErrors++;
                    }
                }
            }

            //Test all backups readable
            List<string> allPaths = new();
            foreach (object? history in dbHistory)
            {
                object? fullName = PsProperty.Get(history, "FullName");
                if (fullName is IEnumerable names and not string)
                {
                    foreach (object? name in names)
                        allPaths.Add(RestoreUtility.PsStringify(name));
                }
                else if (fullName is not null)
                {
                    allPaths.Add(RestoreUtility.PsStringify(fullName));
                }
            }
            Hashtable allPathParms = new()
            {
                ["SqlInstance"] = _restoreInstance,
                ["Path"] = allPaths.Count == 1 ? allPaths[0] : (object)allPaths.ToArray()
            };
            Collection<PSObject> allPathsValidity = allPaths.Count > 0
                ? NestedCommand.Invoke(this, "Test-DbaPath", allPathParms)
                : new Collection<PSObject>();
            foreach (PSObject pathResult in allPathsValidity)
            {
                // For a single path Test-DbaPath returns a bare bool whose FileExists reads as
                // null; null -eq $false is FALSE in PS, so no warning fires. Preserved.
                string filePath = RestoreUtility.PsStringify(PsProperty.Get(pathResult, "FilePath"));
                if (PsOps.Eq(PsProperty.Get(pathResult, "FileExists"), false)
                    && !filePath.StartsWith("http", StringComparison.OrdinalIgnoreCase)
                    && !filePath.StartsWith("s3", StringComparison.OrdinalIgnoreCase))
                {
                    WriteMessage(MessageLevel.Warning, $"Backup File {filePath} cannot be read by {_restoreInstance!.Name}. Does the service account ({RestoreUtility.PsStringify(PsProperty.Get(_restoreInstance, "ServiceAccount"))}) have permission?");
                    verificationErrors++;
                }
            }

            if (verificationErrors == 0)
            {
                WriteMessage(MessageLevel.Verbose, $"Marking {database} as verified");
                foreach (object? history in _internalHistory)
                {
                    if (PsOps.Eq(PsProperty.Get(history, "Database"), database))
                        PsProperty.Set(history!, "IsVerified", true);
                }
            }
            else
            {
                WriteMessage(MessageLevel.Verbose, $"Verification errors  = {verificationErrors} - Has not Passed");
            }
        }
        foreach (object? history in _internalHistory)
            WriteObject(history);
    }
}
