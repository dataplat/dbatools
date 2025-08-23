function Restore-DbaDatabase {
    <#
    .SYNOPSIS
        Restores SQL Server databases from backup files with intelligent backup chain selection and point-in-time recovery.

    .DESCRIPTION
        Scans backup files and automatically selects the optimal restore sequence to recover databases to a specific point in time.
        This function handles the complex task of building complete backup chains from full, differential, and transaction log backups,
        so you don't have to manually determine which files are needed or in what order to restore them.

        The function excels at disaster recovery scenarios where you need to quickly restore from a collection of backup files.
        It validates backup headers, ensures restore chains are complete, and can recover to any point in time within your backup coverage.
        Whether restoring from local files, network shares, or Azure blob storage, it automatically handles file discovery and validation.

        By default, all file paths must be accessible to the target SQL Server instance. The function uses xp_dirtree for remote file scanning
        and supports various input methods including direct file lists, folder scanning, and pipeline input from other dbatools commands.
        It integrates seamlessly with Ola Hallengren's maintenance solution backup structures for faster processing.

    .PARAMETER SqlInstance
        The target SQL Server instance.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Path
        Specifies the location of backup files to restore from, supporting local drives, UNC paths, or Azure blob storage URLs.
        Use this when you need to restore from a specific backup location or when piping backup files from Get-ChildItem.
        Accepts multiple comma-separated paths for complex restore scenarios spanning multiple locations.

    .PARAMETER DatabaseName
        Defines the target database name for the restored database when different from the original name.
        Use this when creating a copy of a production database for testing or when restoring to avoid name conflicts.
        Required when restoring a single database to a different name than what's stored in the backup files.

    .PARAMETER DestinationDataDirectory
        Sets the target directory path where data files (.mdf, .ndf) will be restored on the destination instance.
        Use this when you need to restore to a different drive or storage location than the original database.
        When specified alone, log files will also be placed here unless DestinationLogDirectory is provided.

    .PARAMETER DestinationLogDirectory
        Defines the target directory for transaction log files (.ldf) separate from data files.
        Use this to follow best practices by placing log files on different drives for performance and disaster recovery.
        Must be used together with DestinationDataDirectory for proper file separation.

    .PARAMETER DestinationFileStreamDirectory
        Specifies where FILESTREAM data containers will be restored, separate from regular database files.
        Use this when your database contains FILESTREAM data and you need to place it on specific storage.
        Requires DestinationDataDirectory to be specified and the target instance to have FILESTREAM enabled.

    .PARAMETER RestoreTime
        Sets the point-in-time recovery target for restoring the database to a specific moment.
        Use this for recovering from logical errors, unwanted changes, or data corruption that occurred at a known time.
        Requires a complete backup chain including transaction logs covering the specified time period.

    .PARAMETER NoRecovery
        Leaves the database in a restoring state to allow additional transaction log restores or log shipping setup.
        Use this when you need to apply additional log backups, set up availability groups, or prepare for continuous log shipping.
        The database will remain inaccessible until recovered with the RESTORE WITH RECOVERY statement.

    .PARAMETER WithReplace
        Allows overwriting an existing database with the same name during the restore operation.
        Use this when you need to refresh a test environment or replace a corrupted database with a backup.
        Essential for disaster recovery scenarios where you're restoring over a damaged database.

    .PARAMETER XpDirTree
        Forces backup file discovery to use SQL Server's xp_dirtree instead of PowerShell file system access.
        Use this when backup files are on network shares that PowerShell cannot access but SQL Server can.
        Requires sysadmin privileges and may be needed for environments with strict network security policies.

    .PARAMETER OutputScriptOnly
        Generates the T-SQL RESTORE statements without executing them, allowing for script review or manual execution.
        Use this to validate restore commands, create deployment scripts, or when you need approval before running restores.
        Helpful for compliance environments where all database changes must be reviewed before execution.

    .PARAMETER VerifyOnly
        Validates backup files and restore paths without performing the actual restore operation.
        Use this to test backup file integrity, verify backup chains are complete, and confirm restore feasibility.
        Essential for disaster recovery planning and backup validation routines without impacting production systems.

    .PARAMETER MaintenanceSolutionBackup
        Optimizes backup file scanning for Ola Hallengren's Maintenance Solution folder structure.
        Use this when your backups follow the standard Ola Hallengren folder layout with separate FULL, DIFF, and LOG subdirectories.
        Significantly improves performance by using predictable file locations rather than reading every backup header.

    .PARAMETER FileMapping
        Provides precise control over where individual database files are restored using logical file names.
        Use this when you need granular file placement, such as putting specific filegroups on different drives for performance.
        Create a hashtable mapping logical names to physical paths: @{'DataFile1'='C:\Data\File1.mdf'; 'LogFile1'='D:\Logs\File1.ldf'}

    .PARAMETER IgnoreLogBackup
        Excludes transaction log backups from the restore operation, stopping at the latest full or differential backup.
        Use this when you only need to restore to a recent backup checkpoint rather than the latest point in time.
        Useful for creating a baseline copy of a database without applying the most recent transactions.

    .PARAMETER IgnoreDiffBackup
        Skips differential backups and restores using only full backups plus transaction logs.
        Use this when differential backups are corrupted or when you need to restore using a specific full backup as the baseline.
        Results in longer restore times as all transaction log backups since the full backup must be applied.

    .PARAMETER UseDestinationDefaultDirectories
        Places restored database files in the SQL Server instance's default data and log directories.
        Use this when you want to follow the target instance's standard file location configuration.
        The function will attempt to create directories if they don't exist, ensuring consistent file placement.

    .PARAMETER ReuseSourceFolderStructure
        Maintains the original database file directory structure from the source server during restore.
        Use this when migrating between servers that share similar drive layouts or when preserving application-specific paths.
        Consider version differences in SQL Server default paths (MSSQL12, MSSQL13, etc.) when restoring between versions.

    .PARAMETER DestinationFilePrefix
        This value will be prefixed to ALL restored files (log and data). This is just a simple string prefix.
        If you want to perform more complex rename operations then please use the FileMapping parameter.
        This will apply to all file move options, except for FileMapping.

    .PARAMETER DestinationFileSuffix
        This value will be suffixed to ALL restored files (log and data). This is just a simple string suffix.
        If you want to perform more complex rename operations then please use the FileMapping parameter.
        This will apply to all file move options, except for FileMapping.

    .PARAMETER RestoredDatabaseNamePrefix
        A string which will be prefixed to the start of the restore Database's Name.
        Useful if restoring a copy to the same sql server for testing.

    .PARAMETER TrustDbBackupHistory
        Bypasses backup header validation when using piped input from Get-DbaDbBackupHistory or similar commands.
        Use this to significantly speed up restores when you're confident in the backup chain integrity.
        Trades verification safety for performance - backup file issues won't be detected until the restore attempt.

    .PARAMETER MaxTransferSize
        Controls the size of each data transfer between storage and SQL Server during restore operations.
        Use this to optimize restore performance based on your storage subsystem characteristics.
        Must be a multiple of 64KB with higher values potentially improving performance on high-speed storage.

    .PARAMETER Blocksize
        Defines the physical block size used for backup file reading during restore operations.
        Use this to match the block size used during backup creation for optimal performance.
        Valid values: 0.5KB, 1KB, 2KB, 4KB, 8KB, 16KB, 32KB, or 64KB, with larger blocks typically faster on modern storage.

    .PARAMETER BufferCount
        Sets the number of I/O buffers SQL Server uses for the restore operation to improve throughput.
        Use this to optimize restore performance by allowing more parallel I/O operations.
        Higher values can improve performance but consume more memory - typically set between 2-64 based on available RAM.

    .PARAMETER NoXpDirRecurse
        If specified, prevents the XpDirTree process from recursing (its default behaviour).

    .PARAMETER DirectoryRecurse
        If specified the specified directory will be recursed into (overriding the default behaviour).

    .PARAMETER Continue
        Resumes log restore operations on databases currently in RESTORING or STANDBY states.
        Use this to apply additional transaction log backups to advance the recovery point of an existing restore chain.
        Essential for log shipping scenarios or when performing point-in-time recovery in multiple steps.

    .PARAMETER ExecuteAs
        If value provided the restore will be executed under this login's context. The login must exist, and have the relevant permissions to perform the restore.

    .PARAMETER StandbyDirectory
        Places restored databases in STANDBY mode with undo files created in the specified directory.
        Use this for log shipping secondary servers or when you need read-only access during restore operations.
        The directory must exist and be writable by the SQL Server service account for undo file creation.

    .PARAMETER AzureCredential
        Specifies the SQL Server credential name for authenticating to Azure blob storage during restore operations.
        Use this when restoring from Azure blob storage backups that require authentication beyond SAS tokens.
        The credential must be created on the SQL Server instance with the appropriate storage account access keys.

    .PARAMETER ReplaceDbNameInFile
        Substitutes the original database name with the new DatabaseName in physical file names during restore.
        Use this when restoring databases with descriptive file names to maintain naming consistency.
        Requires DatabaseName parameter and helps avoid confusing file names like "Production_Data.mdf" in test environments.

    .PARAMETER Recover
        Brings databases currently in RESTORING state online by executing RESTORE WITH RECOVERY.
        Use this to complete restore operations that were left in NoRecovery state or to finalize standby databases.
        Makes previously inaccessible databases available for normal read/write operations.

    .PARAMETER GetBackupInformation
        Passing a string value into this parameter will cause a global variable to be created holding the output of Get-DbaBackupInformation.

    .PARAMETER SelectBackupInformation
        Passing a string value into this parameter will cause a global variable to be created holding the output of Select-DbaBackupInformation.

    .PARAMETER FormatBackupInformation
        Passing a string value into this parameter will cause a global variable to be created holding the output of Format-DbaBackupInformation.

    .PARAMETER TestBackupInformation
        Passing a string value into this parameter will cause a global variable to be created holding the output of Test-DbaBackupInformation.

    .PARAMETER StopAfterGetBackupInformation
        Switch which will cause the function to exit after returning GetBackupInformation.

    .PARAMETER StopAfterSelectBackupInformation
        Switch which will cause the function to exit after returning SelectBackupInformation.

    .PARAMETER StopAfterFormatBackupInformation
        Switch which will cause the function to exit after returning FormatBackupInformation.

    .PARAMETER StopAfterTestBackupInformation
        Switch which will cause the function to exit after returning TestBackupInformation.

    .PARAMETER StatementTimeOut
        Sets the maximum time in minutes to wait for restore operations before timing out.
        Use this to prevent extremely long-running restores from hanging indefinitely in automated scripts.
        Defaults to unlimited since large database restores can take hours depending on size and storage speed.

    .PARAMETER KeepCDC
        Preserves Change Data Capture (CDC) configuration and data during the restore operation.
        Use this when restoring databases with CDC enabled and you need to maintain change tracking functionality.
        Cannot be combined with NoRecovery or Standby modes as CDC requires the database to be fully recovered.

    .PARAMETER KeepReplication
        Maintains replication settings and objects when restoring databases involved in replication topologies.
        Use this when restoring publisher or subscriber databases where you need to preserve replication configuration.
        Essential for disaster recovery scenarios involving replicated databases to avoid reconfiguring publications and subscriptions.

    .PARAMETER PageRestore
        Performs targeted restoration of specific damaged pages using output from Get-DbaSuspectPages.
        Use this for repairing isolated page corruption without restoring the entire database.
        Enterprise Edition enables online page restore while Standard Edition requires the database offline during repair.

    .PARAMETER PageRestoreTailFolder
        Specifies where to create the tail log backup required for page restore operations.
        Use this to designate a safe location for the automatic tail log backup that page restore creates.
        The folder must be accessible to the SQL Server service account and have sufficient space for the tail log backup.

    .PARAMETER StopMark
        Marked point in the transaction log to stop the restore at (Mark is created via BEGIN TRANSACTION (https://docs.microsoft.com/en-us/sql/t-sql/language-elements/begin-transaction-transact-sql?view=sql-server-ver15)).

    .PARAMETER StopBefore
        Switch to indicate the restore should stop before StopMark occurs, default is to stop when mark is created.

    .PARAMETER StopAfterDate
        By default the restore will stop at the first occurence of StopMark found in the chain, passing a datetime where will cause it to stop the first StopMark atfer that datetime.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Confirm
        Prompts to confirm certain actions.

    .PARAMETER WhatIf
        Shows what would happen if the command would execute, but does not actually perform the command.

    .NOTES
        Tags: DisasterRecovery, Backup, Restore
        Author: Stuart Moore (@napalmgram), stuart-moore.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Restore-DbaDatabase

    .EXAMPLE
        PS C:\> Restore-DbaDatabase -SqlInstance server1\instance1 -Path \\server2\backups

        Scans all the backup files in \\server2\backups, filters them and restores the database to server1\instance1

    .EXAMPLE
        PS C:\> Restore-DbaDatabase -SqlInstance server1\instance1 -Path \\server2\backups -MaintenanceSolutionBackup -DestinationDataDirectory c:\restores

        Scans all the backup files in \\server2\backups$ stored in an Ola Hallengren style folder structure,
        filters them and restores the database to the c:\restores folder on server1\instance1

    .EXAMPLE
        PS C:\> Get-ChildItem c:\SQLbackups1\, \\server\sqlbackups2 | Restore-DbaDatabase -SqlInstance server1\instance1

        Takes the provided files from multiple directories and restores them on  server1\instance1

    .EXAMPLE
        PS C:\> $RestoreTime = Get-Date('11:19 23/12/2016')
        PS C:\> Restore-DbaDatabase -SqlInstance server1\instance1 -Path \\server2\backups -MaintenanceSolutionBackup -DestinationDataDirectory c:\restores -RestoreTime $RestoreTime

        Scans all the backup files in \\server2\backups stored in an Ola Hallengren style folder structure,
        filters them and restores the database to the c:\restores folder on server1\instance1 up to 11:19 23/12/2016

    .EXAMPLE
        PS C:\> $result = Restore-DbaDatabase -SqlInstance server1\instance1 -Path \\server2\backups -DestinationDataDirectory c:\restores -OutputScriptOnly
        PS C:\> $result | Out-File -Filepath c:\scripts\restore.sql

        Scans all the backup files in \\server2\backups, filters them and generate the T-SQL Scripts to restore the database to the latest point in time, and then stores the output in a file for later retrieval

    .EXAMPLE
        PS C:\> Restore-DbaDatabase -SqlInstance server1\instance1 -Path c:\backups -DestinationDataDirectory c:\DataFiles -DestinationLogDirectory c:\LogFile

        Scans all the files in c:\backups and then restores them onto the SQL Server Instance server1\instance1, placing data files
        c:\DataFiles and all the log files into c:\LogFiles

    .EXAMPLE
        PS C:\> Restore-DbaDatabase -SqlInstance server1\instance1 -Path http://demo.blob.core.windows.net/backups/dbbackup.bak -AzureCredential MyAzureCredential

        Will restore the backup held at  http://demo.blob.core.windows.net/backups/dbbackup.bak to server1\instance1. The connection to Azure will be made using the
        credential MyAzureCredential held on instance Server1\instance1

    .EXAMPLE
        PS C:\> Restore-DbaDatabase -SqlInstance server1\instance1 -Path http://demo.blob.core.windows.net/backups/dbbackup.bak

        Will attempt to restore the backups from http://demo.blob.core.windows.net/backups/dbbackup.bak if a SAS credential with the name http://demo.blob.core.windows.net/backups exists on server1\instance1

    .EXAMPLE
        PS C:\> $File = Get-ChildItem c:\backups, \\server1\backups
        PS C:\> $File | Restore-DbaDatabase -SqlInstance Server1\Instance -UseDestinationDefaultDirectories

        This will take all of the files found under the folders c:\backups and \\server1\backups, and pipeline them into
        Restore-DbaDatabase. Restore-DbaDatabase will then scan all of the files, and restore all of the databases included
        to the latest point in time covered by their backups. All data and log files will be moved to the default SQL Server
        folder for those file types as defined on the target instance.

    .EXAMPLE
        PS C:\> $files = Get-ChildItem C:\dbatools\db1
        PS C:\> $params = @{
        >> SqlInstance = 'server\instance1'
        >> DestinationFilePrefix = 'prefix'
        >> DatabaseName ='Restored'
        >> RestoreTime = (get-date "14:58:30 22/05/2017")
        >> NoRecovery = $true
        >> WithReplace = $true
        >> StandbyDirectory = 'C:\dbatools\standby'
        >> }
        >>
        PS C:\> $files | Restore-DbaDatabase @params
        PS C:\> Invoke-DbaQuery -SQLInstance server\instance1 -Query "select top 1 * from Restored.dbo.steps order by dt desc"
        PS C:\> $params.RestoreTime = (get-date "15:09:30 22/05/2017")
        PS C:\> $params.NoRecovery = $false
        PS C:\> $params.Add("Continue",$true)
        PS C:\> $files | Restore-DbaDatabase @params
        PS C:\> Invoke-DbaQuery -SQLInstance server\instance1 -Query "select top 1 * from Restored.dbo.steps order by dt desc"
        PS C:\> Restore-DbaDatabase -SqlInstance server\instance1 -DestinationFilePrefix prefix -DatabaseName Restored -Continue -WithReplace

        In this example we step through the backup files held in c:\dbatools\db1 folder.
        First we restore the database to a point in time in standby mode. This means we can check some details in the databases
        We then roll it on a further 9 minutes to perform some more checks
        And finally we continue by rolling it all the way forward to the latest point in the backup.
        At each step, only the log files needed to roll the database forward are restored.

    .EXAMPLE
        PS C:\> Restore-DbaDatabase -SqlInstance server\instance1 -Path c:\backups -DatabaseName example1 -NoRecovery
        PS C:\> Restore-DbaDatabase -SqlInstance server\instance1 -Recover -DatabaseName example1

        In this example we restore example1 database with no recovery, and then the second call is to set the database to recovery.

    .EXAMPLE
        PS C:\> $SuspectPage = Get-DbaSuspectPage -SqlInstance server\instance1 -Database ProdFinance
        PS C:\> Get-DbaDbBackupHistory -SqlInstance server\instance1 -Database ProdFinance -Last | Restore-DbaDatabase -PageRestore $SuspectPage -PageRestoreTailFolder c:\temp -TrustDbBackupHistory

        Gets a list of Suspect Pages using Get-DbaSuspectPage. Then uses Get-DbaDbBackupHistory and Restore-DbaDatabase to perform a restore of the suspect pages and bring them up to date
        If server\instance1 is Enterprise edition this will be done online, if not it will be performed offline

    .EXAMPLE
        PS C:\> $BackupHistory = Get-DbaBackupInformation -SqlInstance sql2005 -Path \\backups\sql2000\ProdDb
        PS C:\> $BackupHistory | Restore-DbaDatabase -SqlInstance sql2000 -TrustDbBackupHistory

        Due to SQL Server 2000 not returning all the backup headers we cannot restore directly. As this is an issues with the SQL engine all we can offer is the following workaround
        This will use a SQL Server instance > 2000 to read the headers, and then pass them in to Restore-DbaDatabase as a BackupHistory object.

    .EXAMPLE
        PS C:\> Restore-DbaDatabase -SqlInstance server1\instance1 -Path "C:\Temp\devops_prod_full.bak" -DatabaseName "DevOps_DEV" -ReplaceDbNameInFile
        PS C:\> Rename-DbaDatabase -SqlInstance server1\instance1 -Database "DevOps_DEV" -LogicalName "<DBN>_<FT>"

        This will restore the database from the "C:\Temp\devops_prod_full.bak" file, with the new name "DevOps_DEV" and store the different physical files with the new name. It will use the system default configured data and log locations.
        After the restore the logical names of the database files will be renamed with the "DevOps_DEV_ROWS" for MDF/NDF and "DevOps_DEV_LOG" for LDF

    .EXAMPLE
        PS C:\> $FileStructure = @{
        >> 'database_data' = 'C:\Data\database_data.mdf'
        >> 'database_log' = 'C:\Log\database_log.ldf'
        >> }
        >>
        PS C:\> Restore-DbaDatabase -SqlInstance server1 -Path \\ServerName\ShareName\File -DatabaseName database -FileMapping $FileStructure

        Restores 'database' to 'server1' and moves the files to new locations. The format for the $FileStructure HashTable is the file logical name as the Key, and the new location as the Value.

    .EXAMPLE
        PS C:\> $filemap = Get-DbaDbFileMapping -SqlInstance sql2016 -Database test
        PS C:\> Get-ChildItem \\nas\db\backups\test | Restore-DbaDatabase -SqlInstance sql2019 -Database test -FileMapping $filemap.FileMapping

        Restores test to sql2019 using the file structure built from the existing database on sql2016

    .EXAMPLE
        PS C:\> Restore-DbaDatabase -SqlInstance server1 -Path \\ServerName\ShareName\File -DatabaseName database -StopMark OvernightStart -StopBefore -StopAfterDate Get-Date('21:00 10/05/2020')

        Restores the backups from \\ServerName\ShareName\File as database, stops before the first 'OvernightStart' mark that occurs after '21:00 10/05/2020'.

        Note that Date time needs to be specified in your local SQL Server culture
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = "Restore")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "AzureCredential", Justification = "For Parameter AzureCredential")]
    param (
        [parameter(Mandatory)][DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory, ValueFromPipeline, ParameterSetName = "Restore")][parameter(Mandatory, ValueFromPipeline, ParameterSetName = "RestorePage")][object[]]$Path,
        [parameter(ValueFromPipeline)][Alias("Name")][object[]]$DatabaseName,
        [parameter(ParameterSetName = "Restore")][String]$DestinationDataDirectory,
        [parameter(ParameterSetName = "Restore")][String]$DestinationLogDirectory,
        [parameter(ParameterSetName = "Restore")][String]$DestinationFileStreamDirectory,
        [parameter(ParameterSetName = "Restore")][DateTime]$RestoreTime = (Get-Date).AddYears(1),
        [parameter(ParameterSetName = "Restore")][switch]$NoRecovery,
        [parameter(ParameterSetName = "Restore")][switch]$WithReplace,
        [parameter(ParameterSetName = "Restore")][switch]$KeepReplication,
        [parameter(ParameterSetName = "Restore")][Switch]$XpDirTree,
        [parameter(ParameterSetName = "Restore")][Switch]$NoXpDirRecurse,
        [switch]$OutputScriptOnly,
        [parameter(ParameterSetName = "Restore")][switch]$VerifyOnly,
        [parameter(ParameterSetName = "Restore")][switch]$MaintenanceSolutionBackup,
        [parameter(ParameterSetName = "Restore", ValueFromPipelineByPropertyname)][hashtable]$FileMapping,
        [parameter(ParameterSetName = "Restore")][switch]$IgnoreLogBackup,
        [parameter(ParameterSetName = "Restore")][switch]$IgnoreDiffBackup,
        [parameter(ParameterSetName = "Restore")][switch]$UseDestinationDefaultDirectories,
        [parameter(ParameterSetName = "Restore")][switch]$ReuseSourceFolderStructure,
        [parameter(ParameterSetName = "Restore")][string]$DestinationFilePrefix = '',
        [parameter(ParameterSetName = "Restore")][string]$RestoredDatabaseNamePrefix,
        [parameter(ParameterSetName = "Restore")][parameter(ParameterSetName = "RestorePage")][switch]$TrustDbBackupHistory,
        [parameter(ParameterSetName = "Restore")][parameter(ParameterSetName = "RestorePage")][int]$MaxTransferSize,
        [parameter(ParameterSetName = "Restore")][parameter(ParameterSetName = "RestorePage")][int]$BlockSize,
        [parameter(ParameterSetName = "Restore")][parameter(ParameterSetName = "RestorePage")][int]$BufferCount,
        [parameter(ParameterSetName = "Restore")][switch]$DirectoryRecurse,
        [switch]$EnableException,
        [parameter(ParameterSetName = "Restore")][string]$StandbyDirectory,
        [parameter(ParameterSetName = "Restore")][switch]$Continue,
        [parameter(ParameterSetName = "Restore")][string]$ExecuteAs,
        [string]$AzureCredential,
        [parameter(ParameterSetName = "Restore")][switch]$ReplaceDbNameInFile,
        [parameter(ParameterSetName = "Restore")][string]$DestinationFileSuffix,
        [parameter(ParameterSetName = "Recovery")][switch]$Recover,
        [parameter(ParameterSetName = "Restore")][switch]$KeepCDC,
        [string]$GetBackupInformation,
        [switch]$StopAfterGetBackupInformation,
        [string]$SelectBackupInformation,
        [switch]$StopAfterSelectBackupInformation,
        [string]$FormatBackupInformation,
        [switch]$StopAfterFormatBackupInformation,
        [string]$TestBackupInformation,
        [switch]$StopAfterTestBackupInformation,
        [parameter(Mandatory, ParameterSetName = "RestorePage")][object]$PageRestore,
        [parameter(Mandatory, ParameterSetName = "RestorePage")][string]$PageRestoreTailFolder,
        [switch]$StopBefore,
        [string]$StopMark,
        [datetime]$StopAfterDate = (Get-Date '01/01/1971'),
        [int]$StatementTimeout = 0
    )
    begin {
        Write-Message -Level InternalComment -Message "Starting"
        Write-Message -Level Debug -Message "Parameters bound: $($PSBoundParameters.Keys -join ", ")"

        #region Validation
        try {
            $RestoreInstance = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database master
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
            return
        }

        if ($RestoreInstance.DatabaseEngineEdition -eq "SqlManagedInstance") {
            Write-Message -Level Verbose -Message "Restore target is a Managed Instance, restricted feature set available"
            $MiParams = ("DestinationDataDirectory", "DestinationLogDirectory", "DestinationFileStreamDirectory", "XpDirTree", "FileMapping", "UseDestinationDefaultDirectories", "ReuseSourceFolderStructure", "DestinationFilePrefix", "StandbyDirecttory", "ReplaceDbNameInFile", "KeepCDC")
            ForEach ($MiParam in $MiParams) {
                if (Test-Bound $MiParam) {
                    # Write-Message -Level Warning "Restoring to a Managed SQL Instance, parameter $MiParm is not supported"
                    Stop-Function -Category InvalidArgument -Message "The parameter $MiParam cannot be used with a Managed SQL Instance"
                    return
                }
            }
        }

        if ($PSCmdlet.ParameterSetName -eq "Restore") {
            $UseDestinationDefaultDirectories = $true
            $paramCount = 0

            if (Test-Bound "FileMapping") {
                $paramCount += 1
            }
            If (Test-Bound "ExecuteAs") {
                if ((Get-DbaLogin -SqlInstance $RestoreInstance -Login $ExecuteAs).count -eq 0) {
                    Stop-Function -Category InvalidArgument -Message "You specified a Login to execute the restore, but the login '$ExecuteAs' does not exist"
                    return
                }
            }
            if (Test-Bound "ReuseSourceFolderStructure") {
                $paramCount += 1
            }
            if (Test-Bound "DestinationDataDirectory") {
                $paramCount += 1
            }
            if ($paramCount -gt 1) {
                Stop-Function -Category InvalidArgument -Message "You've specified incompatible Location parameters. Please only specify one of FileMapping, ReuseSourceFolderStructure or DestinationDataDirectory"
                return
            }
            if (($ReplaceDbNameInFile) -and !(Test-Bound "DatabaseName")) {
                Stop-Function -Category InvalidArgument -Message "To use ReplaceDbNameInFile you must specify DatabaseName"
                return
            }

            if ((Test-Bound "DestinationLogDirectory") -and (Test-Bound "ReuseSourceFolderStructure")) {
                Stop-Function -Category InvalidArgument -Message "The parameters DestinationLogDirectory and UseDestinationDefaultDirectories are mutually exclusive"
                return
            }
            if ((Test-Bound "DestinationLogDirectory") -and -not (Test-Bound "DestinationDataDirectory")) {
                Stop-Function -Category InvalidArgument -Message "The parameter DestinationLogDirectory can only be specified together with DestinationDataDirectory"
                return
            }
            if ((Test-Bound "DestinationFileStreamDirectory") -and (Test-Bound "ReuseSourceFolderStructure")) {
                Stop-Function -Category InvalidArgument -Message "The parameters DestinationFileStreamDirectory and UseDestinationDefaultDirectories are mutually exclusive"
                return
            }
            if ((Test-Bound "DestinationFileStreamDirectory") -and -not (Test-Bound "DestinationDataDirectory")) {
                Stop-Function -Category InvalidArgument -Message "The parameter DestinationFileStreamDirectory can only be specified together with DestinationDataDirectory"
                return
            }
            if ((Test-Bound "ReuseSourceFolderStructure") -and (Test-Bound "UseDestinationDefaultDirectories")) {
                Stop-Function -Category InvalidArgument -Message "The parameters UseDestinationDefaultDirectories and ReuseSourceFolderStructure cannot both be applied "
                return
            }

            if (($null -ne $FileMapping) -or $ReuseSourceFolderStructure -or ($DestinationDataDirectory -ne '')) {
                $UseDestinationDefaultDirectories = $false
            }
            if (($MaxTransferSize % 64kb) -ne 0 -or $MaxTransferSize -gt 4mb) {
                Stop-Function -Category InvalidArgument -Message "MaxTransferSize value must be a multiple of 64kb and no greater than 4MB"
                return
            }
            if ($BlockSize) {
                if ($BlockSize -notin (0.5kb, 1kb, 2kb, 4kb, 8kb, 16kb, 32kb, 64kb)) {
                    Stop-Function -Category InvalidArgument -Message "Block size must be one of 0.5kb,1kb,2kb,4kb,8kb,16kb,32kb,64kb"
                    return
                }
            }
            if ('' -ne $StandbyDirectory) {
                if (!(Test-DbaPath -Path $StandbyDirectory -SqlInstance $RestoreInstance)) {
                    Stop-Function -Message "$SqlServer cannot see the specified Standby Directory $StandbyDirectory" -Target $SqlInstance
                    return
                }
            }
            if ($KeepCDC -and ($NoRecovery -or ('' -ne $StandbyDirectory))) {
                Stop-Function -Category InvalidArgument -Message "KeepCDC cannot be specified with Norecovery or Standby as it needs recovery to work"
                return
            }
            if ($Continue) {
                Write-Message -Message "Called with continue, so assume we have an existing db in norecovery"
                $WithReplace = $True
                $ContinuePoints = Get-RestoreContinuableDatabase -SqlInstance $RestoreInstance
                $LastRestoreType = Get-DbaDbRestoreHistory -SqlInstance $RestoreInstance -Last
            }
            if (!($PSBoundParameters.ContainsKey("DataBasename"))) {
                $PipeDatabaseName = $true
            }
            if ($OutputScriptOnly -and $VerifyOnly) {
                Stop-Function -Category InvalidArgument -Message "The switches OutputScriptOnly and VerifyOnly cannot both be specified at the same time, stopping"
                return
            }
        }

        if ($StatementTimeout -eq 0) {
            Write-Message -Level Verbose -Message "Changing statement timeout to infinity"
        } else {
            Write-Message -Level Verbose -Message "Changing statement timeout to ($StatementTimeout) minutes"
        }
        $RestoreInstance.ConnectionContext.StatementTimeout = ($StatementTimeout * 60)
        #endregion Validation

        if ($UseDestinationDefaultDirectories) {
            $DefaultPath = (Get-DbaDefaultPath -SqlInstance $RestoreInstance)
            $DestinationDataDirectory = $DefaultPath.Data
            $DestinationLogDirectory = $DefaultPath.Log
        }

        $BackupHistory = @()
    }
    process {
        if (Test-FunctionInterrupt) {
            return
        }

        if ($RestoreInstance.VersionMajor -eq 8 -and $true -ne $TrustDbBackupHistory) {
            foreach ($file in $Path) {
                $bh = Get-DbaBackupInformation -SqlInstance $RestoreInstance -Path $file
                $bound = $PSBoundParameters
                $bound['TrustDbBackupHistory'] = $true
                $bound['Path'] = $bh
                Restore-DbaDatabase @bound
            }
            # Flag function interrupt to silently not execute end
            ${__dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r} = $true
            return
        }
        if ($PSCmdlet.ParameterSetName -like "Restore*") {
            if ($PipeDatabaseName -eq $true) {
                $DatabaseName = ''
            }
            Write-Message -message "ParameterSet  = Restore" -Level Verbose
            if ($TrustDbBackupHistory -or $path[0].GetType().ToString() -eq 'Dataplat.Dbatools.Database.BackupHistory') {
                foreach ($f in $path) {
                    Write-Message -Level Verbose -Message "Trust Database Backup History Set"
                    if ("BackupPath" -notin $f.PSObject.Properties.name) {
                        Write-Message -Level Verbose -Message "adding BackupPath - $($_.FullName)"
                        $f = $f | Select-Object *, @{ Name = "BackupPath"; Expression = { $_.FullName } }
                    }
                    if ("DatabaseName" -notin $f.PSObject.Properties.Name) {
                        $f = $f | Select-Object *, @{ Name = "DatabaseName"; Expression = { $_.Database } }
                    }
                    if ("Database" -notin $f.PSObject.Properties.Name) {
                        $f = $f | Select-Object *, @{ Name = "Database"; Expression = { $_.DatabaseName } }
                    }
                    if ("BackupSetGUID" -notin $f.PSObject.Properties.Name) {
                        $f = $f | Select-Object *, @{ Name = "BackupSetGUID"; Expression = { $_.BackupSetID } }
                    }
                    if ($f.BackupPath -like 'http*') {
                        if ('' -ne $AzureCredential) {
                            Write-Message -Message "At least one Azure backup passed in with a credential, assume correct" -Level Verbose
                            Write-Message -Message "Storage Account Identity access means striped backups cannot be restore"
                        } else {
                            if ($f.BackupPath.count -gt 1) {
                                $null = $f.BackupPath[0] -match '(http|https)://[^/]*/[^/]*'
                            } else {
                                $null = $f.BackupPath -match '(http|https)://[^/]*/[^/]*'
                            }
                            if (Get-DbaCredential -SqlInstance $RestoreInstance -Name $matches[0].trim('/') ) {
                                Write-Message -Message "We have a SAS credential to use with $($f.BackupPath)" -Level Verbose
                            } else {
                                Stop-Function -Message "A URL to a backup has been passed in, but no credential can be found to access it"
                                return
                            }
                        }
                    }
                    # Fix #5036 by implementing a deep copy of the FileList
                    $f.FileList = $f.FileList | Select-Object *
                    $BackupHistory += $f | Select-Object *, @{ Name = "ServerName"; Expression = { $_.SqlInstance } }, @{ Name = "BackupStartDate"; Expression = { $_.Start -as [DateTime] } }
                }
            } else {
                $files = @()
                foreach ($f in $Path) {
                    if ($f -is [System.IO.FileSystemInfo]) {
                        $files += $f.FullName
                    } else {
                        $files += $f
                    }
                }
                Write-Message -Level Verbose -Message "Unverified input, full scans - $($files -join ';')"
                if ($BackupHistory.GetType().ToString() -eq 'Dataplat.Dbatools.Database.BackupHistory') {
                    $BackupHistory = @($BackupHistory)
                }
                $parms = @{
                    SqlInstance         = $RestoreInstance
                    SqlCredential       = $SqlCredential
                    Path                = $files
                    DirectoryRecurse    = $DirectoryRecurse
                    MaintenanceSolution = $MaintenanceSolutionBackup
                    IgnoreDiffBackup    = $IgnoreDiffBackup
                    IgnoreLogBackup     = $IgnoreLogBackup
                    AzureCredential     = $AzureCredential
                    NoXpDirRecurse      = $NoXpDirRecurse
                }
                $BackupHistory += Get-DbaBackupInformation @parms
            }
            if ($PSCmdlet.ParameterSetName -eq "RestorePage") {
                if (-not (Test-DbaPath -SqlInstance $RestoreInstance -Path $PageRestoreTailFolder)) {
                    Stop-Function -Message "Instance $RestoreInstance cannot read $PageRestoreTailFolder, cannot proceed" -Target $PageRestoreTailFolder
                    return
                }
                $WithReplace = $true
            }
        } elseif ($PSCmdlet.ParameterSetName -eq "Recovery") {
            Write-Message -Message "$($Database.Count) databases to recover" -level Verbose
            foreach ($Database in $DatabaseName) {
                if ($Database -is [object]) {
                    #We've got an object, try the normal options Database, DatabaseName, Name
                    if ("Database" -in $Database.PSObject.Properties.Name) {
                        [string]$DataBase = $Database.Database
                    } elseif ("DatabaseName" -in $Database.PSObject.Properties.Name) {
                        [string]$DataBase = $Database.DatabaseName
                    } elseif ("Name" -in $Database.PSObject.Properties.Name) {
                        [string]$Database = $Database.name
                    }
                }
                Write-Message -Level Verbose -Message "existence - $($RestoreInstance.Databases[$DataBase].State)"
                if ($RestoreInstance.Databases[$DataBase].State -ne 'Existing') {
                    Write-Message -Message "$Database does not exist on $RestoreInstance" -level Warning
                    continue
                }

                if (@("Restoring", "Normal, Standby") -notcontains $RestoreInstance.Databases[$Database].Status) {
                    Write-Message -Message "$Database on $RestoreInstance state [$($RestoreInstance.Databases[$Database].Status)] is not a valid state. Valid state is Restoring or Standby" -Level Warning
                    continue
                }
                $RestoreComplete = $true
                $RecoverSql = "RESTORE DATABASE [$Database] WITH RECOVERY"
                Write-Message -Message "Recovery Sql Query - $RecoverSql" -level verbose
                try {
                    $RestoreInstance.query($RecoverSql)
                } catch {
                    $RestoreComplete = $False
                    $ExitError = $_.Exception.InnerException
                    Write-Message -Level Warning -Message "Failed to recover $Database on $RestoreInstance, `n $ExitError"
                } finally {
                    [PSCustomObject]@{
                        SqlInstance     = $SqlInstance
                        DatabaseName    = $Database
                        RestoreComplete = $RestoreComplete
                        Scripts         = $RecoverSql
                    }
                }
            }
        }
    }
    end {
        if (Test-FunctionInterrupt) {
            return
        }
        if (($BackupHistory.Database | Sort-Object -Unique).count -gt 1 -and ('' -ne $DatabaseName)) {
            Stop-Function -Message "Multiple Databases' backups passed in, but only 1 name to restore them under. Stopping as cannot work out how to proceed" -Category InvalidArgument
            return
        }
        if ($PSCmdlet.ParameterSetName -like "Restore*") {
            if ($BackupHistory.Count -eq 0 -and $RestoreInstance.VersionMajor -ne 8) {
                Write-Message -Level Warning -Message "No backups passed through. `n This could mean the SQL instance cannot see the referenced files, the file's headers could not be read or some other issue"
                return
            }
            Write-Message -message "Processing DatabaseName - $DatabaseName" -Level Verbose
            $FilteredBackupHistory = @()
            if (Test-Bound -ParameterName GetBackupInformation) {
                Write-Message -Message "Setting $GetBackupInformation to BackupHistory" -Level Verbose
                Set-Variable -Name $GetBackupInformation -Value $BackupHistory -Scope Global
            }
            if ($StopAfterGetBackupInformation) {
                return
            }
            $pathSep = Get-DbaPathSep -Server $RestoreInstance
            $parms = @{
                DataFileDirectory              = $DestinationDataDirectory
                LogFileDirectory               = $DestinationLogDirectory
                DestinationFileStreamDirectory = $DestinationFileStreamDirectory
                DatabaseFileSuffix             = $DestinationFileSuffix
                DatabaseFilePrefix             = $DestinationFilePrefix
                DatabaseNamePrefix             = $RestoredDatabaseNamePrefix
                ReplaceDatabaseName            = $DatabaseName
                Continue                       = $Continue
                ReplaceDbNameInFile            = $ReplaceDbNameInFile
                FileMapping                    = $FileMapping
                PathSep                        = $pathSep
            }
            $BackupHistory = $BackupHistory | Format-DbaBackupInformation @parms

            if (Test-Bound -ParameterName FormatBackupInformation) {
                Set-Variable -Name $FormatBackupInformation -Value $BackupHistory -Scope Global
            }
            if ($StopAfterFormatBackupInformation) {
                return
            }
            if ($VerifyOnly) {
                $FilteredBackupHistory = $BackupHistory
            } else {
                $parms = @{
                    RestoreTime     = $RestoreTime
                    IgnoreLogs      = $IgnoreLogBackups
                    IgnoreDiffs     = $IgnoreDiffBackup
                    ContinuePoints  = $ContinuePoints
                    LastRestoreType = $LastRestoreType
                    DatabaseName    = $DatabaseName
                }
                $FilteredBackupHistory = $BackupHistory | Select-DbaBackupInformation @parms
            }
            if (Test-Bound -ParameterName SelectBackupInformation) {
                Write-Message -Message "Setting $SelectBackupInformation to FilteredBackupHistory" -Level Verbose
                Set-Variable -Name $SelectBackupInformation -Value $FilteredBackupHistory -Scope Global

            }
            if ($StopAfterSelectBackupInformation) {
                return
            }
            try {
                Write-Message -Level Verbose -Message "VerifyOnly = $VerifyOnly"
                $parms = @{
                    SqlInstance      = $RestoreInstance
                    WithReplace      = $WithReplace
                    Continue         = $Continue
                    VerifyOnly       = $VerifyOnly
                    EnableException  = $true
                    OutputScriptOnly = $OutputScriptOnly
                }

                $null = $FilteredBackupHistory | Test-DbaBackupInformation @parms
            } catch {
                Stop-Function -ErrorRecord $_ -Message "Failure" -Continue
            }
            if (Test-Bound -ParameterName TestBackupInformation) {
                Set-Variable -Name $TestBackupInformation -Value $FilteredBackupHistory -Scope Global
            }
            if ($StopAfterTestBackupInformation) {
                return
            }
            $DbVerfied = ($FilteredBackupHistory | Where-Object { $_.IsVerified -eq $True } | Sort-Object -Property Database -Unique).Database -join ','
            Write-Message -Message "$DbVerfied passed testing" -Level Verbose
            if ((@($FilteredBackupHistory | Where-Object { $_.IsVerified -eq $True })).count -lt $FilteredBackupHistory.count) {
                $DbUnVerified = ($FilteredBackupHistory | Where-Object { $_.IsVerified -eq $False } | Sort-Object -Property Database -Unique).Database -join ','
                Stop-Function -Message "Database $DbUnverified unable to be restored, see warnings for details"
            }
            If ($PSCmdlet.ParameterSetName -eq "RestorePage") {
                if (($FilteredBackupHistory.Database | Sort-Object -Unique | Measure-Object).count -ne 1) {
                    Stop-Function -Message "Must only 1 database passed in for Page Restore. Sorry"
                    return
                } else {
                    $WithReplace = $false
                }
            }
            Write-Message -Message "Passing in to restore" -Level Verbose

            if ($PSCmdlet.ParameterSetName -eq "RestorePage" -and $RestoreInstance.Edition -notlike '*Enterprise*') {
                Write-Message -Message "Taking Tail log backup for page restore for non-Enterprise" -Level Verbose
                $TailBackup = Backup-DbaDatabase -SqlInstance $RestoreInstance -Database $DatabaseName -Type Log -BackupDirectory $PageRestoreTailFolder -NoRecovery -CopyOnly
            }
            try {
                $parms = @{
                    SqlInstance      = $RestoreInstance
                    WithReplace      = $WithReplace
                    RestoreTime      = $RestoreTime
                    StandbyDirectory = $StandbyDirectory
                    NoRecovery       = $NoRecovery
                    Continue         = $Continue
                    OutputScriptOnly = $OutputScriptOnly
                    BlockSize        = $BlockSize
                    MaxTransferSize  = $MaxTransferSize
                    BufferCount      = $Buffercount
                    KeepCDC          = $KeepCDC
                    VerifyOnly       = $VerifyOnly
                    PageRestore      = $PageRestore
                    AzureCredential  = $AzureCredential
                    KeepReplication  = $KeepReplication
                    StopMark         = $StopMark
                    StopAfterDate    = $StopAfterDate
                    StopBefore       = $StopBefore
                    ExecuteAs        = $ExecuteAs
                    EnableException  = $true
                }
                $FilteredBackupHistory | Where-Object { $_.IsVerified -eq $true } | Invoke-DbaAdvancedRestore @parms
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -Target $RestoreInstance
            }
            if ($PSCmdlet.ParameterSetName -eq "RestorePage") {
                if ($RestoreInstance.Edition -like '*Enterprise*') {
                    Write-Message -Message "Taking Tail log backup for page restore for Enterprise" -Level Verbose
                    $TailBackup = Backup-DbaDatabase -SqlInstance $RestoreInstance -Database $DatabaseName -Type Log -BackupDirectory $PageRestoreTailFolder -NoRecovery -CopyOnly
                }
                Write-Message -Message "Restoring Tail log backup for page restore" -Level Verbose
                $parms = @{
                    SqlInstance          = $RestoreInstance
                    TrustDbBackupHistory = $true
                    NoRecovery           = $true
                    OutputScriptOnly     = $OutputScriptOnly
                    BlockSize            = $BlockSize
                    MaxTransferSize      = $MaxTransferSize
                    BufferCount          = $Buffercount
                    Continue             = $true
                }
                $TailBackup | Restore-DbaDatabase @parms
                Restore-DbaDatabase -SqlInstance $RestoreInstance -Recover -DatabaseName $DatabaseName -OutputScriptOnly:$OutputScriptOnly
            }
            # refresh the SMO as we probably used T-SQL, but only if we already got a SMO
            if ($SqlInstance.InputObject -is [Microsoft.SqlServer.Management.Smo.Server]) {
                $SqlInstance.InputObject.Databases.Refresh()
            }
        }
    }
}