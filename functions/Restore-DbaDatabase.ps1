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
	
	.PARAMETER	Continue
		If specified we will to attempt to recover more transaction log backups onto  database(s) in Recovering or Standby states

	.PARAMETER StandbyDirectory
		If a directory is specified the database(s) will be restored into a standby state, with the standby file placed into this directory (which must exist, and be writable by the target Sql Server instance)

	.PARAMETER AzureCredential
		The name of the SQL Server credential to be used if restoring from an Azure hosted backup

    .PARAMETER ReplaceDbNameInFile
        If switch set and occurence of the original database's name in a data or log file will be replace with the name specified in the Databasename paramter
    
    .PARAMETER Recover
        If set will perform recovery on the indicated database

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
        to the latest point in time covered by their backups. All data and log files will be moved to the default SQL Sever
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

    .NOTES
        Tags: DisasterRecovery, Backup, Restore
        Author: Stuart Moore (@napalmgram), stuart-moore.com
        
        dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
        Copyright (C) 2016 Chrissy LeMaire
        License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0 
#>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName="Restore")]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName="Restore")]
        [object[]]$Path,
        [parameter(Mandatory = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(ValueFromPipeline = $true)]
        [Alias("Name")]
        [object[]]$DatabaseName,
        [parameter(ParameterSetName="Restore")]
        [String]$DestinationDataDirectory,
        [parameter(ParameterSetName="Restore")]
        [String]$DestinationLogDirectory,
        [parameter(ParameterSetName="Restore")]
        [DateTime]$RestoreTime = (Get-Date).addyears(1),
        [parameter(ParameterSetName="Restore")]
        [switch]$NoRecovery,
        [parameter(ParameterSetName="Restore")]
        [switch]$WithReplace,
        [parameter(ParameterSetName="Restore")]
        [Switch]$XpDirTree,
        [switch]$OutputScriptOnly,
        [parameter(ParameterSetName="Restore")]
        [switch]$VerifyOnly,
        [parameter(ParameterSetName="Restore")]
        [switch]$MaintenanceSolutionBackup,
        [parameter(ParameterSetName="Restore")]
        [hashtable]$FileMapping,
        [parameter(ParameterSetName="Restore")]
        [switch]$IgnoreLogBackup,
        [parameter(ParameterSetName="Restore")]
        [switch]$useDestinationDefaultDirectories,
        [parameter(ParameterSetName="Restore")]
        [switch]$ReuseSourceFolderStructure,
        [parameter(ParameterSetName="Restore")]
        [string]$DestinationFilePrefix = '',
        [parameter(ParameterSetName="Restore")]
        [string]$RestoredDatababaseNamePrefix,
        [parameter(ParameterSetName="Restore")]
        [switch]$TrustDbBackupHistory,
        [parameter(ParameterSetName="Restore")]
        [int]$MaxTransferSize,
        [parameter(ParameterSetName="Restore")]
        [int]$BlockSize,
        [parameter(ParameterSetName="Restore")]
        [int]$BufferCount,
        [parameter(ParameterSetName="Restore")]
        [switch]$DirectoryRecurse,     
        [switch]$EnableException ,
        [parameter(ParameterSetName="Restore")]
        [string]$StandbyDirectory,
        [parameter(ParameterSetName="Restore")]
        [switch]$Continue,
        [string]$AzureCredential,
        [parameter(ParameterSetName="Restore")]
        [switch]$ReplaceDbNameInFile,
        [parameter(ParameterSetName="Restore")]
        [string]$DestinationFileSuffix,
        [parameter(ParameterSetName="Recovery")]
        [switch]$Recover

    )
    begin {
        Write-Message -Level InternalComment -Message "Starting"
        Write-Message -Level Debug -Message "Parameters bound: $($PSBoundParameters.Keys -join ", ")"
		#[string]$DatabaseName = 'testparam'
        #region Validation
        if ($PSCmdlet.ParameterSetName -eq "Restore") {
            $useDestinationDefaultDirectories = $true
            $paramCount = 0
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
                if (!(Test-DbaSqlPath -Path $StandbyDirectory -SqlInstance $SqlInstance -SqlCredential $SqlCredential)) {
                    Stop-Function -Message "$SqlSever cannot see the specified Standby Directory $StandbyDirectory" -Target $SqlInstance
                    return
                }
            }
            if ($Continue) {
                $ContinuePoints = Get-RestoreContinuableDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential
                $WithReplace = $true 
                #$ContinuePoints
            }
            if (!($PSBoundParameters.ContainsKey("DataBasename"))){
               $PipeDatabaseName = $true
            }
        }
        
        try {
            $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        }
        catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            return
        }
        #endregion Validation
		
        $isLocal = [dbavalidate]::IsLocalHost($SqlInstance.ComputerName)
		
        $backupFiles = @()
        #$useDestinationDefaultDirectories = $true
    }
    process {
        if (Test-FunctionInterrupt) { return }
        if ($PSCmdlet.ParameterSetName -eq "Restore") {
            if ($PipeDatabaseName -eq $true){$DatabaseName  = ''}
            Write-Message -message "ParameterSet  = Restore" -Level Verbose
            foreach ($f in $path) {
                if ($TrustDbBackupHistory) {
                    Write-Message -Level Verbose -Message "Trust Database Backup History Set"
                    if ("BackupPath" -notin $f.PSobject.Properties.name) {
                        Write-Message -Level Verbose -Message "adding BackupPath - $($_.Fullname)"
                        $f = $f | Select-Object *, @{ Name = "BackupPath"; Expression = { $_.FullName } }
                    }
                    if ("DatabaseName" -notin $f.PSobject.Properties.name) {
                        $f = $f | Select-Object *, @{ Name = "DatabaseName"; Expression = { $_.Database } }
                    }
                    if ("Type" -notin $f.PSobject.Properties.name) {
                        #$f = $f | Select-Object *,  @{Name="Type";Expression={"Full"}}
                    }
                    if ("BackupSetGUID" -notin $f.PSobject.Properties.name) {
                        #This line until Get-DbaBackupHistory gets fixed
                        #$f = $f | Select-Object *, @{ Name = "BackupSetGUID"; Expression = { $_.BackupSetupID } }
                        #This one once it's sorted:
                        $f = $f | Select-Object *, @{Name="BackupSetGUID";Expression={$_.BackupSetID}}
                    }
                    if ($f.BackupPath -like 'http*' -and '' -eq $AzureCredential) {
                        Stop-Function -Message "At least one Azure backup passed in, and no Credential supplied. Stopping"
                        return
                    }
                    $backupFiles += $F | Select-Object *, @{ Name = "ServerName"; Expression = { $_.SqlInstance } }, @{ Name = "BackupStartDate"; Expression = { $_.Start -as [DateTime] } }

                }
                else {
                    Write-Message -Level Verbose -Message "Unverified input, full scans"
                    if ($f.FullName) {
                        $f = $f.FullName
                    }
                    
                    if ($f -is [string]) {
                        if ($f.StartsWith("\\") -eq $false -and $isLocal -ne $true) {
                            Write-Message -Level Verbose -Message "Working remotely, and non UNC path used. Dropping to XpDirTree, all paths evaluated at $SqlInstance"

                            if ($XpDirTree -ne $true) {
                                Write-Message -Level Verbose -Message "Only XpDirTree is safe on remote server"
                                $XpDirTree = $true
                                $MaintenanceSolutionBackup = $false
                            }
                        }
                    }
                    
                    Write-Message -Level Verbose -Message "type = $($f.gettype())"
                    if ($f -is [string]) {
                        Write-Verbose "$FunctionName : Paths passed in"
                        foreach ($p in $f) {
                            if ($XpDirTree) {
                                if ($p -match '\.\w{3}\Z') {
                                    if ((Test-DbaSqlPath -Path $p -SqlInstance $SqlInstance -SqlCredential $SqlCredential) -and $p -notlike 'http*') {
                                        $p = $p | Select-Object *, @{ Name = "FullName"; Expression = { $p } }
                                        $backupFiles += $p
                                    }
                                    else {
                                        Write-Message -Level Warning -Message "$p cannot be accessed by $SqlInstance" 
                                    }
                                }
                                else {
                                    $backupFiles += Get-XPDirTreeRestoreFile -Path $p -SqlInstance $SqlInstance -SqlCredential $SqlCredential
                                }
                            }
                            elseif ($p -like 'http*') {
                                if ('' -eq $AzureCredential) {
                                    Stop-Function -Message "At least one Azure backup passed in, and no Credential supplied. Stopping"
                                    return
                                }
                                $backupFiles += $p 

                            }
                            elseif ((Get-Item $p -ErrorAction SilentlyContinue).PSIsContainer -ne $true) {
                                try {
                                    $backupFiles += Get-Item $p -ErrorAction Stop
                                }
                                catch {
                                    if ((Test-DbaSqlPath -Path $p -SqlInstance $SqlInstance -SqlCredential $SqlCredential) -or $p -like 'http*') {
                                        $p = $p | Select-Object *, @{ Name = "FullName"; Expression = { $p } }
                                        $backupFiles += $p
                                    }
                                    else {
                                        Stop-Function -Message "$p cannot be accessed by $SqlInstance" -Continue -Target $SqlInstance
                                    }
                                }
                            }
                            elseif ($MaintenanceSolutionBackup) {
                                Write-Verbose "$FunctionName : Ola Style Folder"
                                $backupFiles += Get-OlaHRestoreFile -Path $p -IgnoreLogBackup:$IgnoreLogBackup
                            }
                            else {
                                Write-Verbose "$FunctionName : Standard Directory"
                                $FileCheck = $backupFiles.count
                                $backupFiles += Get-DirectoryRestoreFile -Path $p
                                if ((($backupFiles.count) - $FileCheck) -eq 0) {
                                    $backupFiles += Get-OlaHRestoreFile -Path $p -IgnoreLogBackup:$IgnoreLogBackup
                                }
                            }
                        }
                    }
                    elseif (($f -is [System.IO.FileInfo]) -or ($f -is [System.Object] -and $f.FullName.Length -ne 0)) {
                        Write-Verbose "$FunctionName : Files passed in $($Path.count)"
                        Foreach ($FileTmp in $Path) {
                            Write-Message -Level Verbose -Message "Type - $($FileTmp.GetType()), length =$($FileTmp.length)"
                            if ($FileTmp -is [System.Io.FileInfo] -and $isLocal -eq $False) {
                                Write-Message -Level Verbose -Message "File object"
                                if ($FileTmp.PsIsContainer) {
                                    $backupFiles += Get-XPDirTreeRestoreFile -Path $FileTmp.Fullname -SqlInstance $SqlInstance -SqlCredential $SqlCredential
                                }
                                else {
                                    if (Test-DbaSqlPath -Path $FileTmp.FullName -SqlInstance $SqlInstance -SqlCredential $SqlCredential  -and $p -notlike 'http*') {
                                        $backupFiles += $FileTmp
                                    }
                                    else {
                                        Write-Message -Level Warning -Message "$($FileTmp.FullName) cannot be access by $SqlInstance" 
                                    }
                                
                                }
                            }
                            elseif (($FileTmp -is [System.Management.Automation.PSCustomObject])) {
                                Write-Message -Level Verbose -Message "Should be pipe input "
                                if ($FileTmp.PSobject.Properties.name -match "Server") {
                                    #Most likely incoming from Get-DbaBackupHistory
                                    if ($Filetmp.Server -ne $SqlInstance -and $FileTmp.FullName -notlike '\\*') {
                                        Stop-Function -Target $SqlInstance -Message "Backups from a different server and on a local drive, can't access" 
                                        return
                                    }
                                }
                                if ([bool]($FileTmp.FullName -notmatch '\.\w{3}\Z')) {
                                    
                                    foreach ($dir in $Filetmp.path) {
                                        Write-Message -Level Verbose -Message "it's a folder, passing to Get-XpDirTree - $($dir)"
                                        $backupFiles += Get-XPDirTreeRestoreFile -Path $dir -SqlInstance $SqlInstance -SqlCredential $SqlCredential
                                    }
                                }
                                elseif ([bool]($FileTmp.FullName -match '\.\w{3}\Z')) {
                                    Write-Message -Level Verbose -Message "it's folder"
                                    ForEach ($ft in $Filetmp.FullName) {
                                        Write-Message -Level Verbose -Message "Piped files Test-DbaSqlPath $($ft)"
                                        if (Test-DbaSqlPath -Path $ft -SqlInstance $SqlInstance -SqlCredential $SqlCredential) {
                                            $backupFiles += $ft
                                        }
                                        else {
                                            Write-Message -Level Warning -Message "$($ft) cannot be accessed by $SqlInstance" 
                                        }
                                    }
                                    
                                }
                            }
                            else {
                                Write-Message -Level Verbose -Message "Dropped to Default"
                                $backupFiles += $FileTmp
                            }
                        }
                    }
                }
            }
        }
        elseif ($PSCmdlet.ParameterSetName -eq "Recovery") {
            Write-Message -Message "$($Database.count) databases to recover" -level Verbose
            ForEach ($DataBase in $DatabaseName){
                if ($database -is [object]) {
                    #We've got an object, try the normal options Database, DatabaseName, Name
                    if ("Database" -in $Database.PSobject.Properties.name){
                        [string]$DataBase = $database.Database
                    }
                    elseif ("DatabaseName" -in $Database.PSobject.Properties.name){
                        [string]$DataBase = $database.DatabaseName
                    }
                    elseif ("Name" -in $Database.PSobject.Properties.name){
                        [string]$DataBase = $database.name
                    }
                }
                Write-Verbose "existence - $($server.Databases[$DataBase].State)"
                if ($server.Databases[$DataBase].State -ne 'Existing'){
                    Write-Message -Message "$Database does not exist on $server" -level Warning
                    Continue
                    
                }
                if ($server.Databases[$Database].Status -ne "Restoring"){
                    Write-Message -Message "$Database on $server is not in a Restoring State" -Level Warning
                    Continue
                    
                }
                $RestoreComplete  = $true
                $RecoverSql  = "RESTORE DATABASE $Database WITH RECOVERY"
                Write-Message -Message "rsql - $RecoverSql" -level verbose
                Try{
                    $server.query($RecoverSql)
                }
                Catch {
                    $RestoreComplete = $False
                    $ExitError = $_.Exception.InnerException
                    Write-Message -Level Warning -Message "Failed to recover $Database on $server," 
                }
                Finally {
                    [PSCustomObject]@{
                    SqlInstance            = $SqlInstance
                    DatabaseName           = $Database
                    RestoreComplete        = $RestoreComplete
                    Scripts                = $RecoverSql
                    }
                }
            }    
        }
    }
    end {
        if (Test-FunctionInterrupt) { return }
        if ($PSCmdlet.ParameterSetName -eq "Restore") {
            Write-Message -message "ParameterSet - end  = Restore" -Level Verbose
            

            if ($null -ne $DatabaseName) {
                If (($DatabaseName -in ($server.Databases.name)) -and ($WithReplace -eq $false)) {
                    Stop-Function -Message "$DatabaseName exists on Sql Instance $SqlInstance , must specify WithReplace to continue" -Target $file -Category 'DeviceError' -EnableException  $true
                    break
                }
            }   
            
            if ($isLocal -eq $false) {
                Write-Message -Level Verbose -Message "Remote server, checking folders"
                if ($DestinationDataDirectory -ne '') {
                    if ((Test-DbaSqlPath -Path $DestinationDataDirectory -SqlInstance $SqlInstance -SqlCredential $SqlCredential) -ne $true) {
                        if ((New-DbaSqlDirectory -Path $DestinationDataDirectory -SqlInstance $SqlInstance -SqlCredential $SqlCredential).Created -ne $true) {
                            Stop-Function -Target $DestinationDataDirectory -Message "DestinationDataDirectory $DestinationDataDirectory does not exist, and could not be created on $SqlInstance" 
                            return # removed break
                        }
                        else {
                            Write-Message -Level Verbose -Message "DestinationDataDirectory $DestinationDataDirectory  created on $SqlInstance"
                        }
                    }
                    else {
                        Write-Message -Level Verbose -Message "DestinationDataDirectory $DestinationDataDirectory  exists on $SqlInstance"
                    }
                }
                if ($DestinationLogDirectory -ne '') {
                    if ((Test-DbaSqlPath -Path $DestinationLogDirectory -SqlInstance $SqlInstance -SqlCredential $SqlCredential) -ne $true) {
                        if ((New-DbaSqlDirectory -Path $DestinationLogDirectory -SqlInstance $SqlInstance -SqlCredential $SqlCredential).Created -ne $true) {
                            Stop-Function -Target $DestinationDataDirectory -Message "DestinationLogDirectory $DestinationLogDirectory does not exist, and could not be created on $SqlInstance" 
                            return
                        }
                        else {
                            Write-Message -Level Verbose -Message "DestinationLogDirectory $DestinationLogDirectory  created on $SqlInstance"
                        }
                    }
                    else {
                        Write-Message -Level Verbose -Message "DestinationLogDirectory $DestinationLogDirectory  exists on $SqlInstance"
                    }
                }
            }
            #$BackupFiles 
            #return
            [String]$DatabaseName = $DatabaseName
            Write-Message -Level Verbose -Message "sorting uniquely - $DatabaseName"
            $AllFilteredFiles = $backupFiles | sort-object -property fullname,position -unique | Get-FilteredRestoreFile -SqlInstance $SqlInstance -RestoreTime $RestoreTime -SqlCredential $SqlCredential -IgnoreLogBackup:$IgnoreLogBackup -TrustDbBackupHistory:$TrustDbBackupHistory -continue:$continue -ContinuePoints:$ContinuePoints -DatabaseName $DatabaseName -AzureCredential $AzureCredential
            
            Write-Message -Level Verbose -Message "$($AllFilteredFiles.count) dbs to restore"
            
            #$AllFilteredFiles
            #return
            
            
            if ($AllFilteredFiles.count -gt 1 -and $DatabaseName -ne '') {
                Write-Message -Level Warning -Message "DatabaseName parameter and multiple database restores is not compatible " 
                break
            }
            
            ForEach ($FilteredFileSet in $AllFilteredFiles) {
                $FilteredFiles = $FilteredFileSet.values
                
                
                Write-Message -Level Verbose -Message "Starting FileSet"
                if (($FilteredFiles.DatabaseName | Group-Object | Measure-Object).count -gt 1) {
                    $dbs = ($FilteredFiles | Select-Object -Property DatabaseName) -join (',')
                    Stop-Function -Target $FilteredFiles -Message "We can only handle 1 Database at a time - $dbs"
                    return
                }
                $OldDatabaseName = ($FilteredFiles | Select-Object -Property DatabaseName -unique).DatabaseName
                IF ($DatabaseName -eq '') {
                    #Workaround 
                    $dbnametmp = ($FilteredFiles | Select-Object -Property DatabaseName -unique).databaseName.split(',') 
                    $DatabaseName = $RestoredDatababaseNamePrefix + $dbnametmp
                    Write-Message -Level Verbose -Message "Dbname set from backup = $DatabaseName"
                }
                
                if (($FilteredFiles.Count -gt 0) -and (Test-DbaLsnChain -FilteredRestoreFiles $FilteredFiles -continue:$continue) -and (Test-DbaRestoreVersion -FilteredRestoreFiles $FilteredFiles -SqlInstance $SqlInstance -SqlCredential $SqlCredential)) {
                    try {
                        $FilteredFiles | Restore-DBFromFilteredArray -SqlInstance $SqlInstance -DBName $databasename -SqlCredential $SqlCredential -RestoreTime $RestoreTime -DestinationDataDirectory $DestinationDataDirectory -DestinationLogDirectory $DestinationLogDirectory -NoRecovery:$NoRecovery -TrustDbBackupHistory:$TrustDbBackupHistory -ReplaceDatabase:$WithReplace -ScriptOnly:$OutputScriptOnly -FileStructure $FileMapping -VerifyOnly:$VerifyOnly -UseDestinationDefaultDirectories:$useDestinationDefaultDirectories -ReuseSourceFolderStructure:$ReuseSourceFolderStructure -DestinationFilePrefix $DestinationFilePrefix -MaxTransferSize $MaxTransferSize -BufferCount $BufferCount -BlockSize $BlockSize -StandbyDirectory $StandbyDirectory -continue:$continue -AzureCredential $AzureCredential -ReplaceDbNameInFile:$ReplaceDbNameInFile -DestinationFileSuffix $DestinationFileSuffix -OldDatabaseName $OldDatabaseName
                        $Completed = 'successfully'
                    }
                    catch {
                        if ($_.CategoryInfo.Category -like "DeviceError") {
                            Stop-Function -Message "Restore of $databasename failed, $_" -ErrorRecord $_ -EnableException  $EnableException 
                        }
                        else {
                            Stop-Function -Message "Restore of $databasename failed" -ErrorRecord $_ -EnableException  $EnableException 
                        }
                        $Completed = 'unsuccessfully'
                        return
                    }
                    Finally {
                        Write-Message -Level Verbose -Message "Database $databasename restored $Completed"
                    }
                }
                $DatabaseName = ''
            }
        }    
    }
}