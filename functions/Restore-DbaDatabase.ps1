function Restore-DbaDatabase {
<#
    .SYNOPSIS
        Restores a SQL Server Database from a set of backupfiles
    
    .DESCRIPTION
        Upon bein passed a list of potential backups files this command will scan the files, select those that contain SQL Server
        backup sets. It will then filter those files down to a set that can perform the requested restore, checking that we have a
        full restore chain to the point in time requested by the caller.
        
        The function defaults to working on a remote instance. This means that all paths passed in must be relative to the remote instance.
        XpDirTree will be used to perform the file scans
        
        
        Various means can be used to pass in a list of files to be considered. The default is to non recursively scan the folder
        passed in.
    
    .PARAMETER Path
        Path to SQL Server backup files.
        
        Paths passed in as strings will be scanned using the desired method, default is a non recursive folder scan
        Accepts multiple paths seperated by ','
        
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
    
    .PARAMETER RestoredDatababaseNamePrefix
        A string which will be prefixed to the start of the restore Database's Name
        Useful if restoring a copy to the same sql sevrer for testing.
    
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
        Restore-DbaDatabase -SqlInstance server1\instance1 -Path \\server2\backups -DestinationDataDirectory c:\restores -OutputScriptOnly | Select-Object -ExpandPropert Tsql | Out-File -Filepath c:\scripts\restore.sql
        
        Scans all the backup files in \\server2\backups stored in an Ola Hallengren style folder structure,
        filters them and generate the T-SQL Scripts to restore the database to the latest point in time,
        and then stores the output in a file for later retrieval
    
    .EXAMPLE
        Restore-DbaDatabase -SqlInstance server1\instance1 -Path c:\backups -DestinationDataDirectory c:\DataFiles -DestinationLogDirectory c:\LogFile
        
        Scans all the files in c:\backups and then restores them onto the SQL Server Instance server1\instance1, placing data files
        c:\DataFiles and all the log files into c:\LogFiles
    
    .EXAMPLE
        $File = Get-ChildItem c:\backups, \\server1\backups -recurse
        $File | Restore-DbaDatabase -SqlInstance Server1\Instance -useDestinationDefaultDirectories
        
        This will take all of the files found under the folders c:\backups and \\server1\backups, and pipeline them into
        Restore-DbaDatabase. Restore-DbaDatabase will then scan all of the files, and restore all of the databases included
        to the latest point in time covered by their backups. All data and log files will be moved to the default SQL Sever
        folder for those file types as defined on the target instance.
    
    .NOTES
        Tags: DisasterRecovery, Backup, Restore
        Original Author: Stuart Moore (@napalmgram), stuart-moore.com
        
        dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
        Copyright (C) 2016 Chrissy LeMaire
        
        This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
        
        This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
        
        You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[object[]]$Path,
		[parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[string]$DatabaseName,
		[String]$DestinationDataDirectory,
		[String]$DestinationLogDirectory,
		[DateTime]$RestoreTime = (Get-Date).addyears(1),
		[switch]$NoRecovery,
		[switch]$WithReplace,
		[Switch]$XpDirTree,
		[switch]$OutputScriptOnly,
		[switch]$VerifyOnly,
		[switch]$MaintenanceSolutionBackup,
		[hashtable]$FileMapping,
		[switch]$IgnoreLogBackup,
		[switch]$useDestinationDefaultDirectories,
		[switch]$ReuseSourceFolderStructure,
		[string]$DestinationFilePrefix = '',
		[string]$RestoredDatababaseNamePrefix,
		[switch]$TrustDbBackupHistory,
		[int]$MaxTransferSize,
		[int]$BlockSize,
		[int]$BufferCount,
		[switch]$DirectoryRecurse,
		[switch]$Silent,
		[string]$StandbyDirectory,
		[switch]$continue
	)
	begin {
		Write-Message -Level InternalComment -Message "Starting"
		Write-Message -Level Debug -Message "Parameters bound: $($PSBoundParameters.Keys -join ", ")"
		
		#region Validation
		$paramCount = 0
		if (Was-Bound "FileMapping") {
			$paramCount += 1
		}
		if (Was-Bound "ReuseSourceFolderStructure") {
			$paramCount += 1
		}
		if (Was-Bound "DestinationDataDirectory") {
			$paramCount += 1
		}
		if ($paramCount -gt 1) {
			Stop-Function -Category InvalidArgument -Message "You've specified incompatible Location parameters. Please only specify one of FileMapping, ReuseSourceFolderStructure or DestinationDataDirectory"
			return
		}
		
		if ((Was-Bound "DestinationLogDirectory") -and (Was-Bound "ReuseSourceFolderStructure")) {
			Stop-Function -Category InvalidArgument -Message "The parameters DestinationLogDirectory and UseDestinationDefaultDirectories are mutually exclusive"
			return
		}
		if ((Was-Bound "DestinationLogDirectory") -and -not (Was-Bound "DestinationDataDirectory")) {
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
		if ('' -ne $StandbyDirectory)
		{
			if (!(Test-SqlPath -Path $StandbyDirectory -SqlServer $SqlServer -SqlCredential $SqlCredential))
			{
				Stop-Function -Message "$SqlSever cannot see the specified Standby Directory $StandbyDirectory"
				return
			}
		}
		if ($Continue)
		{
			$ContinuePoints = Get-RestoreContinuableDatabase -SqlInstance $SqlServer -SqlCredential $SqlCredential 
			#$ContinuePoints
		}
		
		try {
			$server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
		}
		catch {
			Stop-Function -Message "Failed to connect to $SqlInstance" -Silent $Silent -ErrorRecord $_
			return
		}
		#endregion Validation
		
		$isLocal = [dbavalidate]::IsLocalHost($SqlInstance.ComputerName)
		
		$backupFiles = @()
		$useDestinationDefaultDirectories = $true
	}
	process {
		if (Test-FunctionInterrupt) { return }
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
					$f = $f | Select-Object *, @{ Name = "BackupSetGUID"; Expression = { $_.BackupSetupID } }
					#This one once it's sorted:
					#$f = $f | Select-Object *, @{Name="BackupSetGUID";Expression={$_.BackupSetID}}
				}
				$backupFiles += $F | Select-Object *, @{ Name = "ServerName"; Expression = { $_.SqlInstance } }, @{ Name = "BackupStartDate"; Expression = { $_.Start -as [DateTime] } }
				$str = ($backupFiles | Select-Object Fullname) -join ','
			}
			else {
				Write-Message -Level Verbose -Message "Unverified input, full scans"
				if ($f.FullName) {
					$f = $f.FullName
				}
				
				if ($f -is [string]) {
					if ($f.StartsWith("\\") -eq $false -and $isLocal -ne $true) {
						Write-Message -Level Verbose -Message "Working remotely, and non UNC path used. Dropping to XpDirTree, all paths evaluated at $SqlInstance"
						# Many internal functions parse using Get-ChildItem. 
						# We need to use Test-DbaSqlPath and other commands instead
						# Prevent people from trying 
						
						#Stop-Function -silent:$silent -message "Currently, you can only use UNC paths when running this command remotely. We expect to support non-UNC paths for remote servers shortly."
						#continue
						
						#$newpath = Join-AdminUnc $SqlInstance "$path"
						#Write-Warning "Run this command on the server itself or try $newpath."
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
								if (Test-DbaSqlPath -Path $p -SqlInstance $SqlInstance -SqlCredential $SqlCredential) {
									$p = $p | Select-Object *, @{ Name = "FullName"; Expression = { $p } }
									$backupFiles += $p
								}
								else {
									Write-Warning "$FunctionName - $p cannot be accessed by $SqlInstance"
								}
							}
							else {
								$backupFiles += Get-XPDirTreeRestoreFile -Path $p -SqlInstance $SqlInstance -SqlCredential $SqlCredential
							}
						}
						elseif ((Get-Item $p -ErrorAction SilentlyContinue).PSIsContainer -ne $true) {
							try {
								$backupFiles += Get-Item $p -ErrorAction Stop
							}
							catch {
								if (Test-DbaSqlPath -Path $p -SqlInstance $SqlInstance -SqlCredential $SqlCredential) {
									$p = $p | Select-Object *, @{ Name = "FullName"; Expression = { $p } }
									$backupFiles += $p
								}
								else {
									Write-Warning "$FunctionName - $p cannot be accessed by $SqlInstance"
									continue
								}
							}
						}
						elseif ($MaintenanceSolutionBackup) {
							Write-Verbose "$FunctionName : Ola Style Folder"
							$backupFiles += Get-OlaHRestoreFile -Path $p
						}
						else {
							Write-Verbose "$FunctionName : Standard Directory"
							$FileCheck = $backupFiles.count
							$backupFiles += Get-DirectoryRestoreFile -Path $p
							if ((($backupFiles.count) - $FileCheck) -eq 0) {
								$backupFiles += Get-OlaHRestoreFile -Path $p
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
								if (Test-DbaSqlPath -Path $FileTmp.FullName -SqlInstance $SqlInstance -SqlCredential $SqlCredential) {
									$backupFiles += $FileTmp
								}
								else {
									Write-Warning "$FunctionName - $($FileTmp.FullName) cannot be access by $SqlInstance"
								}
							
							}
						}
						elseif (($FileTmp -is [System.Management.Automation.PSCustomObject])) #Dealing with Pipeline input 					
{
							Write-Message -Level Verbose -Message "Should be pipe input "
							if ($FileTmp.PSobject.Properties.name -match "Server") {
								#Most likely incoming from Get-DbaBackupHistory
								if ($Filetmp.Server -ne $SqlInstance -and $FileTmp.FullName -notlike '\\*') {
									Write-Warning "$FunctionName - Backups from a different server and on a local drive, can't access"
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
										Write-Warning "$FunctionName - $($ft) cannot be accessed by $SqlInstance"
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
	end {
		if (Test-FunctionInterrupt) { return }
		
		if ($null -ne $DatabaseName) {
			If (($null -ne $server.Databases[$DatabaseName]) -and ($WithReplace -eq $false)) {
				Write-Warning "$FunctionName - $DatabaseName exists on Sql Instance $SqlInstance , must specify WithReplace to continue"
				break
			}
		}
		
		if ($isLocal -eq $false) {
			Write-Message -Level Verbose -Message "Remote server, checking folders"
			if ($DestinationDataDirectory -ne '') {
				if ((Test-DbaSqlPath -Path $DestinationDataDirectory -SqlInstance $SqlInstance -SqlCredential $SqlCredential) -ne $true) {
					if ((New-DbaSqlDirectory -Path $DestinationDataDirectory -SqlInstance $SqlInstance -SqlCredential $SqlCredential).Created -ne $true) {
						Write-Warning "$FunctionName - DestinationDataDirectory $DestinationDataDirectory does not exist, and could not be created on $SqlInstance"
						break
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
						Write-Warning "$FunctionName - DestinationLogDirectory $DestinationLogDirectory does not exist, and could not be created on $SqlInstance"
						break
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
		Write-Message -Level Verbose -Message "sorting uniquely"
		$AllFilteredFiles = $backupFiles | sort-object -property fullname -unique | Get-FilteredRestoreFile -SqlInstance $SqlInstance -RestoreTime $RestoreTime -SqlCredential $SqlCredential -IgnoreLogBackup:$IgnoreLogBackup -TrustDbBackupHistory:$TrustDbBackupHistory -Silent:$Silent
		
		Write-Message -Level Verbose -Message "$($AllFilteredFiles.count) dbs to restore"
		
		#$AllFilteredFiles
		#return
		
		
		if ($AllFilteredFiles.count -gt 1 -and $DatabaseName -ne '') {
			Write-Warning "$FunctionName -  DatabaseName parameter and multiple database restores is not compatible "
			break
		}
		
		ForEach ($FilteredFileSet in $AllFilteredFiles) {
			$FilteredFiles = $FilteredFileSet.values
			
			
			Write-Message -Level Verbose -Message "Starting FileSet"
			if (($FilteredFiles.DatabaseName | Group-Object | Measure-Object).count -gt 1) {
				$dbs = ($FilteredFiles | Select-Object -Property DatabaseName) -join (',')
				Stop-Function -silent:$silent -message "We can only handle 1 Database at a time - $dbs"
				break
			}
			
			IF ($DatabaseName -eq '') {
				$DatabaseName = $RestoredDatababaseNamePrefix + ($FilteredFiles | Select-Object -Property DatabaseName -unique).DatabaseName
				Write-Message -Level Verbose -Message "Dbname set from backup = $DatabaseName"
			}
			
			if ((Test-DbaLsnChain -FilteredRestoreFiles $FilteredFiles) -and (Test-DbaRestoreVersion -FilteredRestoreFiles $FilteredFiles -SqlInstance $SqlInstance -SqlCredential $SqlCredential)) {
				try {
					$FilteredFiles | Restore-DBFromFilteredArray -SqlInstance $SqlInstance -DBName $databasename -SqlCredential $SqlCredential -RestoreTime $RestoreTime -DestinationDataDirectory $DestinationDataDirectory -DestinationLogDirectory $DestinationLogDirectory -NoRecovery:$NoRecovery -TrustDbBackupHistory:$TrustDbBackupHistory -ReplaceDatabase:$WithReplace -ScriptOnly:$OutputScriptOnly -FileStructure $FileMapping -VerifyOnly:$VerifyOnly -UseDestinationDefaultDirectories:$useDestinationDefaultDirectories -ReuseSourceFolderStructure:$ReuseSourceFolderStructure -DestinationFilePrefix $DestinationFilePrefix -MaxTransferSize $MaxTransferSize -BufferCount $BufferCount -BlockSize $BlockSize
					$Completed = 'successfully'
				}
				catch {
					Write-Exception $_
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