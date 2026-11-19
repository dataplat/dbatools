#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Migrates user databases between instances by backup/restore or detach/attach. Port of
/// public/Copy-DbaDatabase.ps1.
/// </summary>
/// <remarks>
/// The whole workflow rides module-scoped PowerShell hops: the body drives Backup-DbaDatabase,
/// Restore-DbaDatabase, Set-DbaDbState, Remove-DbaDatabase, SMO detach/attach, BITS file
/// transfer over admin shares and Select-DefaultView decoration, all of which keep the retired
/// function's engine semantics there.
///
/// Three hops, matching the source's three blocks. The begin hop runs the parameter-combination
/// validations, which latch Test-FunctionInterrupt; the process hop runs the per-record
/// migration; the end hop deletes the shared backups when more than one destination was
/// targeted and writes the elapsed-time summary. The source declares its five internal helpers
/// (Get-SqlFileStructure, Dismount-SqlDatabase, Mount-SqlDatabase, Start-SqlFileTransfer,
/// Start-SqlDetachAttach) in begin and calls them from process; because a hop scriptblock is a
/// fresh scope, they are declared at the top of the process hop instead. They read
/// $databaseList, $dbFileTable, $sourceServer and friends out of the enclosing scope exactly as
/// they did in the function, which is why they cannot be lifted to C#.
///
/// Cross-record state lives in C# fields: the source's process block locals are function-scoped
/// and survive piped records, while each hop gets a fresh scope. $backupCollection is the
/// pipeline-spanning accumulator the end hop drains; $NoBackupCleanup and $WithReplace are
/// parameters the body REASSIGNS mid-run (a failed backup delete forces the first, -Force forces
/// the second) and both are read on later records and in end; $fsWarning and $replaceInFile are
/// set true and never reset; $sourceServer, $elapsed and $started are set in process and read
/// only in end; the three $sourceDb* property snapshots are taken only when the source is 2005
/// or higher, so on an older source a later record would read the previous one's values.
///
/// -WhatIf and -Confirm are carried into the process and end hops, not just routed through
/// $__realCmdlet: Start-SqlFileTransfer and Start-SqlDetachAttach declare their own
/// SupportsShouldProcess and gate on their own $PSCmdlet, which in the function inherited
/// $WhatIfPreference from the caller. Splatting the bound values into the hop's
/// [CmdletBinding(SupportsShouldProcess)] block reproduces that inheritance; without it those
/// two helpers would mutate under -WhatIf. Surface pinned by
/// migration/baselines/Copy-DbaDatabase.json.
/// </remarks>
[Cmdlet(VerbsCommon.Copy, "DbaDatabase", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium, DefaultParameterSetName = "DbBackup")]
public sealed class CopyDbaDatabaseCommand : DbaBaseCmdlet
{
    /// <summary>Specifies the source SQL Server instance containing the databases to migrate.</summary>
    [Parameter(ParameterSetName = "DbAttachDetach")]
    [Parameter(ParameterSetName = "DbBackup")]
    public DbaInstanceParameter? Source { get; set; }

    /// <summary>Specifies credentials for connecting to the source SQL Server instance when Windows authentication is not available.</summary>
    [Parameter(ParameterSetName = "DbAttachDetach")]
    [Parameter(ParameterSetName = "DbBackup")]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <summary>Specifies one or more destination SQL Server instances where databases will be migrated.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "DbAttachDetach")]
    [Parameter(Mandatory = true, ParameterSetName = "DbBackup")]
    public DbaInstanceParameter[] Destination { get; set; } = null!;

    /// <summary>Specifies credentials for connecting to the destination SQL Server instance when Windows authentication is not available.</summary>
    [Parameter(ParameterSetName = "DbAttachDetach")]
    [Parameter(ParameterSetName = "DbBackup")]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>Specifies which user databases to migrate by name.</summary>
    [Parameter(ParameterSetName = "DbAttachDetach")]
    [Parameter(ParameterSetName = "DbBackup")]
    public object[]? Database { get; set; }

    /// <summary>Specifies databases to exclude when using -AllDatabases.</summary>
    [Parameter(ParameterSetName = "DbAttachDetach")]
    [Parameter(ParameterSetName = "DbBackup")]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Migrates all user databases from the source instance, excluding system databases (master, model, msdb, tempdb).</summary>
    [Parameter(ParameterSetName = "DbAttachDetach")]
    [Parameter(ParameterSetName = "DbBackup")]
    [Alias("All")]
    public SwitchParameter AllDatabases { get; set; }

    /// <summary>Uses backup and restore method for database migration, creating copy-only backups to preserve existing backup chains.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "DbBackup")]
    public SwitchParameter BackupRestore { get; set; }

    /// <summary>Specifies additional parameters for the backup operation as a hashtable.</summary>
    [Parameter(ParameterSetName = "DbBackup")]
    public Hashtable? AdvancedBackupParams { get; set; }

    /// <summary>Specifies the storage location accessible by both source and destination SQL Server instances.</summary>
    [Parameter(ParameterSetName = "DbBackup")]
    public string? SharedPath { get; set; }

    /// <summary>Specifies the SQL Server credential name for Azure blob storage authentication.</summary>
    [Parameter(ParameterSetName = "DbAttachDetach")]
    [Parameter(ParameterSetName = "DbBackup")]
    public string? AzureCredential { get; set; }

    /// <summary>Overwrites existing databases at the destination with the same name.</summary>
    [Parameter(ParameterSetName = "DbBackup")]
    public SwitchParameter WithReplace { get; set; }

    /// <summary>Restores databases in NORECOVERY mode, leaving them ready for additional transaction log restores.</summary>
    [Parameter(ParameterSetName = "DbBackup")]
    public SwitchParameter NoRecovery { get; set; }

    /// <summary>Preserves backup files after migration instead of automatically deleting them.</summary>
    [Parameter(ParameterSetName = "DbBackup")]
    public SwitchParameter NoBackupCleanup { get; set; }

    /// <summary>Specifies how many backup files to create for each database backup to improve performance.</summary>
    [Parameter(ParameterSetName = "DbBackup")]
    [ValidateRange(1, 64)]
    public int NumberFiles { get; set; } = 3;

    /// <summary>Uses detach/copy/attach method for database migration by moving physical database files.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "DbAttachDetach")]
    public SwitchParameter DetachAttach { get; set; }

    /// <summary>Reattaches databases to the source instance after successful detach/attach migration.</summary>
    [Parameter(ParameterSetName = "DbAttachDetach")]
    public SwitchParameter Reattach { get; set; }

    /// <summary>Sets source databases to read-only before migration to prevent data changes during the process.</summary>
    [Parameter(ParameterSetName = "DbAttachDetach")]
    [Parameter(ParameterSetName = "DbBackup")]
    public SwitchParameter SetSourceReadOnly { get; set; }

    /// <summary>Sets source databases offline before migration to prevent any connections during the process.</summary>
    [Parameter(ParameterSetName = "DbAttachDetach")]
    [Parameter(ParameterSetName = "DbBackup")]
    public SwitchParameter SetSourceOffline { get; set; }

    /// <summary>Maintains the exact file path structure from the source instance on the destination.</summary>
    [Parameter(ParameterSetName = "DbAttachDetach")]
    [Parameter(ParameterSetName = "DbBackup")]
    [Alias("ReuseFolderStructure")]
    public SwitchParameter ReuseSourceFolderStructure { get; set; }

    /// <summary>Migrates SQL Server feature databases including ReportServer, ReportServerTempDB, SSISDB, and distribution databases.</summary>
    [Parameter(ParameterSetName = "DbAttachDetach")]
    [Parameter(ParameterSetName = "DbBackup")]
    public SwitchParameter IncludeSupportDbs { get; set; }

    /// <summary>Uses existing backups from backup history instead of creating new ones.</summary>
    [Parameter(ParameterSetName = "DbBackup")]
    public SwitchParameter UseLastBackup { get; set; }

    /// <summary>Continues restoration by applying transaction log backups to databases in RECOVERING or STANDBY states.</summary>
    [Parameter(ParameterSetName = "DbBackup")]
    public SwitchParameter Continue { get; set; }

    /// <summary>Accepts database objects piped from Get-DbaDatabase for migration.</summary>
    [Parameter(ValueFromPipeline = true, ParameterSetName = "DbAttachDetach")]
    [Parameter(ValueFromPipeline = true, ParameterSetName = "DbBackup")]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    /// <summary>Creates regular backups instead of copy-only backups, which affects the database's backup chain.</summary>
    [Parameter(ParameterSetName = "DbAttachDetach")]
    [Parameter(ParameterSetName = "DbBackup")]
    public SwitchParameter NoCopyOnly { get; set; }

    /// <summary>Preserves Change Data Capture (CDC) configuration and data during migration.</summary>
    [Parameter(ParameterSetName = "DbBackup")]
    public SwitchParameter KeepCDC { get; set; }

    /// <summary>Preserves replication configuration during database migration.</summary>
    [Parameter(ParameterSetName = "DbBackup")]
    public SwitchParameter KeepReplication { get; set; }

    /// <summary>Renames the database during migration when copying a single database.</summary>
    [Parameter(ParameterSetName = "DbAttachDetach")]
    [Parameter(ParameterSetName = "DbBackup")]
    public string? NewName { get; set; }

    /// <summary>Adds a prefix to all migrated database names and their physical file names.</summary>
    [Parameter(ParameterSetName = "DbAttachDetach")]
    [Parameter(ParameterSetName = "DbBackup")]
    public string? Prefix { get; set; }

    /// <summary>Forcibly overwrites existing databases at the destination and bypasses safety checks.</summary>
    [Parameter(ParameterSetName = "DbAttachDetach")]
    [Parameter(ParameterSetName = "DbBackup")]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private object? _backupCollection;
    private object? _fsWarning;
    private object? _replaceInFile;
    private object? _sourceServer;
    private object? _elapsed;
    private object? _started;
    private object? _sourceDbOwnerChaining;
    private object? _sourceDbTrustworthy;
    private object? _sourceDbBrokerEnabled;

    // Two PARAMETERS the body reassigns mid-run, so they cannot ride the parameter slot: a
    // backup file that will not delete sets $NoBackupCleanup true so end warns, and -Force sets
    // $WithReplace true. Both are read on later records and in end, so they seed from the bound
    // value once and then live in the sentinel like any other cross-record local.
    private object? _noBackupCleanup;
    private object? _withReplace;

    protected override void BeginProcessing()
    {
        _noBackupCleanup = NoBackupCleanup.ToBool();
        _withReplace = WithReplace.ToBool();
        _backupCollection = Array.Empty<object>();

        // $InputObject is deliberately passed as it stands at begin time: a pipeline-bound value
        // is not populated yet, which is exactly what the function's begin block saw, and the
        // "with no piped input a -Source must be specified" check depends on that.
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else
            {
                WriteObject(item);
            }
        }, BeginScript,
            InputObject, Source, BackupRestore.ToBool(), SharedPath, UseLastBackup.ToBool(),
            DetachAttach.ToBool(), Reattach.ToBool(), Destination, Continue.ToBool(),
            EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"),
            NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
                if (item?.BaseObject is ErrorRecord nestedError)
                {
                    NestedCommand.RemoveDuplicateError(this, nestedError);
                    WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                }
                else if (item is not null && LanguagePrimitives.IsTrue(
                    item.Properties["__CopyDbaDatabaseProcessComplete"]?.Value))
                {
                    _backupCollection = UnwrapHopValue(item.Properties["backupCollection"]?.Value);
                    _noBackupCleanup = UnwrapHopValue(item.Properties["NoBackupCleanup"]?.Value);
                    _withReplace = UnwrapHopValue(item.Properties["WithReplace"]?.Value);
                    _fsWarning = UnwrapHopValue(item.Properties["fsWarning"]?.Value);
                    _replaceInFile = UnwrapHopValue(item.Properties["replaceInFile"]?.Value);
                    _sourceServer = UnwrapHopValue(item.Properties["sourceServer"]?.Value);
                    _elapsed = UnwrapHopValue(item.Properties["elapsed"]?.Value);
                    _started = UnwrapHopValue(item.Properties["started"]?.Value);
                    _sourceDbOwnerChaining = UnwrapHopValue(item.Properties["sourceDbOwnerChaining"]?.Value);
                    _sourceDbTrustworthy = UnwrapHopValue(item.Properties["sourceDbTrustworthy"]?.Value);
                    _sourceDbBrokerEnabled = UnwrapHopValue(item.Properties["sourceDbBrokerEnabled"]?.Value);
                }
                else
                {
                    WriteObject(item);
                }
        }, BodyScript,
                Source, SourceSqlCredential, Destination, DestinationSqlCredential, Database,
                ExcludeDatabase, AllDatabases.ToBool(), BackupRestore.ToBool(), AdvancedBackupParams,
                SharedPath, AzureCredential, _withReplace, NoRecovery.ToBool(),
                _noBackupCleanup, NumberFiles, DetachAttach.ToBool(), Reattach.ToBool(),
                SetSourceReadOnly.ToBool(), SetSourceOffline.ToBool(),
                ReuseSourceFolderStructure.ToBool(), IncludeSupportDbs.ToBool(),
                UseLastBackup.ToBool(), Continue.ToBool(), InputObject, NoCopyOnly.ToBool(),
                KeepCDC.ToBool(), KeepReplication.ToBool(), NewName, Prefix, Force.ToBool(),
                EnableException.ToBool(), TestBound(nameof(NewName)), TestBound(nameof(Prefix)),
                _backupCollection, _fsWarning, _replaceInFile, _sourceServer, _elapsed, _started,
                _sourceDbOwnerChaining, _sourceDbTrustworthy, _sourceDbBrokerEnabled, this,
                NestedCommand.BoundCommonParameter(this, "WhatIf"),
                NestedCommand.BoundCommonParameter(this, "Confirm"),
                NestedCommand.BoundCommonParameter(this, "Verbose"),
                NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void EndProcessing()
    {
        if (Interrupted)
        {
            return;
        }

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else
            {
                WriteObject(item);
            }
        }, EndScript,
            _noBackupCleanup, Destination, _backupCollection, _sourceServer, _elapsed, _started,
            SharedPath,
            NestedCommand.BoundCommonParameter(this, "Verbose"),
            NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // Carried hop state arrives PSObject-wrapped. A PSCustomObject carries its content on the
    // wrapper rather than the BaseObject, so unwrapping one would discard it - keep it wrapped.
    private static object? UnwrapHopValue(object? value)
    {
        if (value is null || ReferenceEquals(value, System.Management.Automation.Internal.AutomationNull.Value))
            return null;
        if (value is not PSObject wrapper)
            return value;
        return wrapper.BaseObject is PSCustomObject ? wrapper : wrapper.BaseObject;
    }
    private const string BodyScript = """
param($Source, $SourceSqlCredential, $Destination, $DestinationSqlCredential, $Database, $ExcludeDatabase, $AllDatabases, $BackupRestore, $AdvancedBackupParams, $SharedPath, $AzureCredential, $WithReplace, $NoRecovery, $NoBackupCleanup, $NumberFiles, $DetachAttach, $Reattach, $SetSourceReadOnly, $SetSourceOffline, $ReuseSourceFolderStructure, $IncludeSupportDbs, $UseLastBackup, $Continue, $InputObject, $NoCopyOnly, $KeepCDC, $KeepReplication, $NewName, $Prefix, $Force, $EnableException, $__boundNewName, $__boundPrefix, $backupCollection, $fsWarning, $replaceInFile, $sourceServer, $elapsed, $started, $sourceDbOwnerChaining, $sourceDbTrustworthy, $sourceDbBrokerEnabled, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    # The flag parameters are deliberately untyped. This block is called with positional
    # arguments, and PowerShell excludes [switch] parameters from positional binding - a single
    # [switch] in the list shifts every argument after it, so -Destination was receiving the
    # shared path. They arrive as real booleans from the cmdlet, which reads the same in every
    # test and pass-through the body performs.
    param([DbaInstanceParameter]$Source, [PSCredential]$SourceSqlCredential,
        [DbaInstanceParameter[]]$Destination, [PSCredential]$DestinationSqlCredential,
        [object[]]$Database, [object[]]$ExcludeDatabase, $AllDatabases,
        $BackupRestore, [hashtable]$AdvancedBackupParams, [string]$SharedPath,
        [string]$AzureCredential, $WithReplace, $NoRecovery,
        $NoBackupCleanup, [int]$NumberFiles, $DetachAttach, $Reattach,
        $SetSourceReadOnly, $SetSourceOffline, $ReuseSourceFolderStructure,
        $IncludeSupportDbs, $UseLastBackup, $Continue,
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $NoCopyOnly,
        $KeepCDC, $KeepReplication, [string]$NewName, [string]$Prefix,
        $Force, $EnableException, $__boundNewName, $__boundPrefix, $backupCollection,
        $fsWarning, $replaceInFile, $sourceServer, $elapsed, $started, $sourceDbOwnerChaining,
        $sourceDbTrustworthy, $sourceDbBrokerEnabled, $__realCmdlet)

    $CopyOnly = -not $NoCopyOnly

    if ($Force) {
        $ConfirmPreference = 'none'
    }

    function Get-SqlFileStructure {
        $dbcollection = @{
        };
        $databaseProgressbar = 0

        foreach ($db in $databaseList) {
            Write-Progress -Id 1 -Activity "Processing database file structure" -PercentComplete ($databaseProgressbar / $dbCount * 100) -Status "Processing $databaseProgressbar of $dbCount."
            $dbName = $db.Name
            Write-Message -Level Verbose -Message $dbName

            $databaseProgressbar++
            $dbStatus = $db.status.toString()
            if ($dbStatus.StartsWith("Normal") -eq $false) {
                continue
            }
            $destinstancefiles = @{
            }; $sourcefiles = @{
            }

            $where = "Filetype <> 'LOG' and Filetype <> 'FULLTEXT'"

            $datarows = $dbFileTable.Tables.Select("dbname = '$dbName' and $where")

            # Data Files
            foreach ($file in $datarows) {
                # Destination File Structure
                $d = @{
                }
                if ($ReuseSourceFolderStructure) {
                    $d.physical = $file.filename
                } elseif ($WithReplace) {
                    $name = $file.Name
                    $destfile = $remoteDbFileTable.Tables[0].Select("dbname = '$dbName' and name = '$name'")
                    $d.physical = $destfile.filename

                    if ($null -eq $d.physical) {
                        $directory = Get-SqlDefaultPaths $destServer data
                        $fileName = Split-Path $file.filename -Leaf
                        $d.physical = "$directory\$fileName"
                    }
                } else {
                    $directory = Get-SqlDefaultPaths $destServer data
                    $fileName = Split-Path $file.filename -Leaf
                    $d.physical = "$directory\$fileName"
                }
                $d.logical = $file.Name

                $d.remotefilename = Join-AdminUNC $destFullComputerName $d.physical
                $destinstancefiles.add($file.Name, $d)

                # Source File Structure
                $s = @{
                }
                $s.logical = $file.Name
                $s.physical = $file.filename
                $s.remotefilename = Join-AdminUNC $sourceFullComputerName $s.physical
                $sourcefiles.add($file.Name, $s)
            }

            # Add support for Full Text Catalogs in SQL Server 2005 and below
            if ($sourceServer.VersionMajor -lt 10) {
                try {
                    $fttable = $null = $sourceServer.Databases[$dbName].ExecuteWithResults('sp_help_fulltext_catalogs')
                    $allrows = $fttable.Tables[0].rows
                } catch {
                    # Nothing, it's just not enabled
                    # here to avoid an empty catch
                    $null = 1
                }

                foreach ($ftc in $allrows) {
                    # Destination File Structure
                    $d = @{
                    }
                    $pre = "sysft_"
                    $name = $ftc.Name
                    $physical = $ftc.Path # RootPath
                    $logical = "$pre$name"
                    if ($ReuseSourceFolderStructure) {
                        $d.physical = $physical
                    } else {
                        $directory = Get-SqlDefaultPaths $destServer data
                        if ($destServer.VersionMajor -lt 10) {
                            $directory = "$directory\FTDATA"
                        }
                        $fileName = Split-Path($physical) -Leaf
                        $d.physical = "$directory\$fileName"
                    }
                    $d.logical = $logical
                    $d.remotefilename = Join-AdminUNC $destFullComputerName $d.physical
                    $destinstancefiles.add($logical, $d)

                    # Source File Structure
                    $s = @{
                    }
                    $pre = "sysft_"
                    $name = $ftc.Name
                    $physical = $ftc.Path # RootPath
                    $logical = "$pre$name"

                    $s.logical = $logical
                    $s.physical = $physical
                    $s.remotefilename = Join-AdminUNC $sourceFullComputerName $s.physical
                    $sourcefiles.add($logical, $s)
                }
            }

            $where = "Filetype = 'LOG'"
            $datarows = $dbFileTable.Tables[0].Select("dbname = '$dbName' and $where")

            # Log Files
            foreach ($file in $datarows) {
                $d = @{
                }
                if ($ReuseSourceFolderStructure) {
                    $d.physical = $file.filename
                } elseif ($WithReplace) {
                    $name = $file.Name
                    $destfile = $remoteDbFileTable.Tables[0].Select("dbname = '$dbName' and name = '$name'")
                    $d.physical = $destfile.filename

                    if ($null -eq $d.physical) {
                        $directory = Get-SqlDefaultPaths $destServer log
                        $fileName = Split-Path $file.filename -Leaf
                        $d.physical = "$directory\$fileName"
                    }
                } else {
                    $directory = Get-SqlDefaultPaths $destServer log
                    $fileName = Split-Path $file.filename -Leaf
                    $d.physical = "$directory\$fileName"
                }
                $d.logical = $file.Name
                $d.remotefilename = Join-AdminUNC $destFullComputerName $d.physical
                $destinstancefiles.add($file.Name, $d)

                $s = @{
                }
                $s.logical = $file.Name
                $s.physical = $file.filename
                $s.remotefilename = Join-AdminUNC $sourceFullComputerName $s.physical
                $sourcefiles.add($file.Name, $s)
            }

            $location = @{
            }
            $location.add("Destination", $destinstancefiles)
            $location.add("Source", $sourcefiles)
            $dbcollection.Add($($db.Name), $location)
        }

        $fileStructure = [PSCustomObject]@{
            "databases" = $dbcollection
        }
        Write-Progress -Id 1 -Activity "Processing database file structure" -Status "Completed" -Completed
        return $fileStructure
    }

    function Dismount-SqlDatabase {
        [CmdletBinding()]
        param (
            [object]$server,
            [string]$dbName
        )

        $currentdb = $server.databases[$dbName]
        if ($currentdb.IsMirroringEnabled) {
            try {
                Write-Message -Level Verbose -Message "Breaking mirror for $dbName"
                $currentdb.ChangeMirroringState([Microsoft.SqlServer.Management.Smo.MirroringOption]::Off)
                $currentdb.Alter()
                $currentdb.Refresh()
                Write-Message -Level Verbose -Message "Could not break mirror for $dbName. Skipping."
            } catch {
                Stop-Function -Message "Issue breaking mirror." -Target $dbName -ErrorRecord $_
                return $false
            }
        }

        if ($currentdb.AvailabilityGroupName) {
            $agName = $currentdb.AvailabilityGroupName
            Write-Message -Level Verbose -Message "Attempting remove from Availability Group $agName."
            try {
                $server.AvailabilityGroups[$currentdb.AvailabilityGroupName].AvailabilityDatabases[$dbName].Drop()
                Write-Message -Level Verbose -Message "Successfully removed $dbName from  detach from $agName on $($server.Name)."
            } catch {
                Stop-Function -Message "Could not remove $dbName from $agName on $($server.Name)." -Target $dbName -ErrorRecord $_
                return $false
            }
        }

        Write-Message -Level Verbose -Message "Attempting detach from $dbName from $source."

        ####### Using Sql to detach does not modify the $currentdb collection #######

        $server.KillAllProcesses($dbName)

        try {
            $sql = "ALTER DATABASE [$dbName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE"
            Write-Message -Level Verbose -Message $sql
            $null = $server.Query($sql)
            Write-Message -Level Verbose -Message "Successfully set $dbName to single-user from $source."
        } catch {
            Stop-Function -Message "Issue setting database to single-user." -Target $dbName -ErrorRecord $_
        }

        try {
            $sql = "EXEC master.dbo.sp_detach_db N'$dbName'"
            Write-Message -Level Verbose -Message $sql
            $null = $server.Query($sql)
            Write-Message -Level Verbose -Message "Successfully detached $dbName from $source."
            return $true
        } catch {
            Stop-Function -Message "Issue detaching database." -Target $dbName -ErrorRecord $_
            return $false
        }
    }

    function Mount-SqlDatabase {
        [CmdletBinding()]
        param (
            [object]$server,
            [string]$dbName,
            [object]$fileStructure,
            [string]$dbOwner
        )

        if ($null -eq $server.Logins.Item($dbOwner)) {
            try {
                $dbOwner = ($destServer.logins | Where-Object {
                        $_.id -eq 1
                    }).Name
            } catch {
                $dbOwner = "sa"
            }
        }
        try {
            $null = $server.AttachDatabase($dbName, $fileStructure, $dbOwner, [Microsoft.SqlServer.Management.Smo.AttachOptions]::None)
            return $true
        } catch {
            Stop-Function -Message "Issue mounting database." -ErrorRecord $_
            return $false
        }
    }

    function Start-SqlFileTransfer {
        <#

            SYNOPSIS
            Internal function. Uses BITS to transfer detached files (.mdf, .ndf, .ldf, and filegroups) to
            another server over admin UNC paths. Locations of data files are kept in the
            custom object generated by Get-SqlFileStructure

            #>
        [CmdletBinding(SupportsShouldProcess)]
        param (
            [object]$fileStructure,
            [string]$dbName
        )
        $filestructure
        $copydb = $fileStructure.databases[$dbName]
        $dbsource = $copydb.source
        $dbdestination = $copydb.destination

        foreach ($file in $dbsource.keys) {
            if ($Pscmdlet.ShouldProcess($file, "Starting Sql File Transfer")) {
                $remotefilename = $dbdestination[$file].remotefilename
                $from = $dbsource[$file].remotefilename
                try {
                    if (Test-Path $from -PathType container) {
                        $null = New-Item -ItemType Directory -Path $remotefilename -Force
                        Start-BitsTransfer -Source "$from\*.*" -Destination $remotefilename -ErrorAction Stop

                        $directories = (Get-ChildItem -Recurse $from | Where-Object {
                                $_.PsIsContainer
                            }).FullName
                        foreach ($directory in $directories) {
                            $newdirectory = $directory.replace($from, $remotefilename)
                            $null = New-Item -ItemType Directory -Path $newdirectory -Force
                            Start-BitsTransfer -Source "$directory\*.*" -Destination $newdirectory -ErrorAction Stop
                        }
                    } else {
                        Write-Message -Level Verbose -Message "Copying $from for $dbName."
                        Start-BitsTransfer -Source $from -Destination $remotefilename -ErrorAction Stop
                    }
                } catch {
                    try {
                        # Sometimes BITS trips out temporarily on cloned drives.
                        Start-BitsTransfer -Source $from -Destination $remotefilename -ErrorAction Stop
                    } catch {
                        Write-Message -Level Verbose -Message "Start-BitsTransfer did not succeed. Now attempting with Copy-Item - no progress bar will be shown."
                        try {
                            Copy-Item -Path $from -Destination $remotefilename -ErrorAction Stop
                            $remotefilename
                        } catch {
                            Write-Message -Level Verbose -Message "Access denied. This can happen for a number of reasons including issues with cloned disks."
                            Stop-Function -Message "Alternatively, you may need to run PowerShell as Administrator, especially when running on localhost." -Target $from -ErrorRecord $_
                            return
                        }
                    }
                }
            }
        }
        return $true
    }

    function Start-SqlDetachAttach {
        <#

                .SYNOPSIS
                Internal function. Performs checks, then executes Dismount-SqlDatabase on a database, copies its files to the new server, then performs Mount-SqlDatabase. $sourceServer and $destServer are SMO server objects.

                $fileStructure is a custom object generated by Get-SqlFileStructure

                #>
        [CmdletBinding(SupportsShouldProcess)]
        param (
            [object]$sourceServer,
            [object]$destServer,
            [object]$fileStructure,
            [string]$dbName
        )
        if ($Pscmdlet.ShouldProcess($dbName, "Starting detaching and re-attaching from $sourceServer to $destServer")) {
            $destfilestructure = New-Object System.Collections.Specialized.StringCollection
            $sourceFileStructure = New-Object System.Collections.Specialized.StringCollection
            $dbOwner = $sourceServer.databases[$dbName].owner
            $destDbName = $fileStructure.databases[$dbName].destinationDbName

            if ($null -eq $dbOwner) {
                try {
                    $dbOwner = ($destServer.logins | Where-Object {
                            $_.id -eq 1
                        }).Name
                } catch {
                    $dbOwner = "sa"
                }
            }

            foreach ($file in $fileStructure.databases[$dbName].destination.values) {
                $null = $destfilestructure.add($file.physical)
            }
            foreach ($file in $fileStructure.databases[$dbName].source.values) {
                $null = $sourceFileStructure.add($file.physical)
            }

            $detachresult = Dismount-SqlDatabase $sourceServer $dbName

            if ($detachresult) {

                $transfer = Start-SqlFileTransfer $fileStructure $dbName
                if ($transfer -eq $false) {
                    Write-Message -Level Verbose -Message "Could not copy files."
                    return "Could not copy files."
                }
                $attachresult = Mount-SqlDatabase $destServer $destDbName $destfilestructure $dbOwner

                if ($attachresult -eq $true) {
                    # add to added dbs because ATTACH was successful
                    Write-Message -Level Verbose -Message "Successfully attached $dbName to $destinstance."
                    return $true
                } else {
                    # add to failed because ATTACH was unsuccessful
                    Write-Message -Level Verbose -Message "Could not attach $dbName."
                    return "Could not attach database."
                }
            } else {
                # add to failed because DETACH was unsuccessful
                Write-Message -Level Verbose -Message "Could not detach $dbName."
                return "Could not detach database."
            }
        }
    }

    . {
        if (Test-FunctionInterrupt) {
                    return
                }
    
                # testing twice for whatif reasons
                if ($BackupRestore -and (-not $SharedPath -and -not $UseLastBackup)) {
                    Stop-Function -Message "When using -BackupRestore, you must specify -SharedPath or -UseLastBackup" -FunctionName Copy-DbaDatabase
                    return
                }
                if ($SharedPath -and $UseLastBackup) {
                    Stop-Function -Message "-SharedPath cannot be used with -UseLastBackup because the backup path is determined by the paths in the last backups" -FunctionName Copy-DbaDatabase
                    return
                }
                if ($DetachAttach -and -not $Reattach -and $Destination.Count -gt 1) {
                    Stop-Function -Message "When using -DetachAttach with multiple servers, you must specify -Reattach to reattach database at source" -FunctionName Copy-DbaDatabase
                    return
                }
                if (($AllDatabases -or $IncludeSupportDbs -or $Database) -and !$DetachAttach -and !$BackupRestore) {
                    Stop-Function -Message "You must specify -DetachAttach or -BackupRestore when migrating databases." -FunctionName Copy-DbaDatabase
                    return
                }
    
                if (-not $AllDatabases -and -not $IncludeSupportDbs -and -not $Database -and -not $InputObject) {
                    Stop-Function -Message "You must specify a -AllDatabases or -Database to continue." -FunctionName Copy-DbaDatabase
                    return
                }
    
                if (($__boundNewName) -and ($__boundPrefix)) {
                    Stop-Function -Message "NewName and Prefix are exclusive options, cannot specify both" -FunctionName Copy-DbaDatabase
                    return
                }
    
                if ($InputObject) {
                    $Source = $InputObject[0].Parent
                    $Database = $InputObject.Name
                }
    
                if ($Database -contains "master" -or $Database -contains "msdb" -or $Database -contains "tempdb") {
                    Stop-Function -Message "Migrating system databases is not currently supported." -Continue -FunctionName Copy-DbaDatabase
                }
    
                try {
                    $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source -FunctionName Copy-DbaDatabase
                    return
                }
    
                if ($SharedPath -like 'https*') {
                    if ($AzureCredential -eq '') {
                        $tAzureCredential = $SharedPath
                    } else {
                        $tAzureCredential = $AzureCredential
                    }
                    if (-not (Get-DbaCredential -SqlInstance $sourceServer -Name $tAzureCredential.trim('/'))) {
                        Stop-Function -Message "Azure storage path passed in, but no matching credential found" -Category InvalidArgument -Target $sourceServer -FunctionName Copy-DbaDatabase
                        return
                    }
                }
    
                # Fix #6600
                $sourceFullComputerName = Resolve-DbaComputerName -ComputerName $sourceServer.ComputerName
                Write-Message -Level Verbose -Message "Using $sourceFullComputerName as sourceFullComputerName." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
    
                Write-Message -Level Verbose -Message "Ensuring user databases exist (counting databases)." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
    
                if ($sourceserver.Databases.IsSystemObject -notcontains $false) {
                    Stop-Function -Message "No user databases to migrate" -FunctionName Copy-DbaDatabase
                    return
                }
    
                foreach ($destinstance in $Destination) {
                    try {
                        $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
                    } catch {
                        Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue -FunctionName Copy-DbaDatabase
                    }
    
                    if ($sourceServer.ComputerName -eq $destServer.ComputerName) {
                        $script:sameserver = $true
                    } else {
                        $script:sameserver = $false
                    }
                    if ($SharedPath -like 'https*') {
                        if ($AzureCredential -eq '') {
                            $tAzureCredential = $SharedPath
                        } else {
                            $tAzureCredential = $AzureCredential
                        }
                        if (-not (Get-DbaCredential -SqlInstance $destServer -Name $tAzureCredential.trim('/'))) {
                            Stop-Function -Message "Azure storage path passed in, but no matching credential found" -Category InvalidArgument -Target $destServer -Continue -FunctionName Copy-DbaDatabase
                        }
                    }
                    if ($script:sameserver -and $DetachAttach) {
                        if (-not (Test-ElevationRequirement -ComputerName $sourceServer)) {
                            return
                        }
                    }
    
                    $destVersionLower = $destServer.VersionMajor -lt $sourceServer.VersionMajor
                    $destVersionMinorLow = ($destServer.VersionMajor -eq 10 -and $sourceServer.VersionMajor -eq 10) -and ($destServer.VersionMinor -lt $sourceServer.VersionMinor)
    
                    if ($destVersionLower -or $destVersionMinorLow) {
                        Stop-Function -Message "Error: copy database cannot be made from newer $($sourceServer.VersionString) to older $($destServer.VersionString) SQL Server version." -FunctionName Copy-DbaDatabase
                        return
                    }
                    $miRestore = $false
                    if ($destServer.DatabaseEngineEdition -eq 'SqlManagedInstance') {
                        # we have a managed instance destination, set an internal flag to disable switches that don't work
                        $miRestore = $True
                    }
                    if ($DetachAttach) {
                        if ($sourceServer.ComputerName -eq $env:COMPUTERNAME -or $destServer.ComputerName -eq $env:COMPUTERNAME) {
                            if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
                                Write-Message -Level Verbose -Message "When running DetachAttach locally on the console, it's possible you'll need to Run As Administrator. Trying anyway." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                            }
                        }
                    }
    
                    if ($SharedPath -and $SharedPath -notlike 'https*') {
                        if ($(Test-DbaPath -SqlInstance $sourceServer -Path $SharedPath) -eq $false) {
                            Write-Message -Level Verbose -Message "$Source may not be able to access $SharedPath. Trying anyway." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                        }
    
                        if ($(Test-DbaPath -SqlInstance $destServer -Path $SharedPath) -eq $false) {
                            Write-Message -Level Verbose -Message "$destinstance may not be able to access $SharedPath. Trying anyway." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                        }
    
                        if ($SharedPath.StartsWith('\\')) {
                            try {
                                $shareServer = ($SharedPath -split "\\")[2]
                                $hostEntry = ([Net.Dns]::GetHostEntry($shareServer)).HostName -split "\."
    
                                if ($shareServer -ne $hostEntry[0]) {
                                    Write-Message -Level Verbose -Message "Using CNAME records for the network share may present an issue if an SPN has not been created. Trying anyway. If it doesn't work, use a different (A record) hostname." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                                }
                            } catch {
                                Stop-Function -Message "Error validating unc path: $_" -FunctionName Copy-DbaDatabase
                                return
                            }
                        }
                    }
    
                    # Fix #6600
                    $destFullComputerName = Resolve-DbaComputerName -ComputerName $destserver.ComputerName
                    Write-Message -Level Verbose -Message "Using $destFullComputerName as destFullComputerName." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
    
                    Write-Message -Level Verbose -Message "Checking to ensure the source isn't the same as the destination." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                    if ($source -eq $destinstance) {
                        Stop-Function -Message "Source and Destination SQL Servers instances are the same. Quitting." -Continue -FunctionName Copy-DbaDatabase
                    }
    
                    Write-Message -Level Verbose -Message "Checking to ensure server is not SQL Server 7 or below." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                    if ($sourceServer.VersionMajor -lt 8 -or $destServer.VersionMajor -lt 8) {
                        Stop-Function -Message "This script can only be run on SQL Server 2000 and above. Quitting." -Continue -FunctionName Copy-DbaDatabase
                    }
    
                    Write-Message -Level Verbose -Message "Checking to ensure detach/attach is not attempted on SQL Server 2000." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                    if ($destServer.VersionMajor -lt 9 -and $DetachAttach) {
                        Stop-Function -Message "Detach/Attach not supported when destination SQL Server is version 2000. Quitting." -Target $destServer -Continue -FunctionName Copy-DbaDatabase
                    }
    
                    Write-Message -Level Verbose -Message "Checking to ensure SQL Server 2000 migration isn't directly attempted to SQL Server 2012." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                    if ($sourceServer.VersionMajor -lt 9 -and $destServer.VersionMajor -gt 10) {
                        Stop-Function -Message "SQL Server 2000 databases cannot be migrated to SQL Server versions 2012 and above. Quitting." -Target $destServer -Continue -FunctionName Copy-DbaDatabase
                    }
    
                    Write-Message -Level Verbose -Message "Warning if migration from 2005 to 2012 and above and attach/detach is used." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                    if ($sourceServer.VersionMajor -eq 9 -and $destServer.VersionMajor -gt 9 -and !$BackupRestore -and !$Force -and $DetachAttach) {
                        Stop-Function -Message "Backup and restore is the safest method for migrating from SQL Server 2005 to other SQL Server versions. Please use the -BackupRestore switch or override this requirement by specifying -Force." -Continue -FunctionName Copy-DbaDatabase
                    }
    
                    if ($sourceServer.Collation -ne $destServer.Collation) {
                        Write-Message -Level Verbose -Message "Warning on different collation." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                        Write-Message -Level Verbose -Message "Collation on $Source, $($sourceServer.Collation) differs from the $destinstance, $($destServer.Collation)." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                    }
    
                    Write-Message -Level Verbose -Message "Ensuring destination server version is equal to or greater than source." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                    if ($sourceServer.VersionMajor -ge $destServer.VersionMajor) {
                        if ($sourceServer.VersionMinor -gt $destServer.VersionMinor) {
                            Stop-Function -Message "Source SQL Server version build must be <= destination SQL Server for database migration." -Continue -FunctionName Copy-DbaDatabase
                        }
                    }
    
                    # SMO's filestreamlevel is sometimes null
                    $sql = "SELECT COALESCE(SERVERPROPERTY('FilestreamConfiguredLevel'),0) AS fs"
                    $sourceFilestream = $sourceServer.ConnectionContext.ExecuteScalar($sql)
                    $destFilestream = $destServer.ConnectionContext.ExecuteScalar($sql)
                    if ($sourceFilestream -gt 0 -and $destFilestream -eq 0) {
                        $fsWarning = $true
                    }
    
                    Write-Message -Level Verbose -Message "Writing warning about filestream being enabled." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                    if ($fsWarning) {
                        Write-Message -Level Verbose -Message "FILESTREAM enabled on $source but not $destinstance. Databases that use FILESTREAM will be skipped." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                    }
    
                    if ($DetachAttach -eq $true) {
                        Write-Message -Level Verbose -Message "Checking access to remote directories." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                        $remoteSourcePath = Join-AdminUNC $sourceFullComputerName (Get-SqlDefaultPaths -SqlInstance $sourceServer -filetype data)
    
                        if ((Test-Path $remoteSourcePath) -ne $true -and $DetachAttach) {
                            Write-Message -Level Warning -Message "Can't access remote Sql directories on $source which is required to perform detach/copy/attach." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                            Write-Message -Level Warning -Message "You can manually try accessing $remoteSourcePath to diagnose any issues." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                            Stop-Function -Message "Halting database migration" -FunctionName Copy-DbaDatabase
                            return
                        }
    
                        $remoteDestPath = Join-AdminUNC $destFullComputerName (Get-SqlDefaultPaths -SqlInstance $destServer -filetype data)
                        If ((Test-Path $remoteDestPath) -ne $true -and $DetachAttach) {
                            Write-Message -Level Warning -Message "Can't access remote Sql directories on $destinstance which is required to perform detach/copy/attach." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                            Write-Message -Level Warning -Message "You can manually try accessing $remoteDestPath to diagnose any issues." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                            Stop-Function -Message "Halting database migration" -Continue -FunctionName Copy-DbaDatabase
                        }
                    }
    
                    if (($Database -or $ExcludeDatabase -or $IncludeSupportDbs) -and (!$DetachAttach -and !$BackupRestore)) {
                        Stop-Function -Message "You did not select a migration method. Please use -BackupRestore or -DetachAttach." -FunctionName Copy-DbaDatabase
                        return
                    }
    
                    if ((!$Database -and !$AllDatabases -and !$IncludeSupportDbs) -and ($DetachAttach -or $BackupRestore)) {
                        Stop-Function -Message "You did not select any databases to migrate. Please use -AllDatabases or -Database or -IncludeSupportDbs." -FunctionName Copy-DbaDatabase
                        return
                    }
    
                    Write-Message -Level Verbose -Message "Building database list." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                    $databaseList = New-Object System.Collections.ArrayList
                    $SupportDBs = "ReportServer", "ReportServerTempDB", "distribution", "SSISDB"
    
                    # Only filter by IsAccessible if operations require source database accessibility
                    $requiresAccessible = $SetSourceReadOnly -or $SetSourceOffline
                    if ($requiresAccessible) {
                        $sourceDatabases = $sourceServer.Databases | Where-Object IsAccessible
                    } else {
                        $sourceDatabases = $sourceServer.Databases
                    }
    
                    foreach ($currentdb in $sourceDatabases) {
                        $dbName = $currentdb.Name
                        $dbOwner = $currentdb.Owner
    
                        if ($currentdb.Id -le 4) {
                            continue
                        }
                        if ($Database -and $Database -notcontains $dbName) {
                            continue
                        }
                        if ($IncludeSupportDBs -eq $false -and $SupportDBs -contains $dbName) {
                            continue
                        }
                        if ($IncludeSupportDBs -eq $true -and $SupportDBs -notcontains $dbName) {
                            if ($AllDatabases -eq $false -and $Database.length -eq 0) {
                                continue
                            }
                        }
                        $null = $databaseList.Add($currentdb)
                    }
    
                    Write-Message -Level Verbose -Message "Performing count." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                    $dbCount = $databaseList.Count
    
                    if (($__boundNewName) -and $dbCount -gt 1) {
                        Stop-Function -Message "Cannot use NewName when copying multiple databases" -FunctionName Copy-DbaDatabase
                        return
                    }
    
    
                    Write-Message -Level Verbose -Message "Building file structure inventory for $dbCount databases." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
    
                    if ($sourceServer.VersionMajor -eq 8) {
                        $sql = "SELECT DB_NAME (dbid) AS dbname, name, filename, CASE WHEN groupid = 0 THEN 'LOG' ELSE 'ROWS' END AS filetype FROM sysaltfiles"
                    } else {
                        $sql = "SELECT db.Name AS dbname, type_desc AS FileType, mf.Name, Physical_Name AS filename FROM sys.master_files mf INNER JOIN sys.databases db ON db.database_id = mf.database_id"
                    }
    
                    $dbFileTable = $sourceServer.Databases['master'].ExecuteWithResults($sql)
    
                    if ($destServer.VersionMajor -eq 8) {
                        $sql = "SELECT DB_NAME (dbid) AS dbname, name, filename, CASE WHEN groupid = 0 THEN 'LOG' ELSE 'ROWS' END AS filetype FROM sysaltfiles"
                    } else {
                        $sql = "SELECT db.Name AS dbname, type_desc AS FileType, mf.Name, Physical_Name AS filename FROM sys.master_files mf INNER JOIN sys.databases db ON db.database_id = mf.database_id"
                    }
    
                    $remoteDbFileTable = $destServer.Databases['master'].ExecuteWithResults($sql)
    
                    $fileStructure = Get-SqlFileStructure -sourceserver $sourceServer -destserver $destServer -databaselist $databaseList -ReuseSourceFolderStructure $ReuseSourceFolderStructure
    
                    $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
                    $started = Get-Date
                    $script:TimeNow = (Get-Date -UFormat "%m%d%Y%H%M%S")
    
                    if ($AllDatabases -or $ExcludeDatabase -or $IncludeSupportDbs -or $Database) {
                        foreach ($currentdb in $databaseList) {
                            $dbName = $currentdb.Name
                            $dbOwner = $currentdb.Owner
                            $destinationDbName = $dbName
                            if (($__boundNewName)) {
                                Write-Message -Level Verbose -Message "NewName specified, copying $dbName as $NewName" -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                                $destinationDbName = $NewName
                                $replaceInFile = $True
                            }
                            if ($($__boundPrefix)) {
                                $destinationDbName = $prefix + $destinationDbName
                                Write-Message -Level Verbose -Message "Prefix supplied, copying $dbName as $destinationDbName" -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                            }
    
                            $filestructure.databases[$dbName]['destinationDbName'] = $destinationDbName
                            ForEach ($key in $filestructure.databases[$dbName].Destination.Keys) {
                                $splitFileName = Split-Path $fileStructure.databases[$dbName].Destination[$key].remotefilename -Leaf
                                $SplitPath = Split-Path $fileStructure.databases[$dbName].Destination[$key].remotefilename
                                if ($replaceInFile) {
                                    $splitFileName = $splitFileName.replace($dbName, $destinationDbName)
                                }
                                $splitFileName = $prefix + $splitFileName
                                $filestructure.databases[$dbName].Destination.$key.remotefilename = Join-DbaPath -Path $SplitPath -ChildPath $splitFileName
                                $splitFileName = Split-Path $filestructure.databases[$dbName].Destination[$key].physical -Leaf
                                $SplitPath = Split-Path $fileStructure.databases[$dbName].Destination[$key].physical
                                if ($replaceInFile) {
                                    $splitFileName = $splitFileName.replace($dbName, $destinationDbName)
                                }
                                $splitFileName = $prefix + $splitFileName
                                $filestructure.databases[$dbName].Destination.$key.physical = Join-DbaPath -Path $SplitPath -ChildPath $splitFileName
                            }
    
                            $copyDatabaseStatus = [PSCustomObject]@{
                                SourceServer        = $sourceServer.Name
                                DestinationServer   = $destServer.Name
                                Name                = $dbName
                                DestinationDatabase = $destinationDbName
                                Type                = "Database"
                                Status              = $null
                                Notes               = $null
                                DateTime            = [DbaDateTime](Get-Date)
                            }
    
                            Write-Message -Level Verbose -Message "`n######### Database: $dbName #########" -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                            $dbStart = Get-Date
    
                            if ($ExcludeDatabase -contains $dbName) {
                                Write-Message -Level Verbose -Message "$dbName excluded. Skipping." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                                continue
                            }
    
                            Write-Message -Level Verbose -Message "Checking for accessibility." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                            if ($currentdb.IsAccessible -eq $false) {
                                # Check if inaccessible database is being used with operations that require accessibility
                                if ($SetSourceReadOnly -or $SetSourceOffline) {
                                    if ($__realCmdlet.ShouldProcess($destinstance, "Skipping $dbName. Database is inaccessible and -SetSourceReadOnly or -SetSourceOffline was specified.")) {
                                        Write-Message -Level Warning -Message "Skipping $dbName. Database is inaccessible and cannot be set to read-only or offline. Consider removing -SetSourceReadOnly and -SetSourceOffline parameters for AG secondary replicas." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
    
                                        $copyDatabaseStatus.Status = "Skipped"
                                        $copyDatabaseStatus.Notes = "Database is not accessible (required for SetSourceReadOnly or SetSourceOffline)"
                                        $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                    }
                                    continue
                                }
                                # For BackupRestore without SetSourceReadOnly/SetSourceOffline, inaccessible is OK
                                Write-Message -Level Verbose -Message "Database $dbName is not accessible but will attempt migration using backup history." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                            }
    
                            if ($fsWarning) {
                                $fsRows = $dbFileTable.Tables[0].Select("dbname = '$dbName' and FileType = 'FileStream'")
    
                                if ($fsRows.Count -gt 0) {
                                    if ($__realCmdlet.ShouldProcess($destinstance, "Skipping $dbName (contains FILESTREAM).")) {
                                        Write-Message -Level Verbose -Message "Skipping $dbName (contains FILESTREAM)." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                                        $copyDatabaseStatus.Status = "Skipped"
                                        $copyDatabaseStatus.Notes = "Contains FILESTREAM"
                                        $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                    }
                                    continue
                                }
                            }
    
                            if ($ReuseSourceFolderStructure) {
                                $fgRows = $dbFileTable.Tables[0].Select("dbname = '$dbName' and FileType = 'ROWS'")[0]
                                $remotePath = Split-Path $fgRows.Filename
    
                                if (!(Test-DbaPath -SqlInstance $destServer -Path $remotePath)) {
                                    if ($__realCmdlet.ShouldProcess($destinstance, "$remotePath does not exist on $destinstance and ReuseSourceFolderStructure was specified")) {
                                        # Stop-Function -Message "Cannot resolve $remotePath on $source. `n`nYou have specified ReuseSourceFolderStructure and exact folder structure does not exist. Halting script."
                                        $copyDatabaseStatus.Status = "Failed"
                                        $copyDatabaseStatus.Notes = "$remotePath does not exist on $destinstance and ReuseSourceFolderStructure was specified" #"Can't resolve $remotePath"
                                        $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                    }
                                    continue
                                }
                            }
    
                            Write-Message -Level Verbose -Message "Checking Availability Group status." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                            if ($currentdb.AvailabilityGroupName -and !$force -and $DetachAttach) {
                                $agName = $currentdb.AvailabilityGroupName
                                Write-Message -Level Verbose -Message "Database is part of an Availability Group ($agName). Use -Force to drop from $agName and migrate. Alternatively, you can use the safer backup/restore method." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                                continue
                            }
    
                            $dbStatus = $currentdb.Status.ToString()
    
                            if ($dbStatus.StartsWith("Normal") -eq $false) {
                                if ($__realCmdlet.ShouldProcess($destinstance, "$dbName is not in a Normal state. Skipping.")) {
                                    Write-Message -Level Verbose -Message "$dbName is not in a Normal state. Skipping." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
    
                                    $copyDatabaseStatus.Status = "Skipped"
                                    $copyDatabaseStatus.Notes = "Not in normal state"
                                    $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                }
                                continue
                            }
    
                            if ($currentdb.ReplicationOptions -ne "None" -and $DetachAttach -eq $true) {
                                if ($__realCmdlet.ShouldProcess($destinstance, "$dbName is part of replication. Skipping.")) {
                                    Write-Message -Level Verbose -Message "$dbName is part of replication. Skipping." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
    
                                    $copyDatabaseStatus.Status = "Skipped"
                                    $copyDatabaseStatus.Notes = "Part of replication"
                                    $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                }
                                continue
                            }
    
                            if ($currentdb.IsMirroringEnabled -and !$force -and $DetachAttach) {
                                if ($__realCmdlet.ShouldProcess($destinstance, "Database is being mirrored. Use -Force to break mirror and migrate. Alternatively, you can use the safer backup/restore method.")) {
                                    Write-Message -Level Verbose -Message "Database is being mirrored. Use -Force to break mirror and migrate. Alternatively, you can use the safer backup/restore method." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
    
                                    $copyDatabaseStatus.Status = "Skipped"
                                    $copyDatabaseStatus.Notes = "Database is mirrored"
                                    $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                }
    
                                continue
                            }
    
                            if (($null -ne $destServer.Databases[$destinationDbName]) -and !$force -and !$WithReplace -and !$Continue) {
                                if ($__realCmdlet.ShouldProcess($destinstance, "$destinationDbName exists at destination. Use -Force to drop and migrate. Aborting routine for this database.")) {
                                    Write-Message -Level Verbose -Message "$destinationDbName exists at destination. Use -Force to drop and migrate. Aborting routine for this database." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
    
                                    $copyDatabaseStatus.Status = "Skipped"
                                    $copyDatabaseStatus.Notes = "Already exists on destination"
                                    $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                }
                                continue
                            } elseif ($null -ne $destServer.Databases[$destinationDbName] -and $force) {
                                if ($sourceServer.Name -eq $destServer.Name -and $dbName -eq $destinationDbName) {
                                    Write-Message -Level Verbose -Message "Source and destination database are the same. Aborting routine for this database." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                                    $copyDatabaseStatus.Status = "Failed"
                                    $copyDatabaseStatus.Notes = "Source and destination database are the same."
                                    $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                    continue
                                }
                                if ($__realCmdlet.ShouldProcess($destinstance, "DROP DATABASE $destinationDbName")) {
                                    Write-Message -Level Verbose -Message "$destinationDbName already exists. -Force was specified. Dropping $destinationDbName on $destinstance." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                                    $removeresult = Remove-DbaDatabase -SqlInstance $destserver -Database $destinationDbName -Confirm:$false
                                    $dropResult = $removeresult.Status -eq 'Dropped'
    
                                    if ($dropResult -eq $false) {
                                        Write-Message -Level Verbose -Message "Database could not be dropped. Aborting routine for this database." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
    
                                        $copyDatabaseStatus.Status = "Failed"
                                        $copyDatabaseStatus.Notes = "Could not drop database"
                                        $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                        continue
                                    }
                                }
                            }
    
                            if ($force) {
                                $WithReplace = $true
                            }
    
                            Write-Message -Level Verbose -Message "Started: $dbStart." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
    
                            if ($sourceServer.VersionMajor -ge 9) {
                                $sourceDbOwnerChaining = $sourceServer.Databases[$dbName].DatabaseOwnershipChaining
                                $sourceDbTrustworthy = $sourceServer.Databases[$dbName].Trustworthy
                                $sourceDbBrokerEnabled = $sourceServer.Databases[$dbName].BrokerEnabled
                            }
    
                            $sourceDbReadOnly = $sourceServer.Databases[$dbName].ReadOnly
                            $sourceDbOffline = $sourceServer.Databases[$dbName].Status -like "*Offline*"
    
                            if ($SetSourceReadOnly) {
                                If ($__realCmdlet.ShouldProcess($source, "Set $dbName to read-only")) {
                                    Write-Message -Level Verbose -Message "Setting database to read-only." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                                    try {
                                        $result = Set-DbaDbState -SqlInstance $sourceServer -Database $dbName -ReadOnly -EnableException -Force
                                    } catch {
                                        Stop-Function -Continue -Message "Couldn't set database to read-only. Aborting routine for this database" -ErrorRecord $_ -FunctionName Copy-DbaDatabase
                                    }
                                }
                            }
    
                            if ($SetSourceOffline -and $DetachAttach) {
                                # For DetachAttach, set offline before detach to kill connections
                                If ($__realCmdlet.ShouldProcess($source, "Set $dbName to offline")) {
                                    Write-Message -Level Verbose -Message "Setting database to offline." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                                    try {
                                        $result = Set-DbaDbState -SqlInstance $sourceServer -Database $dbName -Offline -EnableException -Force
                                    } catch {
                                        Stop-Function -Continue -Message "Couldn't set database to offline. Aborting routine for this database" -ErrorRecord $_ -FunctionName Copy-DbaDatabase
                                    }
                                }
                            }
    
                            if ($BackupRestore) {
                                if ($UseLastBackup) {
                                    $whatifmsg = "Gathering last backup information for $dbName from $Source and restoring"
                                } else {
                                    $whatifmsg = "Backup $dbName from $source and restoring"
                                }
                                If ($__realCmdlet.ShouldProcess($destinstance, $whatifmsg)) {
                                    if ($UseLastBackup) {
                                        if ($Continue) {
                                            $backupTmpResult = Get-DbaDbBackupHistory -SqlInstance $sourceServer -Database $dbName -IncludeCopyOnly -Last -IgnoreDiffBackup
                                        } else {
                                            $backupTmpResult = Get-DbaDbBackupHistory -SqlInstance $sourceServer -Database $dbName -IncludeCopyOnly -Last
                                        }
                                        if (-not $backupTmpResult) {
                                            $copyDatabaseStatus.Type = "Database (BackupRestore)"
                                            $copyDatabaseStatus.Status = "Failed"
                                            $copyDatabaseStatus.Notes = "No backups for $dbName on $source"
                                            $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                            continue
                                        }
                                    } else {
                                        $backupTmpResult = $backupCollection | Where-Object Database -eq $dbName
                                        if (-not $backupTmpResult) {
                                            if ($SharedPath -like 'https*') {
                                                if ($AdvancedBackupParams) {
                                                    $backupTmpResult = Backup-DbaDatabase -SqlInstance $sourceServer -Database $dbName -AzureBaseUrl $SharedPath -FileCount $numberfiles -CopyOnly:$CopyOnly -AzureCredential $AzureCredential @AdvancedBackupParams
                                                } else {
                                                    $backupTmpResult = Backup-DbaDatabase -SqlInstance $sourceServer -Database $dbName -AzureBaseUrl $SharedPath -FileCount $numberfiles -CopyOnly:$CopyOnly -AzureCredential $AzureCredential
                                                }
    
                                            } else {
                                                $splatBackup = @{
                                                    SqlInstance      = $sourceServer
                                                    Database         = $dbName
                                                    BackupDirectory  = $SharedPath
                                                    FileCount        = $numberfiles
                                                    CopyOnly         = $CopyOnly
                                                    IgnoreFileChecks = $true
                                                }
                                                if ($AdvancedBackupParams) {
                                                    $backupTmpResult = Backup-DbaDatabase @splatBackup @AdvancedBackupParams
                                                } else {
                                                    $backupTmpResult = Backup-DbaDatabase @splatBackup
                                                }
                                            }
    
                                            if ((-not $backupTmpResult) -or (-not $backupTmpResult.BackupComplete)) {
                                                $serviceAccount = $sourceServer.ServiceAccount
                                                Write-Message -Level Verbose -Message "Backup Failed. Does SQL Server account $serviceAccount have access to $($SharedPath)? Aborting routine for this database." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
    
                                                $copyDatabaseStatus.Status = "Failed"
                                                $copyDatabaseStatus.Notes = "Backup failed. Verify service account access to $SharedPath."
                                                $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                                continue
                                            }
    
                                            $backupCollection += $backupTmpResult
                                        }
                                    }
    
                                    # For BackupRestore, set source offline after backup completes but before restore
                                    if ($SetSourceOffline) {
                                        Write-Message -Level Verbose -Message "Setting source database $dbName to offline after backup." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                                        try {
                                            $null = Set-DbaDbState -SqlInstance $sourceServer -Database $dbName -Offline -EnableException -Force
                                        } catch {
                                            Stop-Function -Continue -Message "Couldn't set database to offline after backup. Aborting routine for this database" -ErrorRecord $_ -FunctionName Copy-DbaDatabase
                                        }
                                    }
    
                                    Write-Message -Level Verbose -Message "Reuse = $ReuseSourceFolderStructure." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                                    try {
                                        $msg = $null
                                        $restoreResultTmp = $null  # Reset so a failed restore doesn't inherit the previous iteration's result
                                        if ($miRestore) {
                                            $restoreResultTmp = $backupTmpResult | Restore-DbaDatabase -SqlInstance $destServer -DatabaseName $destinationDbName -TrustDbBackupHistory -WithReplace:$WithReplace -EnableException -AzureCredential $AzureCredential
                                        } else {
                                            $restoreResultTmp = $backupTmpResult | Restore-DbaDatabase -SqlInstance $destServer -DatabaseName $destinationDbName -ReuseSourceFolderStructure:$ReuseSourceFolderStructure -NoRecovery:$NoRecovery -TrustDbBackupHistory -WithReplace:$WithReplace -Continue:$Continue -EnableException -ReplaceDbNameInFile -AzureCredential $AzureCredential -KeepCDC:$KeepCDC -KeepReplication:$KeepReplication
                                        }
                                    } catch {
                                        $msg = $_.Exception.InnerException.InnerException.InnerException.InnerException.Message
                                        Stop-Function -Message "Failure attempting to restore $dbName to $destinstance" -Exception $_.Exception.InnerException.InnerException.InnerException.InnerException -FunctionName Copy-DbaDatabase
                                    }
                                    $restoreResult = $restoreResultTmp.RestoreComplete
    
                                    if ($restoreResult -eq $true) {
                                        Write-Message -Level Verbose -Message "Successfully restored $dbName to $destinstance." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                                        $copyDatabaseStatus.Status = "Successful"
                                    } else {
                                        if ($ReuseSourceFolderStructure) {
                                            Write-Message -Level Verbose -Message "Failed to restore $dbName to $destinstance. You specified -ReuseSourceFolderStructure. Does the exact same destination directory structure exist?" -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                                            Write-Message -Level Verbose -Message "Aborting routine for this database." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
    
                                            $copyDatabaseStatus.Status = "Failed"
                                            $copyDatabaseStatus.Notes = "Failed to restore. ReuseSourceFolderStructure was specified, verify same directory structure exist on destination."
                                            $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                            continue
                                        } else {
                                            Write-Message -Level Verbose -Message "Failed to restore $dbName to $destinstance. Aborting routine for this database." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
    
                                            $copyDatabaseStatus.Status = "Failed"
                                            if (-not $msg) {
                                                $msg = "Failed to restore database"
                                            }
                                            $copyDatabaseStatus.Notes = $msg
                                            $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                            continue
                                        }
                                    }
                                    if (-not $NoBackupCleanUp -and $Destination.Count -eq 1) {
                                        foreach ($backupFile in ($backupTmpResult.BackupPath)) {
                                            try {
                                                Write-Message -Level Verbose -Message "Deleting $backupFile." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                                                Remove-Item $backupFile -ErrorAction Stop
                                            } catch {
                                                try {
                                                    Write-Message -Level Verbose -Message "Trying alternate SQL method to delete $backupFile." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                                                    $sql = "EXEC master.sys.xp_delete_file 0, '$backupFile'"
                                                    Write-Message -Level Debug -Message $sql -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                                                    $null = $sourceServer.Query($sql)
                                                } catch {
                                                    Write-Message -Level Verbose -Message "Cannot delete backup file $backupFile." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
    
                                                    # Set NoBackupCleanup so that there's a warning at the end
                                                    $NoBackupCleanup = $true
                                                }
                                            }
                                        }
                                    }
                                }
    
                                if ($SetSourceReadOnly) {
                                    If ($__realCmdlet.ShouldProcess($destServer.Name, "Set $destinationDbName to read-write after source was set to read only")) {
                                        try {
                                            $null = Set-DbaDbState -SqlInstance $destServer -Database $destinationDbName -ReadWrite -EnableException -Force
                                        } catch {
                                            Stop-Function -Message "Couldn't set $destinationDbName to read-write on $($destserver.Name)" -ErrorRecord $_ -FunctionName Copy-DbaDatabase
                                        }
                                    }
                                }
    
                                if ($SetSourceOffline) {
                                    If ($__realCmdlet.ShouldProcess($destServer.Name, "Set $destinationDbName to online after source was set to offline")) {
                                        try {
                                            $null = Set-DbaDbState -SqlInstance $destServer -Database $destinationDbName -Online -EnableException -Force
                                        } catch {
                                            Stop-Function -Message "Couldn't set $destinationDbName to online on $($destserver.Name)" -ErrorRecord $_ -FunctionName Copy-DbaDatabase
                                        }
                                    }
                                }
    
                                $dbFinish = Get-Date
                                if ($NoRecovery -eq $false) {
                                    If ($__realCmdlet.ShouldProcess($destServer.Name, "Setting db owner to $dbowner for $destinationDbName")) {
                                        # needed because the newly restored database doesn't show up
                                        $destServer.Databases.Refresh()
                                        $dbOwner = $sourceServer.Databases[$dbName].Owner
                                        if ($null -eq $dbOwner -or $destServer.Logins.Name -notcontains $dbOwner) {
                                            $dbOwner = Get-SaLoginName -SqlInstance $destServer
                                        }
                                        try {
                                            $null = Set-DbaDbOwner -SqlInstance $destServer -Database $destinationDbName -TargetLogin $dbOwner -EnableException
                                        } catch {
                                            Stop-Function -Message "Failure setting database owner to $dbOwner for $destinationDbName on destination server" -ErrorRecord $_ -FunctionName Copy-DbaDatabase
                                        }
                                    }
                                }
                            }
    
                            if ($DetachAttach) {
    
                                $copyDatabaseStatus.Type = "Database (DetachAttach)"
    
                                $sourceFileStructure = New-Object System.Collections.Specialized.StringCollection
                                foreach ($file in $fileStructure.Databases[$dbName].Source.Values) {
                                    $null = $sourceFileStructure.Add($file.Physical)
                                }
    
                                $dbOwner = $sourceServer.Databases[$dbName].Owner
    
                                if ($null -eq $dbOwner -or $destServer.Logins.Name -notcontains $dbOwner) {
                                    $dbOwner = Get-SaLoginName -SqlInstance $destServer
                                }
    
                                if ($__realCmdlet.ShouldProcess($destinstance, "Detach $dbName from $source and attach, then update dbowner")) {
                                    $migrationResult = Start-SqlDetachAttach $sourceServer $destServer $fileStructure $dbName
    
                                    $dbFinish = Get-Date
    
                                    if ($reattach -eq $true) {
                                        $sourceServer.Databases.Refresh()
                                        $destServer.Databases.Refresh()
                                        $result = Mount-SqlDatabase $sourceServer $dbName $sourceFileStructure $dbOwner
    
                                        if ($result -eq $true) {
                                            $sourceServer.Databases[$dbName].DatabaseOwnershipChaining = $sourceDbOwnerChaining
                                            $sourceServer.Databases[$dbName].Trustworthy = $sourceDbTrustworthy
                                            $sourceServer.Databases[$dbName].BrokerEnabled = $sourceDbBrokerEnabled
                                            $sourceServer.Databases[$dbName].Alter()
    
                                            if ($SetSourceReadOnly -or $sourceDbReadOnly) {
                                                try {
                                                    $result = Set-DbaDbState -SqlInstance $sourceServer -Database $dbName -ReadOnly -EnableException
                                                } catch {
                                                    Stop-Function -Message "Couldn't set database to read-only" -ErrorRecord $_ -FunctionName Copy-DbaDatabase
                                                }
                                            }
    
                                            if ($SetSourceOffline -or $sourceDbOffline) {
                                                try {
                                                    $result = Set-DbaDbState -SqlInstance $sourceServer -Database $dbName -Offline -EnableException -Force
                                                } catch {
                                                    Stop-Function -Message "Couldn't set database to offline" -ErrorRecord $_ -FunctionName Copy-DbaDatabase
                                                }
                                            }
                                            Write-Message -Level Verbose -Message "Successfully reattached $dbName to $source." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                                        } else {
                                            Write-Message -Level Verbose -Message "Could not reattach $dbName to $source." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                                            $copyDatabaseStatus.Status = "Failed"
                                            $copyDatabaseStatus.Notes = "Could not reattach database to $source"
                                            $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                        }
                                    }
    
                                    if ($migrationResult -eq $true) {
                                        Write-Message -Level Verbose -Message "Successfully attached $dbName to $destinstance." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                                        $copyDatabaseStatus.Status = "Successful"
                                    } else {
                                        Write-Message -Level Verbose -Message "Failed to attach $dbName to $destinstance. Aborting routine for this database." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
    
                                        $copyDatabaseStatus.Status = "Failed"
                                        $copyDatabaseStatus.Notes = "Failed to attach database to destination"
                                        $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
    
                                        continue
                                    }
                                }
                            }
                            $NewDatabase = Get-DbaDatabase -SqlInstance $destServer -database $destinationDbName
    
                            $propfailures = @()
    
                            # restore potentially lost settings
                            if ($destServer.VersionMajor -ge 9 -and $NoRecovery -eq $false) {
                                if ($sourceDbOwnerChaining -ne $NewDatabase.DatabaseOwnershipChaining) {
                                    if ($__realCmdlet.ShouldProcess($destinstance, "Updating DatabaseOwnershipChaining on $destinationDbName")) {
                                        try {
                                            $NewDatabase.DatabaseOwnershipChaining = $sourceDbOwnerChaining
                                            $NewDatabase.Alter()
                                            Write-Message -Level Verbose -Message "Successfully updated DatabaseOwnershipChaining for $sourceDbOwnerChaining on $destinationDbName on $destinstance." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                                        } catch {
                                            Write-Message -Level Warning -Message "Failed to update DatabaseOwnershipChaining for $sourceDbOwnerChaining on $destinationDbName on $destinstance." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                                            $propfailures += "Ownership chaining"
                                        }
                                    }
                                }
    
                                if ($sourceDbTrustworthy -ne $NewDatabase.Trustworthy) {
                                    if ($__realCmdlet.ShouldProcess($destinstance, "Updating Trustworthy on $destinationDbName")) {
                                        try {
                                            $NewDatabase.Trustworthy = $sourceDbTrustworthy
                                            $NewDatabase.Alter()
                                            Write-Message -Level Verbose -Message "Successfully updated Trustworthy to $sourceDbTrustworthy for $destinationDbName on $destinstance" -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                                        } catch {
                                            Write-Message -Level Warning -Message "Failed to update Trustworthy to $sourceDbTrustworthy for $destinationDbName on $destinstance." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                                            $propfailures += "Trustworthy"
                                        }
                                    }
                                }
    
                                if ($sourceDbBrokerEnabled -ne $NewDatabase.BrokerEnabled) {
                                    if ($__realCmdlet.ShouldProcess($destinstance, "Updating BrokerEnabled on $destinationDbName")) {
                                        try {
                                            $NewDatabase.BrokerEnabled = $sourceDbBrokerEnabled
                                            $NewDatabase.Alter()
                                            Write-Message -Level Verbose -Message "Successfully updated BrokerEnabled to $sourceDbBrokerEnabled for $destinationDbName on $destinstance." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                                        } catch {
                                            try {
                                                Write-Message -Level Verbose -Message "Updating BrokerEnabled to $sourceDbBrokerEnabled for $destinationDbName on $destinstance failed so we try to regenerate the broker identifier." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                                                $quotedDatabaseName = $destserver.Query("SELECT QUOTENAME('$($destinationDbName.Replace("'", "''"))') AS quotename").quotename
                                                $null = $destserver.Query("ALTER DATABASE $quotedDatabaseName SET NEW_BROKER WITH ROLLBACK IMMEDIATE")
                                                $NewDatabase.BrokerEnabled = $sourceDbBrokerEnabled
                                                $null = $NewDatabase.Alter()
                                                Write-Message -Level Verbose -Message "Successfully updated BrokerEnabled to $sourceDbBrokerEnabled for $destinationDbName on $destinstance." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                                            } catch {
                                                Write-Message -Level Warning -Message "Failed to update BrokerEnabled to $sourceDbBrokerEnabled for $destinationDbName on $destinstance." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                                                $propfailures += "Message broker"
                                            }
                                        }
                                    }
                                }
                            }
    
                            if ($sourceDbReadOnly -ne $NewDatabase.ReadOnly -and -not $NoRecovery) {
                                if ($__realCmdlet.ShouldProcess($destinstance, "Updating ReadOnly status on $destinationDbName")) {
                                    try {
                                        if ($sourceDbReadOnly) {
                                            $result = Set-DbaDbState -SqlInstance $destserver -Database $destinationDbName -ReadOnly -EnableException
                                        } else {
                                            $result = Set-DbaDbState -SqlInstance $destserver -Database $destinationDbName -ReadWrite -EnableException
                                        }
                                    } catch {
                                        Write-Message -Level Verbose -Message "Failed to update ReadOnly status on $destinationDbName." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                                        $propfailures += "Read only"
                                    }
                                }
                            }
    
                            if ($__realCmdlet.ShouldProcess("console", "Outputting object")) {
                                if ($propfailures.Count -gt 0) {
                                    $propfailure = $propfailures -join ", "
                                    $copyDatabaseStatus.Notes = "Failed to apply the following properties: $propfailure"
                                }
    
                                $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            }
    
                            $dbTotalTime = $dbFinish - $dbStart
                            $dbTotalTime = ($dbTotalTime.ToString().Split(".")[0])
    
                            Write-Message -Level Verbose -Message "Finished: $dbFinish." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                            Write-Message -Level Verbose -Message "Elapsed time: $dbTotalTime." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
    
                        } # end db by db processing
                    }
                }
    }

    [pscustomobject]@{
        __CopyDbaDatabaseProcessComplete = $true
        backupCollection = $backupCollection
        NoBackupCleanup = $NoBackupCleanup
        WithReplace = $WithReplace
        fsWarning = $fsWarning
        replaceInFile = $replaceInFile
        sourceServer = $sourceServer
        elapsed = $elapsed
        started = $started
        sourceDbOwnerChaining = $sourceDbOwnerChaining
        sourceDbTrustworthy = $sourceDbTrustworthy
        sourceDbBrokerEnabled = $sourceDbBrokerEnabled
    }
} $Source $SourceSqlCredential $Destination $DestinationSqlCredential $Database $ExcludeDatabase $AllDatabases $BackupRestore $AdvancedBackupParams $SharedPath $AzureCredential $WithReplace $NoRecovery $NoBackupCleanup $NumberFiles $DetachAttach $Reattach $SetSourceReadOnly $SetSourceOffline $ReuseSourceFolderStructure $IncludeSupportDbs $UseLastBackup $Continue $InputObject $NoCopyOnly $KeepCDC $KeepReplication $NewName $Prefix $Force $EnableException $__boundNewName $__boundPrefix $backupCollection $fsWarning $replaceInFile $sourceServer $elapsed $started $sourceDbOwnerChaining $sourceDbTrustworthy $sourceDbBrokerEnabled $__realCmdlet @__commonParameters 3>&1 2>&1
""";

    // PS: the begin block's parameter-combination validations, verbatim apart from
    // -FunctionName Copy-DbaDatabase on each Stop-Function. They latch Test-FunctionInterrupt,
    // which is what stops every later record and the end block. $CopyOnly, the $ConfirmPreference
    // suppression and the five internal helper declarations are begin-block setup rather than
    // validation, so they live at the top of the process hop where the body can see them.
    private const string BeginScript = """
param($InputObject, $Source, $BackupRestore, $SharedPath, $UseLastBackup, $DetachAttach, $Reattach, $Destination, $Continue, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    # Untyped flags for the same positional-binding reason as the process block above.
    # $EnableException is unused here yet must be in scope: Stop-Function defaults its own
    # [bool]$EnableException from the caller's variable, so an undefined one binds $null and
    # the validation dies on a cast error instead of warning.
    param([Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, [Dataplat.Dbatools.Parameter.DbaInstanceParameter]$Source, $BackupRestore, [string]$SharedPath, $UseLastBackup, $DetachAttach, $Reattach, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$Destination, $Continue, $EnableException)

    if (-not $InputObject -and -not $Source) {
        Stop-Function -Message "With no piped input a -Source must be specified." -FunctionName Copy-DbaDatabase
        return
    }
    if ($BackupRestore -and (-not $SharedPath -and -not $UseLastBackup)) {
        Stop-Function -Message "When using -BackupRestore, you must specify -SharedPath or -UseLastBackup" -FunctionName Copy-DbaDatabase
        return
    }
    if ($SharedPath -and $UseLastBackup) {
        Stop-Function -Message "-SharedPath cannot be used with -UseLastBackup because the backup path is determined by the paths in the last backups" -FunctionName Copy-DbaDatabase
        return
    }
    if ($DetachAttach -and -not $Reattach -and $Destination.Count -gt 1) {
        Stop-Function -Message "When using -DetachAttach with multiple servers, you must specify -Reattach to reattach database at source" -FunctionName Copy-DbaDatabase
        return
    }
    if ($SharedPath -like 'https*' -and $DetachAttach) {
        Stop-Function -Message "Cannot use DetachAttach with Azure storage. Option is only available with BackupRestore" -FunctionName Copy-DbaDatabase
        return
    }
    if ($Continue -and -not $UseLastBackup) {
        Stop-Function -Message "-Continue cannot be used without -UseLastBackup" -FunctionName Copy-DbaDatabase
        return
    }
} $InputObject $Source $BackupRestore $SharedPath $UseLastBackup $DetachAttach $Reattach $Destination $Continue $EnableException @__commonParameters 3>&1 2>&1
""";

    // PS: the end block, verbatim apart from the -FunctionName/-ModuleName attribution. Every
    // value it reads is cross-record state the process hop handed back through the sentinel:
    // $NoBackupCleanup (possibly flipped true by a backup file that would not delete),
    // $backupCollection, $sourceServer, $elapsed and $started.
    private const string EndScript = """
param($NoBackupCleanup, $Destination, $backupCollection, $sourceServer, $elapsed, $started, $SharedPath, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($NoBackupCleanup, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$Destination, $backupCollection, $sourceServer, $elapsed, $started, [string]$SharedPath)

    if (Test-FunctionInterrupt) {
        return
    }
    if (-not $NoBackupCleanUp -and $Destination.Count -gt 1) {
        foreach ($backupFile in ($backupCollection.BackupPath)) {
            try {
                if (Test-Path $backupFile -ErrorAction Stop) {
                    Write-Message -Level Verbose -Message "Deleting $backupFile." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                    Remove-Item $backupFile -ErrorAction Stop
                }
            } catch {
                try {
                    Write-Message -Level Verbose -Message "Trying alternate SQL method to delete $backupFile." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                    $sql = "EXEC master.sys.xp_delete_file 0, '$backupFile'"
                    Write-Message -Level Debug -Message $sql -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                    $null = $sourceServer.Query($sql)
                } catch {
                    Write-Message -Level Verbose -Message "Cannot delete backup file $backupFile." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
                }
            }
        }
    }
    if (Test-FunctionInterrupt) {
        return
    }
    if ($null -ne $elapsed) {
        $totalTime = ($elapsed.Elapsed.toString().Split(".")[0])

        Write-Message -Level Verbose -Message "`nDatabase migration finished" -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
        Write-Message -Level Verbose -Message "Migration started: $started" -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
        Write-Message -Level Verbose -Message "Migration completed: $(Get-Date)" -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
        Write-Message -Level Verbose -Message "Total Elapsed time: $totalTime" -FunctionName Copy-DbaDatabase -ModuleName "dbatools"

        if ($SharedPath -and $NoBackupCleanup) {
            Write-Message -Level Verbose -Message "Backups still exist at $SharedPath." -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
        }
    } else {
        Write-Message -Level Verbose -Message "No work was done, as we stopped during setup phase" -FunctionName Copy-DbaDatabase -ModuleName "dbatools"
    }
} $NoBackupCleanup $Destination $backupCollection $sourceServer $elapsed $started $SharedPath @__commonParameters 3>&1 2>&1
""";
}