function Restore-DbaDatabase {
    <#
    .SYNOPSIS
        Restores a SQL Server Database from a set of backupfiles

    .DESCRIPTION
        Upon being passed a list of potential backups files this command will scan the files, select those that contain SQL Server
        backup sets. It will then filter those files down to a set that can perform the requested restore, checking that we have a
        full restore chain to the point in time requested by the caller.

        The function defaults to working on a remote instance. This means that all paths passed in must be relative to the remote instance.
        XpDirTree will be used to perform the file scans


        Various means can be used to pass in a list of files to be considered. The default is to non recursively scan the folder
        passed in.

    .PARAMETER Path
        Path to SQL Server backup files.

        Paths passed in as strings will be scanned using the desired method, default is a non recursive folder scan
        Accepts multiple paths separated by ','

        Or it can consist of FileInfo objects, such as the output of Get-ChildItem or Get-Item. This allows you to work with
        your own filestructures as needed

    .PARAMETER SqlInstance
        The SQL Server instance to restore to.

    .PARAMETER SqlCredential
        Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted.

    .PARAMETER DatabaseName
        Name to restore the database under.
        Only works with a single database restore. If multiple database are found in the provided paths then we will exit

    .PARAMETER DestinationDataDirectory
        Path to restore the SQL Server backups to on the target instance.
        If only this parameter is specified, then all database files (data and log) will be restored to this location

    .PARAMETER DestinationLogDirectory
        Path to restore the database log files to.
        This parameter can only be specified alongside DestinationDataDirectory.

    .PARAMETER DestinationFileStreamDirectory
        Path to restore FileStream data to
        This parameter can only be specified alongside DestinationDataDirectory

    .PARAMETER RestoreTime
        Specify a DateTime object to which you want the database restored to. Default is to the latest point  available in the specified backups

    .PARAMETER NoRecovery
        Indicates if the databases should be recovered after last restore. Default is to recover

    .PARAMETER WithReplace
        Switch indicated is the restore is allowed to replace an existing database.

    .PARAMETER XpDirTree
        Switch that indicated file scanning should be performed by the SQL Server instance using xp_dirtree
        This will scan recursively from the passed in path
        You must have sysadmin role membership on the instance for this to work.

    .PARAMETER OutputScriptOnly
        Switch indicates that ONLY T-SQL scripts should be generated, no restore takes place

    .PARAMETER VerifyOnly
        Switch indicate that restore should be verified

    .PARAMETER MaintenanceSolutionBackup
        Switch to indicate the backup files are in a folder structure as created by Ola Hallengreen's maintenance scripts.
        This swith enables a faster check for suitable backups. Other options require all files to be read first to ensure we have an anchoring full backup. Because we can rely on specific locations for backups performed with OlaHallengren's backup solution, we can rely on file locations.

    .PARAMETER FileMapping
        A hashtable that can be used to move specific files to a location.
        $FileMapping = @{'DataFile1'='c:\restoredfiles\Datafile1.mdf';'DataFile3'='d:\DataFile3.mdf'}
        And files not specified in the mapping will be restored to their original location
        This Parameter is exclusive with DestinationDataDirectory

    .PARAMETER IgnoreLogBackup
        This switch tells the function to ignore transaction log backups. The process will restore to the latest full or differential backup point only

    .PARAMETER useDestinationDefaultDirectories
        Switch that tells the restore to use the default Data and Log locations on the target server. If they don't exist, the function will try to create them

    .PARAMETER ReuseSourceFolderStructure
        By default, databases will be migrated to the destination Sql Server's default data and log directories. You can override this by specifying -ReuseSourceFolderStructure.
        The same structure on the SOURCE will be kept exactly, so consider this if you're migrating between different versions and use part of Microsoft's default Sql structure (MSSql12.INSTANCE, etc)

        *Note, to reuse destination folder structure, specify -WithReplace

    .PARAMETER DestinationFilePrefix
        This value will be prefixed to ALL restored files (log and data). This is just a simple string prefix. If you want to perform more complex rename operations then please use the FileMapping parameter

        This will apply to all file move options, except for FileMapping

    .PARAMETER DestinationFileSuffix
        This value will be suffixed to ALL restored files (log and data). This is just a simple string suffix. If you want to perform more complex rename operations then please use the FileMapping parameter

        This will apply to all file move options, except for FileMapping

    .PARAMETER RestoredDatababaseNamePrefix
        A string which will be prefixed to the start of the restore Database's Name
        Useful if restoring a copy to the same sql server for testing.

    .PARAMETER TrustDbBackupHistory
        This switch can be used when piping the output of Get-DbaBackupHistory or Backup-DbaDatabase into this command.
        It allows the user to say that they trust that the output from those commands is correct, and skips the file header read portion of the process. This means a faster process, but at the risk of not knowing till halfway through the restore that something is wrong with a file.

    .PARAMETER MaxTransferSize
        Parameter to set the unit of transfer. Values must be a multiple by 64kb

    .PARAMETER Blocksize
        Specifies the block size to use. Must be one of 0.5kb,1kb,2kb,4kb,8kb,16kb,32kb or 64kb
        Can be specified in bytes
        Refer to https://msdn.microsoft.com/en-us/library/ms178615.aspx for more detail

    .PARAMETER BufferCount
        Number of I/O buffers to use to perform the operation.
        Refer to https://msdn.microsoft.com/en-us/library/ms178615.aspx for more detail

    .PARAMETER XpNoRecurse
        If specified, prevents the XpDirTree process from recursing (its default behaviour)

    .PARAMETER DirectoryRecurse
        If specified the specified directory will be recursed into

    .PARAMETER Continue
        If specified we will to attempt to recover more transaction log backups onto  database(s) in Recovering or Standby states

    .PARAMETER StandbyDirectory
        If a directory is specified the database(s) will be restored into a standby state, with the standby file placed into this directory (which must exist, and be writable by the target Sql Server instance)

    .PARAMETER AzureCredential
        The name of the SQL Server credential to be used if restoring from an Azure hosted backup

    .PARAMETER ReplaceDbNameInFile
        If switch set and occurence of the original database's name in a data or log file will be replace with the name specified in the Databasename paramter

    .PARAMETER Recover
        If set will perform recovery on the indicated database

    .PARAMETER AllowContinue
        By default, Restore-DbaDatabase will stop restoring any databases if it comes across an error.
        Use this switch to enable it to restore all databases without issues.

    .PARAMETER GetBackupInformation
        Passing a string value into this parameter will cause a global variable to be created holding the output of Get-DbaBackupInformation

    .PARAMETER SelectBackupInformation
        Passing a string value into this parameter will cause a global variable to be created holding the output of Select-DbaBackupInformation

    .PARAMETER FormatBackupInformation
        Passing a string value into this parameter will cause a global variable to be created holding the output of Format-DbaBackupInformation

    .PARAMETER TestBackupInformation
        Passing a string value into this parameter will cause a global variable to be created holding the output of Test-DbaBackupInformation

    .PARAMETER StopAfterGetBackupInformation
        Switch which will cause the function to exit after returning GetBackupInformation

    .PARAMETER StopAfterSelectBackupInformation
        Switch which will cause the function to exit after returning SelectBackupInformation

    .PARAMETER StopAfterFormatBackupInformation
         Switch which will cause the function to exit after returning FormatBackupInformation

    .PARAMETER StopAfterTestBackupInformation
         Switch which will cause the function to exit after returning TestBackupInformation

    .PARAMETER StatementTimeOut
        Timeout in minutes. Defaults to infinity (restores can take a while.)

    .PARAMETER KeepCDC
        Indicates whether CDC information should be restored as part of the database

    .PARAMETER PageRestore
        Passes in an object from Get-DbaSuspectPages containing suspect pages from a single database.
        Setting this Parameter will cause an Online Page restore if the target Instance is Enterprise Edition, or offline if not.
        This will involve taking a tail log backup, so you must check your restore chain once it has completed

    .PARAMETER PageRestoreTailFolder
        This parameter passes in a location for the tail log backup required for page level restore

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Confirm
        Prompts to confirm certain actions

    .PARAMETER WhatIf
        Shows what would happen if the command would execute, but does not actually perform the command

    .EXAMPLE
        Restore-DbaDatabase -SqlInstance server1\instance1 -Path \\server2\backups

        Scans all the backup files in \\server2\backups, filters them and restores the database to server1\instance1

    .EXAMPLE
        Restore-DbaDatabase -SqlInstance server1\instance1 -Path \\server2\backups -MaintenanceSolutionBackup -DestinationDataDirectory c:\restores

        Scans all the backup files in \\server2\backups$ stored in an Ola Hallengren style folder structure,
        filters them and restores the database to the c:\restores folder on server1\instance1

    .EXAMPLE
        Get-ChildItem c:\SQLbackups1\, \\server\sqlbackups2 | Restore-DbaDatabase -SqlInstance server1\instance1

        Takes the provided files from multiple directories and restores them on  server1\instance1

    .EXAMPLE
        $RestoreTime = Get-Date('11:19 23/12/2016')
        Restore-DbaDatabase -SqlInstance server1\instance1 -Path \\server2\backups -MaintenanceSolutionBackup -DestinationDataDirectory c:\restores -RestoreTime $RestoreTime

        Scans all the backup files in \\server2\backups stored in an Ola Hallengren style folder structure,
        filters them and restores the database to the c:\restores folder on server1\instance1 up to 11:19 23/12/2016

    .EXAMPLE
        Restore-DbaDatabase -SqlInstance server1\instance1 -Path \\server2\backups -DestinationDataDirectory c:\restores -OutputScriptOnly | Select-Object -ExpandProperty Tsql | Out-File -Filepath c:\scripts\restore.sql

        Scans all the backup files in \\server2\backups stored in an Ola Hallengren style folder structure,
        filters them and generate the T-SQL Scripts to restore the database to the latest point in time,
        and then stores the output in a file for later retrieval

    .EXAMPLE
        Restore-DbaDatabase -SqlInstance server1\instance1 -Path c:\backups -DestinationDataDirectory c:\DataFiles -DestinationLogDirectory c:\LogFile

        Scans all the files in c:\backups and then restores them onto the SQL Server Instance server1\instance1, placing data files
        c:\DataFiles and all the log files into c:\LogFiles

    .EXAMPLE
        Restore-DbaDatabase -SqlInstance server1\instance1 -Path http://demo.blob.core.windows.net/backups/dbbackup.bak -AzureCredential MyAzureCredential

        Will restore the backup held at  http://demo.blob.core.windows.net/backups/dbbackup.bak to server1\instance1. The connection to Azure will be made using the
        credential MyAzureCredential held on instance Server1\instance1

    .EXAMPLE
        $File = Get-ChildItem c:\backups, \\server1\backups -recurse
        $File | Restore-DbaDatabase -SqlInstance Server1\Instance -useDestinationDefaultDirectories

        This will take all of the files found under the folders c:\backups and \\server1\backups, and pipeline them into
        Restore-DbaDatabase. Restore-DbaDatabase will then scan all of the files, and restore all of the databases included
        to the latest point in time covered by their backups. All data and log files will be moved to the default SQL Server
        folder for those file types as defined on the target instance.

    .EXAMPLE
        $files = Get-ChildItem C:\dbatools\db1

        #Restore database to a point in time
        $files | Restore-DbaDatabase -SqlInstance server\instance1 `
                    -DestinationFilePrefix prefix -DatabaseName Restored  `
                    -RestoreTime (get-date "14:58:30 22/05/2017") `
                    -NoRecovery -WithReplace -StandbyDirectory C:\dbatools\standby

        #It's in standby so we can peek at it
        Invoke-Sqlcmd2 -ServerInstance server\instance1 -Query "select top 1 * from Restored.dbo.steps order by dt desc"

        #Not quite there so let's roll on a bit:
        $files | Restore-DbaDatabase -SqlInstance server\instance1 `
                    -DestinationFilePrefix prefix -DatabaseName Restored `
                    -continue -WithReplace -RestoreTime (get-date "15:09:30 22/05/2017") `
                    -StandbyDirectory C:\dbatools\standby

        Invoke-Sqlcmd2 -ServerInstance server\instance1 -Query "select top 1 * from restored.dbo.steps order by dt desc"

        Restore-DbaDatabase -SqlInstance server\instance1 `
                    -DestinationFilePrefix prefix -DatabaseName Restored `
                    -continue -WithReplace

        In this example we step through the backup files held in c:\dbatools\db1 folder.
        First we restore the database to a point in time in standby mode. This means we can check some details in the databases
        We then roll it on a further 9 minutes to perform some more checks
        And finally we continue by rolling it all the way forward to the latest point in the backup.
        At each step, only the log files needed to roll the database forward are restored.

    .EXAMPLE
        Restore-DbaDatabase -SqlInstance server\instance1 -Path c:\backups -DatabaseName example1 -WithNoRecovery
        Restore-DbaDatabase -SqlInstance server\instance1 -Recover -DatabaseName example1

    .EXAMPLE
        $SuspectPage = Get-DbaSuspectPage -SqlInstance server\instance1 -Database ProdFinance
        Get-DbaBackupHistory - SqlInstance server\instance1 -Database -ProdFinance -Last | Restore-DbaDatabase -PageRestore $SuspectPage -PageRestoreTailFolder c:\temp -TrustDbBackupHistory -AllowContinues

        Gets a list of Suspect Pages using Get-DbaSuspectPage. The uses Get-DbaBackupHistory and Restore-DbaDatabase to perform a restore of the suspect pages and bring them up to date
        If server\instance1 is Enterprise edition this will be done online, if not it will be performed offline
        AllowContinue is required to make sure we cope with existing files

    .NOTES
        Tags: DisasterRecovery, Backup, Restore
        Author: Stuart Moore (@napalmgram), stuart-moore.com

        dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
        Copyright (C) 2016 Chrissy LeMaire
        License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
#>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = "Restore")]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = "Restore")]
        [parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = "RestorePage")]
        [object[]]$Path,
        [parameter(Mandatory = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(ValueFromPipeline = $true)]
        [Alias("Name")]
        [object[]]$DatabaseName,
        [parameter(ParameterSetName = "Restore")]
        [String]$DestinationDataDirectory,
        [parameter(ParameterSetName = "Restore")]
        [String]$DestinationLogDirectory,
        [parameter(ParameterSetName = "Restore")]
        [String]$DestinationFileStreamDirectory,
        [parameter(ParameterSetName = "Restore")]
        [DateTime]$RestoreTime = (Get-Date).AddYears(1),
        [parameter(ParameterSetName = "Restore")]
        [switch]$NoRecovery,
        [parameter(ParameterSetName = "Restore")]
        [switch]$WithReplace,
        [parameter(ParameterSetName = "Restore")]
        [Switch]$XpDirTree,
        [switch]$OutputScriptOnly,
        [parameter(ParameterSetName = "Restore")]
        [switch]$VerifyOnly,
        [parameter(ParameterSetName = "Restore")]
        [switch]$MaintenanceSolutionBackup,
        [parameter(ParameterSetName = "Restore")]
        [hashtable]$FileMapping,
        [parameter(ParameterSetName = "Restore")]
        [switch]$IgnoreLogBackup,
        [parameter(ParameterSetName = "Restore")]
        [switch]$useDestinationDefaultDirectories,
        [parameter(ParameterSetName = "Restore")]
        [switch]$ReuseSourceFolderStructure,
        [parameter(ParameterSetName = "Restore")]
        [string]$DestinationFilePrefix = '',
        [parameter(ParameterSetName = "Restore")]
        [string]$RestoredDatababaseNamePrefix,
        [parameter(ParameterSetName = "Restore")]
        [parameter(ParameterSetName = "RestorePage")]
        [switch]$TrustDbBackupHistory,
        [parameter(ParameterSetName = "Restore")]
        [parameter(ParameterSetName = "RestorePage")]
        [int]$MaxTransferSize,
        [parameter(ParameterSetName = "Restore")]
        [parameter(ParameterSetName = "RestorePage")]
        [int]$BlockSize,
        [parameter(ParameterSetName = "Restore")]
        [parameter(ParameterSetName = "RestorePage")]
        [int]$BufferCount,
        [parameter(ParameterSetName = "Restore")]
        [switch]$DirectoryRecurse,
        [switch]$EnableException ,
        [parameter(ParameterSetName = "Restore")]
        [string]$StandbyDirectory,
        [parameter(ParameterSetName = "Restore")]
        [switch]$Continue,
        [string]$AzureCredential,
        [parameter(ParameterSetName = "Restore")]
        [switch]$ReplaceDbNameInFile,
        [parameter(ParameterSetName = "Restore")]
        [string]$DestinationFileSuffix,
        [parameter(ParameterSetName = "Recovery")]
        [switch]$Recover,
        [parameter(ParameterSetName = "Restore")]
        [switch]$KeepCDC,
        [switch]$AllowContinue,
        [string]$GetBackupInformation,
        [switch]$StopAfterGetBackupInformation,
        [string]$SelectBackupInformation,
        [switch]$StopAfterSelectBackupInformation,
        [string]$FormatBackupInformation,
        [switch]$StopAfterFormatBackupInformation,
        [string]$TestBackupInformation,
        [switch]$StopAfterTestBackupInformation,
        [parameter(Mandatory = $true, ParameterSetName = "RestorePage")]
        [object]$PageRestore,
        [parameter(Mandatory = $true, ParameterSetName = "RestorePage")]
        [string]$PageRestoreTailFolder,
        [int]$StatementTimeout = 0

    )
    begin {
        Write-Message -Level InternalComment -Message "Starting"
        Write-Message -Level Debug -Message "Parameters bound: $($PSBoundParameters.Keys -join ", ")"
        #[string]$DatabaseName = 'testparam'
        #region Validation
        try {
            $RestoreInstance = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        }
        catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            return
        }
        if ($PSCmdlet.ParameterSetName -eq "Restore") {
            $useDestinationDefaultDirectories = $true
            $paramCount = 0

            if (!(Test-Bound "AllowContinue") -and $true -ne $AllowContinue) {
                $AllowContinue = $false
            }
            if (Test-Bound "FileMapping") {
                $paramCount += 1
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
            if (($null -ne $FileMapping) -or $ReuseSourceFolderStructure -or ($DestinationDataDirectory -ne '')) {
                $useDestinationDefaultDirectories = $false
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
                if (!(Test-DbaSqlPath -Path $StandbyDirectory -SqlInstance $RestoreInstance)) {
                    Stop-Function -Message "$SqlSever cannot see the specified Standby Directory $StandbyDirectory" -Target $SqlInstance
                    return
                }
            }
            if ($KeepCDC -and ($NoRecovery -or ('' -ne $StandbyDirectory))) {
                Stop-Function -Category InvalidArgument -Message "KeepCDC cannot be specified with Norecovery or Standby as it needs recovery to work"
                return
            }
            if ($Continue) {
                $ContinuePoints = Get-RestoreContinuableDatabase -SqlInstance $RestoreInstance
                #$WithReplace = $true
                #$ContinuePoints
            }
            if (!($PSBoundParameters.ContainsKey("DataBasename"))) {
                $PipeDatabaseName = $true
            }

        }



        # changing statement timeout to $StatementTimeout
        if ($StatementTimeout -eq 0) {
            Write-Message -Level Verbose -Message "Changing statement timeout to infinity"
        }
        else {
            Write-Message -Level Verbose -Message "Changing statement timeout to ($StatementTimeout) minutes"
        }
        $RestoreInstance.ConnectionContext.StatementTimeout = ($StatementTimeout * 60)
        #endregion Validation

        $isLocal = [dbavalidate]::IsLocalHost($SqlInstance.ComputerName)

        if ($useDestinationDefaultDirectories) {
            $DefaultPath = (Get-DbaDefaultPath -SqlInstance $RestoreInstance)
            $DestinationDataDirectory = $DefaultPath.Data
            $DestinationLogDirectory = $DefaultPath.Log
        }

        $BackupHistory = @()
        #$useDestinationDefaultDirectories = $true
    }
    process {
        if (Test-FunctionInterrupt) { return }
        if ($PSCmdlet.ParameterSetName -like "Restore*") {
            if ($PipeDatabaseName -eq $true) {$DatabaseName = ''}
            Write-Message -message "ParameterSet  = Restore" -Level Verbose
            foreach ($f in $path) {
                if ($TrustDbBackupHistory -or $f.GetType().ToString() -eq 'Sqlcollaborative.Dbatools.Database.BackupHistory') {
                    Write-Message -Level Verbose -Message "Trust Database Backup History Set"
                    if ("BackupPath" -notin $f.PSobject.Properties.name) {
                        Write-Message -Level Verbose -Message "adding BackupPath - $($_.Fullname)"
                        $f = $f | Select-Object *, @{ Name = "BackupPath"; Expression = { $_.FullName } }
                    }
                    if ("DatabaseName" -notin $f.PSobject.Properties.name) {
                        $f = $f | Select-Object *, @{ Name = "DatabaseName"; Expression = { $_.Database } }
                    }
                    if ("Database" -notin $f.PSobject.Properties.name) {
                        $f = $f | Select-Object *, @{ Name = "Database"; Expression = { $_.DatabaseName } }
                    }
                    if ("Type" -notin $f.PSobject.Properties.name) {
                        #$f = $f | Select-Object *,  @{Name="Type";Expression={"Full"}}
                    }
                    if ("BackupSetGUID" -notin $f.PSobject.Properties.name) {
                        #This line until Get-DbaBackupHistory gets fixed
                        #$f = $f | Select-Object *, @{ Name = "BackupSetGUID"; Expression = { $_.BackupSetupID } }
                        #This one once it's sorted:
                        $f = $f | Select-Object *, @{Name = "BackupSetGUID"; Expression = {$_.BackupSetID}}
                    }
                    if ($f.BackupPath -like 'http*' -and '' -eq $AzureCredential) {
                        Stop-Function -Message "At least one Azure backup passed in, and no Credential supplied. Stopping"
                        return
                    }

                    $BackupHistory += $F | Select-Object *, @{ Name = "ServerName"; Expression = { $_.SqlInstance } }, @{ Name = "BackupStartDate"; Expression = { $_.Start -as [DateTime] } }

                }
                else {
                    Write-Message -Level Verbose -Message "Unverified input, full scans - $f"
                    if ($f -is [System.IO.FileSystemInfo]) {
                        $f = $f.fullname
                    }
                    $BackupHistory += $f | Get-DbaBackupInformation -SqlInstance $RestoreInstance -DirectoryRecurse:$DirectoryRecurse -MaintenanceSolution:$MaintenanceSolutionBackup -IgnoreLogBackup:$IgnoreLogBackup
                }
            }
            if ($PSCmdlet.ParameterSetName -eq "RestorePage") {
                if (-not (Test-DbaSqlPath -SqlInstance $RestoreInstance -Path $PageRestoreTailFolder)) {
                    Stop-Function -Message "Instance $RestoreInstance cannot read $PageRestoreTailFolder, cannot proceed" -Target $PageRestoreTailFolder
                    return
                }
                $WithReplace = $true
            }
        }
        elseif ($PSCmdlet.ParameterSetName -eq "Recovery") {
            Write-Message -Message "$($Database.count) databases to recover" -level Verbose
            ForEach ($DataBase in $DatabaseName) {
                if ($database -is [object]) {
                    #We've got an object, try the normal options Database, DatabaseName, Name
                    if ("Database" -in $Database.PSobject.Properties.name) {
                        [string]$DataBase = $database.Database
                    }
                    elseif ("DatabaseName" -in $Database.PSobject.Properties.name) {
                        [string]$DataBase = $database.DatabaseName
                    }
                    elseif ("Name" -in $Database.PSobject.Properties.name) {
                        [string]$DataBase = $database.name
                    }
                }
                Write-Verbose "existence - $($RestoreInstance.Databases[$DataBase].State)"
                if ($RestoreInstance.Databases[$DataBase].State -ne 'Existing') {
                    Write-Message -Message "$Database does not exist on $RestoreInstance" -level Warning
                    Continue

                }
                if ($RestoreInstance.Databases[$Database].Status -ne "Restoring") {
                    Write-Message -Message "$Database on $RestoreInstance is not in a Restoring State" -Level Warning
                    Continue

                }
                $RestoreComplete = $true
                $RecoverSql = "RESTORE DATABASE $Database WITH RECOVERY"
                Write-Message -Message "Recovery Sql Query - $RecoverSql" -level verbose
                Try {
                    $RestoreInstance.query($RecoverSql)
                }
                Catch {
                    $RestoreComplete = $False
                    $ExitError = $_.Exception.InnerException
                    Write-Message -Level Warning -Message "Failed to recover $Database on $RestoreInstance, `n $ExitError"
                }
                Finally {
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
        if (Test-FunctionInterrupt) { return }
        if ($PSCmdlet.ParameterSetName -like "Restore*") {
            Write-Message -message "Processing DatabaseName - $DatabaseName" -Level Verbose
            $FilteredBackupHistory = @()
            if (Test-Bound -ParameterName GetBackupInformation) {
                Write-Message -Message "Setting $GetBackupInformation to BackupHistory" -Level Verbose
                Set-Variable -Name $GetBackupInformation -Value $BackupHistory -Scope Global
            }
            if ($StopAfterGetBackupInformation) {
                return
            }

            $FilteredBackupHistory = $BackupHistory | Select-DbaBackupInformation -RestoreTime $RestoreTime -IgnoreLogs:$IgnoreLogBackups -ContinuePoints $ContinuePoints

            if ( Test-Bound -ParameterName SelectBackupInformation) {
                Write-Message -Message "Setting $SelectBackupInformation to FilteredBackupHistory" -Level Verbose
                Set-Variable -Name $SelectBackupInformation -Value $FilteredBackupHistory -Scope Global

            }
            if ($StopAfterSelectBackupInformation) {
                return
            }

            $null = $FilteredBackupHistory | Format-DbaBackupInformation -DataFileDirectory $DestinationDataDirectory -LogFileDirectory $DestinationLogDirectory -DestinationFileStreamDirectory $DestinationFileStreamDirectory -DatabaseFileSuffix $DestinationFileSuffix -DatabaseFilePrefix $DestinationFilePrefix -DatabaseNamePrefix $RestoredDatababaseNamePrefix -ReplaceDatabaseName $DatabaseName -Continue:$Continue -ReplaceDbNameInFile:$ReplaceDbNameInFile -FileMapping $FileMapping

            if ( Test-Bound -ParameterName FormatBackupInformation) {
                Set-Variable -Name $FormatBackupInformation -Value $FilteredBackupHistory -Scope Global
            }
            if ($StopAfterFormatBackupInformation) {
                return
            }
            Write-Message -Level Verbose -Message "VerifyOnly = $VerifyOnly"
            $null = $FilteredBackupHistory | Test-DbaBackupInformation -SqlInstance $RestoreInstance  -WithReplace:$WithReplace -Continue:$Continue -VerifyOnly:$VerifyOnly

            if ( Test-Bound -ParameterName TestBackupInformation) {
                Set-Variable -Name $TestBackupInformation -Value $FilteredBackupHistory -Scope Global
            }
            if ($StopAfterTestBackupInformation) {
                return
            }
            $DbVerfied = ($FilteredBackupHistory | Where-Object {$_.IsVerified -eq $True} | Select-Object -Property Database -Unique).Database -join ','
            Write-Message -Message "$DbVerfied passed testing" -Level Verbose

            if (($FilteredBackupHistory | Where-Object {$_.IsVerified -eq $True}).count -lt $FilteredBackupHistory.count) {
                $DbUnVerified = ($FilteredBackupHistory | Where-Object {$_.IsVerified -eq $False} | Select-Object -Property Database -Unique).Database -join ','
                if ($AllowContinue) {
                    Write-Message -Message "$DbUnverified failed testing, AllowContinue set" -Level Verbose
                }
                else {
                    Stop-Function -Message "$DbUnverified failed testing, AllowContinue not set, exiting"
                    return
                }
            }

            If ($PSCmdlet.ParameterSetName -eq "RestorePage") {
                if (($FilteredBackupHistory.Database | select-Object -unique | Measure-Object).count -ne 1) {
                    Stop-Function -Message "Must only 1 database passed in for Page Restore. Sorry"
                    return
                }
                else {
                    $WithReplace = $false
                    $PageDb = ($FilteredBackupHistory.Database | select-Object -unique).Database
                }
            }
            Write-Message -Message "Passing in to restore" -Level Verbose
            if ($PSCmdlet.ParameterSetName -eq "RestorePage" -and $RestoreInstance.Edition -notlike '*Enterprise*') {
                Write-Message -Message "Taking Tail log backup for page restore for non-Enterprise" -Level Verbose
                $TailBackup = Backup-DbaDatabase -SqlInstance $RestoreInstance -Database $DatabaseName -Type Log -BackupDirectory $PageRestoreTailFolder -Norecovery -CopyOnly
            }
            $FilteredBackupHistory | Where-Object {$_.IsVerified -eq $true} | Invoke-DbaAdvancedRestore -SqlInstance $RestoreInstance -WithReplace:$WithReplace -RestoreTime $RestoreTime -StandbyDirectory $StandbyDirectory -NoRecovery:$NoRecovery -Continue:$Continue -OutputScriptOnly:$OutputScriptOnly -BlockSize $BlockSize -MaxTransferSize $MaxTransferSize -Buffercount $Buffercount -KeepCDC:$KeepCDC -VerifyOnly:$VerifyOnly -PageRestore $PageRestore
            if ($PSCmdlet.ParameterSetName -eq "RestorePage" ) {
                if ($RestoreInstace.Edition -like '*Enterprise*') {
                    Write-Message -Message "Taking Tail log backup for page restore for Enterprise" -Level Verbose
                    $TailBackup = Backup-DbaDatabase -SqlInstance $RestoreInstance -Database $DatabaseName -Type Log -BackupDirectory $PageRestoreTailFolder -Norecovery -CopyOnly
                }
                Write-Message -Message "Restoring Tail log backup for page restore" -Level Verbose
                $TailBackup | Restore-DbaDatabase -SqlInstance $RestoreInstance -TrustDbBackupHistory -NoRecovery -OutputScriptOnly:$OutputScriptOnly -BlockSize $BlockSize -MaxTransferSize $MaxTransferSize -Buffercount $Buffercount -Continue
                Restore-DbaDatabase -SqlInstance $RestoreInstance -Recover -Database $DatabaseName -OutputScriptOnly:$OutputScriptOnly
            }

        }
    }
}