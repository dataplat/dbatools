#nullable enable

namespace Dataplat.Dbatools.Commands;

/// <summary>Hop script HEAD for Test-DbaLastBackup (W3-110): the outer scaffold, the
/// continue-relay guard opening, the sentinel restore, and phases A (Path-mode work
/// item collection) + B (InputObject-mode collection). Composed with ScriptTail via
/// "\n" (raw strings carry no trailing newline); the composed script is
/// parse-checked. The body is MECHANICALLY EXTRACTED from the source
/// (verbatim-proven by reverse-diff); substitutions are the 12 Test-Bound carried
/// flags, the three gates -&gt; $__realCmdlet, and -FunctionName on the 41 hop-frame
/// Stop-Function/Write-Message statements (W1-090).</summary>
public sealed partial class TestDbaLastBackupCommand
{
    private const string ProcessScriptHead = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $Destination, $DestinationSqlCredential, $DataDirectory, $LogDirectory, $FileStreamDirectory, $Prefix, $VerifyOnly, $NoCheck, $NoDrop, $CopyFile, $CopyPath, $MaxSize, $DeviceType, $IncludeCopyOnly, $IgnoreLogBackup, $StorageCredential, $InputObject, $MaxTransferSize, $BufferCount, $IgnoreDiffBackup, $MaxDop, $ReuseSourceFolderStructure, $Checksum, $Wait, $Path, $EnableException, $__boundDatabase, $__boundExcludeDatabase, $__boundPath, $__boundDestination, $__boundStorageCredential, $__boundIgnoreDiffBackup, $__boundIgnoreLogBackup, $__boundCopyFile, $__boundMaxTransferSize, $__boundBufferCount, $__boundFileStreamDirectory, $__boundChecksum, $__state, $__realCmdlet, $__continueMarker, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [object[]]$Database, [object[]]$ExcludeDatabase, [Dataplat.Dbatools.Parameter.DbaInstanceParameter]$Destination, [object]$DestinationSqlCredential, [string]$DataDirectory, [string]$LogDirectory, [string]$FileStreamDirectory, [string]$Prefix, $VerifyOnly, $NoCheck, $NoDrop, $CopyFile, [string]$CopyPath, [int]$MaxSize, [string[]]$DeviceType, $IncludeCopyOnly, $IgnoreLogBackup, [string]$StorageCredential, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, [int]$MaxTransferSize, [int]$BufferCount, $IgnoreDiffBackup, [int]$MaxDop, $ReuseSourceFolderStructure, $Checksum, [int]$Wait, [string[]]$Path, $EnableException, $__boundDatabase, $__boundExcludeDatabase, $__boundPath, $__boundDestination, $__boundStorageCredential, $__boundIgnoreDiffBackup, $__boundIgnoreLogBackup, $__boundCopyFile, $__boundMaxTransferSize, $__boundBufferCount, $__boundFileStreamDirectory, $__boundChecksum, $__state, $__realCmdlet, $__continueMarker, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    $__continueEscaped = $true
    foreach ($__continueRelayGuard in @(1)) {
        . {
            if ($__state.ContainsKey("CopyPath")) { $CopyPath = $__state["CopyPath"] }
        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        $workItems = New-Object System.Collections.Generic.List[hashtable]
        $databaseFilters = @()
        $excludeDatabaseFilters = @()
        $hasExactDatabaseFiltersOnly = $true

        if ($__boundDatabase) {
            $databaseFilters = @($Database | ForEach-Object { [string]$PSItem })
            foreach ($databaseFilter in $databaseFilters) {
                if ($databaseFilter -match "[\*\?\[]") {
                    $hasExactDatabaseFiltersOnly = $false
                    break
                }
            }
        }

        if ($__boundExcludeDatabase) {
            $excludeDatabaseFilters = @($ExcludeDatabase | ForEach-Object { [string]$PSItem })
        }

        if ($__boundPath) {
            if (-not ($__boundDestination)) {
                Stop-Function -Message "A -Destination server must be specified when using -Path to specify backup folder paths." -FunctionName Test-DbaLastBackup
                return
            }

            try {
                $destserver = Connect-DbaInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Destination -FunctionName Test-DbaLastBackup
                return
            }

            if ($DataDirectory) {
                if (-not (Test-DbaPath -SqlInstance $destserver -Path $DataDirectory)) {
                    $serviceAccount = $destserver.ServiceAccount
                    Stop-Function -Message "Can't access $DataDirectory Please check if $serviceAccount has permissions." -Continue -FunctionName Test-DbaLastBackup
                }
                $effectiveDataDirectory = $DataDirectory
            } else {
                $effectiveDataDirectory = Get-SqlDefaultPaths -SqlInstance $destserver -FileType mdf
            }

            if ($LogDirectory) {
                if (-not (Test-DbaPath -SqlInstance $destserver -Path $LogDirectory)) {
                    $serviceAccount = $destserver.ServiceAccount
                    Stop-Function -Message "$Destination can't access its local directory $LogDirectory. Please check if $serviceAccount has permissions." -Continue -FunctionName Test-DbaLastBackup
                }
                $effectiveLogDirectory = $LogDirectory
            } else {
                $effectiveLogDirectory = Get-SqlDefaultPaths -SqlInstance $destserver -FileType ldf
            }

            Write-Message -Level Verbose -Message "Getting backup information from path(s): $($Path -join ', ')." -FunctionName Test-DbaLastBackup -ModuleName "dbatools"

            $splatGetBackupInfo = @{
                SqlInstance      = $destserver
                Path             = $Path
                DirectoryRecurse = $true
                EnableException  = $EnableException
            }
            if ($databaseFilters.Count -gt 0 -and $hasExactDatabaseFiltersOnly) {
                $splatGetBackupInfo.Add("DatabaseName", $databaseFilters)
            }
            if ($__boundStorageCredential) {
                $splatGetBackupInfo.Add("StorageCredential", $StorageCredential)
            }

            try {
                $allPathBackups = Get-DbaBackupInformation @splatGetBackupInfo
            } catch {
                Stop-Function -Message "Failed to get backup information from path(s)." -ErrorRecord $_ -FunctionName Test-DbaLastBackup
                return
            }

            if (-not $allPathBackups) {
                Stop-Function -Message "No backup files found in the specified path(s)." -FunctionName Test-DbaLastBackup
                return
            }

            if ($databaseFilters.Count -gt 0) {
                $allPathBackups = $allPathBackups | Where-Object {
                    $databaseMatch = $false
                    foreach ($databaseFilter in $databaseFilters) {
                        if ($PSItem.Database -like $databaseFilter) {
                            $databaseMatch = $true
                            break
                        }
                    }
                    $databaseMatch
                }
            }

            if ($excludeDatabaseFilters.Count -gt 0) {
                $allPathBackups = $allPathBackups | Where-Object {
                    $excludeDatabase = $false
                    foreach ($excludeDatabaseFilter in $excludeDatabaseFilters) {
                        if ($PSItem.Database -like $excludeDatabaseFilter) {
                            $excludeDatabase = $true
                            break
                        }
                    }
                    -not $excludeDatabase
                }
            }

            $allPathBackups = $allPathBackups | Select-Object *, @{
                Name       = "SourceIdentity"
                Expression = {
                    if ($PSItem.SqlInstance) {
                        [string]$PSItem.SqlInstance
                    } elseif ($PSItem.InstanceName) {
                        [string]$PSItem.InstanceName
                    } elseif ($PSItem.ComputerName) {
                        [string]$PSItem.ComputerName
                    } else {
                        "N/A"
                    }
                }
            }
            $pathDatabaseGroups = $allPathBackups | Group-Object -Property Database, SourceIdentity

            foreach ($pathDbGroup in $pathDatabaseGroups) {
                $dbName = $pathDbGroup.Group[0].Database
                $sourceIdentity = $pathDbGroup.Group[0].SourceIdentity
                $lastbackup = $pathDbGroup.Group

                if (-not ($lastbackup | Where-Object { $_.Type -eq "Full" -or $_.Type -eq "Database" })) {
                    Write-Message -Level Verbose -Message "No full backup found for $dbName in the specified path(s)." -FunctionName Test-DbaLastBackup -ModuleName "dbatools"
                    [PSCustomObject]@{
                        SourceServer   = $sourceIdentity
                        TestServer     = $Destination
                        Database       = $dbName
                        FileExists     = $false
                        Size           = $null
                        RestoreResult  = "No full backup found"
                        DbccResult     = "Skipped"
                        RestoreStart   = $null
                        RestoreEnd     = $null
                        RestoreElapsed = $null
                        DbccMaxDop     = $null
                        DbccStart      = $null
                        DbccEnd        = $null
                        DbccElapsed    = $null
                        DbccOutput     = $null
                        BackupDates    = $null
                        BackupFiles    = $null
                    }
                    continue
                }

                $totalSizeMB = ($lastbackup.TotalSize.Megabyte | Measure-Object -Sum).Sum
                if ($MaxSize -and $MaxSize -lt $totalSizeMB) {
                    [PSCustomObject]@{
                        SourceServer   = $sourceIdentity
                        TestServer     = $Destination
                        Database       = $dbName
                        FileExists     = $null
                        Size           = [dbasize](($lastbackup.TotalSize | Measure-Object -Sum).Sum)
                        RestoreResult  = "The backup size for $dbName ($totalSizeMB MB) exceeds the specified maximum size ($MaxSize MB)."
                        DbccResult     = "Skipped"
                        RestoreStart   = $null
                        RestoreEnd     = $null
                        RestoreElapsed = $null
                        DbccMaxDop     = $null
                        DbccStart      = $null
                        DbccEnd        = $null
                        DbccElapsed    = $null
                        DbccOutput     = $null
                        BackupDates    = [dbadatetime[]]($lastbackup.Start)
                        BackupFiles    = $lastbackup.FullName
                    }
                    continue
                }

                $null = $workItems.Add(@{
                        DbName                    = $dbName
                        LastBackup                = $lastbackup
                        Source                    = $sourceIdentity
                        DestServer                = $destserver
                        DestinationName           = [string]$Destination
                        DestinationCredential     = $DestinationSqlCredential
                        FileExists                = $true
                        SkipRestoreResult         = $null
                        SkipDbccResult            = $null
                        TrustDbBackupHistory      = $true
                        IgnoreDiffBackupInRestore = ($__boundIgnoreDiffBackup)
                        RemoveArray               = $null
                        EffectiveDataDirectory    = $effectiveDataDirectory
                        EffectiveLogDirectory     = $effectiveLogDirectory
                    })
            }
        }

        foreach ($db in $InputObject) {
            if ($db.Name -eq "tempdb") {
                continue
            }

            $sourceserver = $db.Parent
            $source = $db.Parent.Name
            $instance = [DbaInstanceParameter]$source
            $copysuccess = $true
            $dbName = $db.Name
            $restoreresult = $null

            if (-not ($__boundDestination)) {
                $destination = $sourceserver.Name
                $DestinationSqlCredential = $SqlCredential
            }

            if ($db.LastFullBackup.Year -eq 1) {
                [PSCustomObject]@{
                    SourceServer   = $source
                    TestServer     = $destination
                    Database       = $dbName
                    FileExists     = $false
                    Size           = $null
                    RestoreResult  = "Skipped"
                    DbccResult     = "Skipped"
                    RestoreStart   = $null
                    RestoreEnd     = $null
                    RestoreElapsed = $null
                    DbccMaxDop     = $null
                    DbccStart      = $null
                    DbccEnd        = $null
                    DbccElapsed    = $null
                    DbccOutput     = $null
                    BackupDates    = $null
                    BackupFiles    = $null
                }
                continue
            }

            try {
                $destserver = Connect-DbaInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Destination -Continue -FunctionName Test-DbaLastBackup
            }

            if ($destserver.VersionMajor -lt $sourceserver.VersionMajor) {
                Stop-Function -Message "$Destination is a lower version than $instance. Backups would be incompatible." -Continue -FunctionName Test-DbaLastBackup
            }

            if ($destserver.VersionMajor -eq $sourceserver.VersionMajor -and $destserver.VersionMinor -lt $sourceserver.VersionMinor) {
                Stop-Function -Message "$Destination is a lower version than $instance. Backups would be incompatible." -Continue -FunctionName Test-DbaLastBackup
            }

            if ($CopyPath) {
                $testpath = Test-DbaPath -SqlInstance $destserver -Path $CopyPath
                if (-not $testpath) {
                    Stop-Function -Message "$destserver cannot access $CopyPath." -Continue -FunctionName Test-DbaLastBackup
                }
            } else {
                # If not CopyPath is specified, use the destination server default backup directory
                $copyPath = $destserver.BackupDirectory
            }

            if ($instance -ne $destination -and -not $CopyFile) {
                $sourcerealname = $sourceserver.ComputerNetBiosName
                $destrealname = $destserver.ComputerNetBiosName

                if ($CopyPath) {
                    if ($CopyPath.StartsWith("\\") -eq $false -and $sourcerealname -ne $destrealname) {
                        Stop-Function -Message "CopyFolder must be a network share if the source and destination servers are not the same." -Continue -FunctionName Test-DbaLastBackup
                    }
                }
            }

            if ($DataDirectory) {
                if (-not (Test-DbaPath -SqlInstance $destserver -Path $DataDirectory)) {
                    $serviceAccount = $destserver.ServiceAccount
                    Stop-Function -Message "Can't access $DataDirectory Please check if $serviceAccount has permissions." -Continue -FunctionName Test-DbaLastBackup
                }
                $effectiveDataDirectory = $DataDirectory
            } else {
                $effectiveDataDirectory = Get-SqlDefaultPaths -SqlInstance $destserver -FileType mdf
            }

            if ($LogDirectory) {
                if (-not (Test-DbaPath -SqlInstance $destserver -Path $LogDirectory)) {
                    $serviceAccount = $destserver.ServiceAccount
                    Stop-Function -Message "$Destination can't access its local directory $LogDirectory. Please check if $serviceAccount has permissions." -Continue -FunctionName Test-DbaLastBackup
                }
                $effectiveLogDirectory = $LogDirectory
            } else {
                $effectiveLogDirectory = Get-SqlDefaultPaths -SqlInstance $destserver -FileType ldf
            }

            if (($__boundStorageCredential) -and ($__boundCopyFile)) {
                Stop-Function -Message "Cannot use CopyFile with cloud storage backups (Azure/S3)." -Continue -FunctionName Test-DbaLastBackup
            }

            Write-Message -Level Verbose -Message "Getting recent backup history for $dbName on $instance." -FunctionName Test-DbaLastBackup -ModuleName "dbatools"

            if ($__boundIgnoreLogBackup) {
                Write-Message -Level Verbose -Message "Skipping Log backups as requested." -FunctionName Test-DbaLastBackup -ModuleName "dbatools"
                $lastbackup = @()
                $lastbackup += $full = Get-DbaDbBackupHistory -SqlInstance $sourceserver -Database $dbName -IncludeCopyOnly:$IncludeCopyOnly -LastFull -DeviceType $DeviceType -WarningAction SilentlyContinue
                if (-not ($__boundIgnoreDiffBackup)) {
                    $diff = Get-DbaDbBackupHistory -SqlInstance $sourceserver -Database $dbName -IncludeCopyOnly:$IncludeCopyOnly -LastDiff -DeviceType $DeviceType -WarningAction SilentlyContinue
                }
                if ($full.start -le $diff.start) {
                    $lastbackup += $diff
                }
            } else {
                $lastbackup = Get-DbaDbBackupHistory -SqlInstance $sourceserver -Database $dbName -IncludeCopyOnly:$IncludeCopyOnly -Last -DeviceType $DeviceType -WarningAction SilentlyContinue -IgnoreDiffBackup:$IgnoreDiffBackup
            }

            if (-not $lastbackup) {
                Write-Message -Level Verbose -Message "No backups exist for this database." -FunctionName Test-DbaLastBackup -ModuleName "dbatools"
                # This code should never be executed as there is already a test for databases without backup in line 241.
                continue
            }

            $totalSizeMB = ($lastbackup.TotalSize.Megabyte | Measure-Object -Sum).Sum
            if ($MaxSize -and $MaxSize -lt $totalSizeMB) {
                [PSCustomObject]@{
                    SourceServer   = $source
                    TestServer     = $destination
                    Database       = $dbName
                    FileExists     = $null
                    Size           = [dbasize](($lastbackup.TotalSize | Measure-Object -Sum).Sum)
                    RestoreResult  = "The backup size for $dbName ($totalSizeMB MB) exceeds the specified maximum size ($MaxSize MB)."
                    DbccResult     = "Skipped"
                    RestoreStart   = $null
                    RestoreEnd     = $null
                    RestoreElapsed = $null
                    DbccMaxDop     = $null
                    DbccStart      = $null
                    DbccEnd        = $null
                    DbccElapsed    = $null
                    DbccOutput     = $null
                    BackupDates    = [dbadatetime[]]($lastbackup.Start)
                    BackupFiles    = $lastbackup.FullName
                }
                continue
            }

""";
}
