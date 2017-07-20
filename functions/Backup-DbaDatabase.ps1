function Backup-DbaDatabase {
<#
		.SYNOPSIS
			Backup one or more SQL Sever databases from a SQL Server SqlInstance.

		.DESCRIPTION
			Performs a backup of a specified type of 1 or more databases on a SQL Server Instance. These backups may be Full, Differential or Transaction log backups.

		.PARAMETER SqlInstance
			The SQL Server instance hosting the databases to be backed up.

		.PARAMETER SqlCredential
			Credentials to connect to the SQL Server instance if the calling user doesn't have permission.

		.PARAMETER Database
			The database(s) to process. This list is auto-populated from the server. If unspecified, all databases will be processed.

		.PARAMETER ExcludeDatabase
			The database(s) to exclude. This list is auto-populated from the server.

		.PARAMETER BackupFileName
			The name of the file to backup to. This is only accepted for single database backups.
			If no name is specified then the backup files will be named DatabaseName_yyyyMMddHHmm (i.e. "Database1_201714022131") with the appropriate extension.

			If the same name is used repeatedly, SQL Server will add backups to the same file at an incrementing position.

			SQL Server needs permissions to write to the specified location. Path names are based on the SQL Server (C:\ is the C drive on the SQL Server, not the machine running the script).

		.PARAMETER BackupDirectory
			Path in which to place the backup files. If not specified, the backups will be placed in the default backup location for SqlInstance.
			If multiple paths are specified, the backups will be striped across these locations. This will overwrite the FileCount option.

			If the path does not exist, Sql Server will attempt to create it. Folders are created by the Sql Instance, and checks will be made for write permissions.

			File Names with be suffixed with x-of-y to enable identifying striped sets, where y is the number of files in the set and x ranges from 1 to y.

		.PARAMETER CopyOnly
			If this switch is enabled, CopyOnly backups will be taken. By default function performs a normal backup, these backups interfere with the restore chain of the database. CopyOnly backups will not interfere with the restore chain of the database.

			For more details please refer to this MSDN article - https://msdn.microsoft.com/en-us/library/ms191495.aspx 

		.PARAMETER Type
			The type of SQL Server backup to perform. Accepted values are "Full", "Log", "Differential", "Diff", "Database"

		.PARAMETER FileCount
			This is the number of striped copies of the backups you wish to create.	This value is overwritten if you specify multiple Backup Directories.

		.PARAMETER CreateFolder
			If this switch is enabled, each database will be backed up into a separate folder on each of the paths specified by BackupDirectory.

		.PARAMETER CompressBackup
			If this switch is enabled, the function will try to perform a compressed backup if supported by the version and edition of SQL Server. Otherwise, this function will use the server's default setting for compression.

		.PARAMETER MaxTransferSize
			Sets the size of the unit of transfer. Values must be a multiple of 64kb.

		.PARAMETER Blocksize
			Specifies the block size to use. Must be one of 0.5KB, 1KB, 2KB, 4KB, 8KB, 16KB, 32KB or 64KB. This can be specified in bytes.
			Refer to https://msdn.microsoft.com/en-us/library/ms178615.aspx for more detail

		.PARAMETER BufferCount
			Number of I/O buffers to use to perform the operation.
			Refer to https://msdn.microsoft.com/en-us/library/ms178615.aspx for more detail

		.PARAMETER Checksum
			If this switch is enabled, the backup checksum will be calculated.

		.PARAMETER Verify
			If this switch is enabled, the backup will be verified by running a RESTORE VERIFYONLY against the SqlInstance

		.PARAMETER DatabaseCollection
			Internal parameter

		.PARAMETER AzureBaseUrl
			The URL to the basecontainer of an Azure storage account to write backups to.

			If specified, the only other parameters than can be used are "NoCopyOnly", "Type", "CompressBackup", "Checksum", "Verify", "AzureCredential", "CreateFolder".

		.PARAMETER AzureCredential
			The name of the credential on the SQL instance that can write to the AzureBaseUrl.

		.PARAMETER Silent
			If this switch is enabled, the internal messaging functions will be silenced.

		.NOTES
			Tags: DisasterRecovery, Backup, Restore
			Original Author: Stuart Moore (@napalmgram), stuart-moore.com

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.EXAMPLE 
			Backup-DbaDatabase -SqlInstance Server1 -Database HR, Finance

			This will perform a full database backup on the databases HR and Finance on SQL Server Instance Server1 to Server1's default backup directory.
			
		.EXAMPLE
			Backup-DbaDatabase -SqlInstance sql2016 -BackupDirectory C:\temp -Database AdventureWorks2014 -Type Full

			Backs up AdventureWorks2014 to sql2016's C:\temp folder.

		.EXAMPLE
			Backup-DbaDatabase -SqlInstance sql2016 -AzureBaseUrl https://dbatoolsaz.blob.core.windows.net/azbackups/ -AzureCredential dbatoolscred -Type Full -CreateFolder

			Performs a full backup of all databases on the sql2016 instance to their own containers under the https://dbatoolsaz.blob.core.windows.net/azbackups/ container on Azure blog storage using the sql credential "dbatoolscred" registered on the sql2016 instance.
#>
	[CmdletBinding(DefaultParameterSetName = "Default")]
	param (
		[parameter(ParameterSetName = "Pipe", Mandatory = $true)]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]$SqlCredential,
		[Alias("Databases")]
		[object[]]$Database,
		[object[]]$ExcludeDatabase,
		[string[]]$BackupDirectory,
		[string]$BackupFileName,
		[switch]$CopyOnly,
		[ValidateSet('Full', 'Log', 'Differential', 'Diff', 'Database')]
		[string]$Type = "Database",
		[parameter(ParameterSetName = "NoPipe", Mandatory = $true, ValueFromPipeline = $true)]
		[object[]]$DatabaseCollection,
		[switch]$CreateFolder,
		[int]$FileCount = 0,
		[switch]$CompressBackup,
		[switch]$Checksum,
		[switch]$Verify,
		[int]$MaxTransferSize,
		[int]$BlockSize,
		[int]$BufferCount,
		[string]$AzureBaseUrl,
		[string]$AzureCredential,
		[switch]$Silent
	)
	
	begin {
		
		if ($SqlInstance.length -ne 0) {
			Write-Message -Level Verbose -Message "Connecting to $SqlInstance"
			try {
				$Server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
			}
			catch {
				Write-Message -Level Warning -Message "Cannot connect to $SqlInstance"
				continue
			}
			
			if ($Database) {
				$DatabaseCollection = $server.Databases | Where-Object { $_.Name -in $Database }
			}
			else {
				$DatabaseCollection = $server.Databases | Where-object { $_.Name -ne 'tempdb' }
			}
			
			if ($ExcludeDatabase) {
				$DatabaseCollection = $DatabaseCollection | Where-Object Name -notin $ExcludeDatabase
			}
			
			if ($BackupDirectory.count -gt 1) {
				Write-Message -Level Verbose -Message "Multiple Backup Directories, striping"
				$Filecount = $BackupDirectory.count
			}
			
			if ($DatabaseCollection.count -gt 1 -and $BackupFileName -ne '') {
				Write-Message -Level Warning -Message "1 BackupFile specified, but more than 1 database."
				break
			}
			
			if (($MaxTransferSize % 64kb) -ne 0 -or $MaxTransferSize -gt 4mb) {
				Write-Message -Level Warning -Message "MaxTransferSize value must be a multiple of 64kb and no greater than 4MB"
				break
			}
			if ($BlockSize) {
				if ($BlockSize -notin (0.5kb, 1kb, 2kb, 4kb, 8kb, 16kb, 32kb, 64kb)) {
					Write-Message -Level Warning -Message "Block size must be one of 0.5kb,1kb,2kb,4kb,8kb,16kb,32kb,64kb"
					break
				}
			}
			if ('' -ne $AzureBaseUrl) {
				if ($null -eq $AzureCredential) {
					Stop-Function -Message "You must provide the credential name for the Azure Storage Account"
					break
				}
				$AzureBaseUrl = $AzureBaseUrl.Trim("/")
				$FileCount = 1
				$BackupDirectory = $AzureBaseUrl
			}
		}
	}
	
	process {
		if (!$SqlInstance -and !$DatabaseCollection) {
			Write-Message -Level Warning -Message "You must specify a server and database or pipe some databases"
			continue
		}
		
		Write-Message -Level Verbose -Message "$($DatabaseCollection.count) database to backup"
		
		ForEach ($Database in $databasecollection) {
			$failures = @()
			$dbname = $Database.name
			
			if ($dbname -eq "tempdb") {
				Write-Message -Level Warning -Message "Backing up tempdb not supported"
				continue
			}
			
			if ('Normal' -notin ($Database.Status -split ',')) {
				Write-Message -Level Warning -Message "Database status not Normal. $dbname skipped."
				continue
			}
			
			if ($Database.DatabaseSnapshotBaseName) {
				Write-Message -Level Warning -Message "Backing up snapshots not supported. $dbname skipped."
				continue
			}
			
			if ($null -eq $server) { $server = $Database.Parent }
			
			Write-Message -Level Verbose -Message "Backup up database $database"
			
			if ($null -eq $Database.RecoveryModel) {
				$Database.RecoveryModel = $server.databases[$Database.Name].RecoveryModel
				Write-Message -Level Verbose -Message "$dbname is in $($Database.RecoveryModel) recovery model"
			}
			
			# Fixes one-off cases of StackOverflowException crashes, see issue 1481 
			$dbRecovery = $Database.RecoveryModel.ToString()
 			if ($dbRecovery -eq 'Simple' -and $Type -eq 'Log') {
				$failreason = "$database is in simple recovery mode, cannot take log backup"
				$failures += $failreason
				Write-Message -Level Warning -Message "$failreason"
			}
			
			$lastfull = $database.LastBackupDate.Year
			
			if ($Type -ne "Database" -and $lastfull -eq 1) {
				$failreason = "$database does not have an existing full backup, cannot take log or differentialbackup"
				$failures += $failreason
				Write-Message -Level Warning -Message "$failreason"
			}
			
			if ($CopyOnly -ne $True) {
				$CopyOnly -eq $false
			}
			
			$server.ConnectionContext.StatementTimeout  = 0
			$backup = New-Object Microsoft.SqlServer.Management.Smo.Backup
			$backup.Database = $Database.Name
			$Suffix = "bak"
			
			if ($CompressBackup) {
				if ($server.Edition -like 'Express*' -or ($server.VersionMajor -eq 10 -and $server.VersionMinor -eq 0 -and $server.Edition -notlike '*enterprise*') -or $server.VersionMajor -lt 10) {
					Write-Message -Level Warning -Message "Compression is not supported with this version/edition of Sql Server"
				}
				else {
					Write-Message -Level Verbose -Message "Compression enabled"
					$backup.CompressionOption = 1
				}
			}
			
			if ($Checksum) {
				$backup.Checksum = $true
			}
			
			if ($type -in 'diff', 'differential') {
				Write-Message -Level Verbose -Message "Creating differential backup"
				$type = "Database"
				$backup.Incremental = $true
                $outputType = 'Differential'
			}
			
			if ($Type -eq "Log") {
				Write-Message -Level Verbose -Message "Creating log backup"
				$Suffix = "trn"
                $OutputType = 'Log'
			}
			
			if ($type -in 'Full', 'Database') {
                Write-verbose "Setting type"
				$type = "Database"
                $OutputType='Full'
			}
			
			$backup.CopyOnly = $copyonly
			$backup.Action = $type
			if ('' -ne $AzureBaseUrl) {
				$backup.CredentialName = $AzureCredential
			}
			
			Write-Message -Level Verbose -Message "Sorting Paths"
			
			#If a backupfilename has made it this far, use it
			$FinalBackupPath = @()
			
			if ($BackupFileName) {
				if ($BackupFileName -notlike "*:*") {
					if (!$BackupDirectory) {
						$BackupDirectory = $server.BackupDirectory
					}
					
					$BackupFileName = "$BackupDirectory\$BackupFileName" # removed auto suffix
				}
				
				Write-Message -Level Verbose -Message "Single db and filename"
				
				if (Test-DbaSqlPath -SqlInstance $server -Path (Split-Path $BackupFileName)) {
					$FinalBackupPath += $BackupFileName
				}
				else {
					$failreason = "SQL Server cannot write to the location $(Split-Path $BackupFileName)"
					$failures += $failreason
					Write-Message -Level Warning -Message "$failreason"
				}
			}
			else {
				if (!$BackupDirectory) {
					$BackupDirectory += $server.BackupDirectory
				}
				
				$timestamp = (Get-date -Format yyyyMMddHHmm)
				Write-Message -Level Verbose -Message "Setting filename"
				$BackupFileName = "$($dbname)_$timestamp"
				if ('' -ne $AzureBaseUrl) {
					write-verbose "Azure div"
					$PathDivider = "/"
				}
				else {
					$PathDivider = "\"
				}
				Foreach ($path in $BackupDirectory) {
					if ($CreateFolder) {
						$Path = $path + $PathDivider + $Database.name
						Write-Message -Level Verbose -Message "Creating Folder $Path"
						if (((New-DbaSqlDirectory -SqlInstance $server -SqlCredential $SqlCredential -Path $path).Created -eq $false) -and '' -eq $AzureBaseUrl) {
							$failreason = "Cannot create or write to folder $path"
							$failures += $failreason
							Write-Message -Level Warning -Message "$failreason"
						}
						else {
							$FinalBackupPath += "$path$PathDivider$BackupFileName.$suffix"
						}
					}
					else {
						$FinalBackupPath += "$path$PathDivider$BackupFileName.$suffix"
					}
					<#
					The code below attempts to create the directory even when $CreateFolder -- was it supposed to be Test-DbaSqlPath?
					else
					{
						if ((New-DbaSqlDirectory -SqlInstance $server -SqlCredential $SqlCredential -Path $path).Created -eq $false)
						{
							$failreason = "Cannot create or write to folder $path"
							$failures += $failreason
							Write-Message -Level Warning -Message  "$failreason"
						}
						$FinalBackupPath += "$path\$BackupFileName.$suffix"
					}
					#>
				}
			}
			
			if ('' -eq $AzureBaseUrl) {
				$file = New-Object System.IO.FileInfo($FinalBackupPath[0])
			}
			$suffix = $file.Extension
			
			if ($FileCount -gt 1 -and $FinalBackupPath.count -eq 1) {
				Write-Message -Level Verbose -Message "Striping for Filecount of $filecount"
				$stripes = $filecount
				
				for ($i = 2; $i -lt $stripes + 1; $i++) {
					$FinalBackupPath += $FinalBackupPath[0].Replace("$suffix", "-$i-of-$stripes$($suffix)")
				}
				$FinalBackupPath[0] = $FinalBackupPath[0].Replace("$suffix", "-1-of-$stripes$($suffix)")
				
			}
			elseif ($FinalBackupPath.count -gt 1) {
				Write-Message -Level Verbose -Message "String for Backup path count of $($FinalBackupPath.count)"
				$stripes = $FinalbackupPath.count
				for ($i = 1; $i -lt $stripes + 1; $i++) {
					$FinalBackupPath[($i - 1)] = $FinalBackupPath[($i - 1)].Replace($suffix, "-$i-of-$stripes$($suffix)")
				}
			}
			
			$script = $null
			$backupComplete = $false
			
			if (!$failures) {
				$filecount = $FinalBackupPath.count
				
				foreach ($backupfile in $FinalBackupPath) {
					$device = New-Object Microsoft.SqlServer.Management.Smo.BackupDeviceItem
					if ('' -ne $AzureBaseUrl) {
						$device.DeviceType = "URL"
					}
					else {
						$device.DeviceType = "File"
					}
					$device.Name = $backupfile
					$backup.Devices.Add($device)
				}
				
				Write-Message -Level Verbose -Message "Devices added"
				$percent = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] {
					Write-Progress -id 1 -activity "Backing up database $dbname to $backupfile" -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent))
				}
				$backup.add_PercentComplete($percent)
				$backup.PercentCompleteNotification = 1
				$backup.add_Complete($complete)
				
				if ($MaxTransferSize) {
					$backup.MaxTransferSize = $MaxTransferSize
				}
				if ($BufferCount) {
					$backup.BufferCount = $BufferCount
				}
				if ($BlockSize) {
					$backup.Blocksize = $BlockSize
				}
				
				Write-Progress -id 1 -activity "Backing up database $dbname to $backupfile" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
				
				try {
					$backup.SqlBackup($server)
					$script = $backup.Script($server)
					Write-Progress -id 1 -activity "Backing up database $dbname to $backupfile" -status "Complete" -Completed
					$BackupComplete = $true
					$Filelist = @()
					$FileList += $server.Databases[$dbname].FileGroups.Files | Select-Object @{ Name = "FileType"; Expression = { "D" } }, @{ Name = "Type"; Expression = { "D" } }, @{ Name = "LogicalName"; Expression = { $_.Name } }, @{ Name = "PhysicalName"; Expression = { $_.FileName } }
					$FileList += $server.Databases[$dbname].LogFiles | Select-Object @{ Name = "FileType"; Expression = { "L" } }, @{ Name = "Type"; Expression = { "L" } }, @{ Name = "LogicalName"; Expression = { $_.Name } }, @{ Name = "PhysicalName"; Expression = { $_.FileName } }
					$Verified = $false
					if ($Verify) {
						$verifiedresult = [PSCustomObject]@{
							SqlInstance = $server.name
							DatabaseName = $dbname
							BackupComplete = $BackupComplete
							BackupFilesCount = $FinalBackupPath.count
							BackupFile = (split-path $FinalBackupPath -leaf)
							BackupFolder = (split-path $FinalBackupPath | Sort-Object -Unique)
							BackupPath = ($FinalBackupPath | Sort-Object -Unique)
							Script = $script
							Notes = $failures -join (',')
							FullName = ($FinalBackupPath | Sort-Object -Unique)
							FileList = $FileList
							SoftwareVersionMajor = $server.VersionMajor
                            Type = $outputType
						} | Restore-DbaDatabase -SqlInstance $server -SqlCredential $SqlCredential -DatabaseName DbaVerifyOnly -VerifyOnly
						if ($verifiedResult[0] -eq "Verify successful") {
							$failures += $verifiedResult[0]
							$Verified = $true
						}
						else {
							$failures += $verifiedResult[0]
							$Verified = $false
						}
					}
				}
				catch {
					Write-Progress -id 1 -activity "Backup" -status "Failed" -completed
					Stop-Function -message "Backup Failed:  $($_.Exception.Message)" -Silent $Silent -ErrorRecord $_
					$BackupComplete = $false
				}
			}
			$OutputExclude = 'FullName', 'FileList', 'SoftwareVersionMajor'
			if ($failures.count -eq 0) {
				$OutputExclude += ('Notes')
			}
			[PSCustomObject]@{
				SqlInstance = $server.name
				DatabaseName = $dbname
				BackupComplete = $BackupComplete
				BackupFilesCount = $FinalBackupPath.count
				BackupFile = (split-path $FinalBackupPath -leaf)
				BackupFolder = (split-path $FinalBackupPath | Sort-Object -Unique)
				BackupPath = ($FinalBackupPath | Sort-Object -Unique)
				Script = $script
				Notes = $failures -join (',')
				FullName = ($FinalBackupPath | Sort-Object -Unique)
				FileList = $FileList
				SoftwareVersionMajor = $server.VersionMajor
				Verified = $Verified
                Type = $outputType
			} | Select-DefaultView -ExcludeProperty $OutputExclude
			$BackupFileName = $null
		}
	}
}

