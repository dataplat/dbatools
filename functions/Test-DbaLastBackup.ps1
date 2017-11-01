function Test-DbaLastBackup {
	<#
		.SYNOPSIS
			Quickly and easily tests the last set of full backups for a server

		.DESCRIPTION
			Restores all or some of the latest backups and performs a DBCC CHECKDB

			1. Gathers information about the last full backups
			2. Restores the backups to the Destination with a new name. If no Destination is specified, the originating SqlServer wil be used.
			3. The database is restored as "dbatools-testrestore-$databaseName" by default, but you can change dbatools-testrestore to whatever you would like using -Prefix
			4. The internal file names are also renamed to prevent conflicts with original database
			5. A DBCC CHECKDB is then performed
			6. And the test database is finally dropped

		.PARAMETER SqlInstance
			The SQL Server to connect to. Unlike many of the other commands, you cannot specify more than one server.

		.PARAMETER SqlCredential
			Allows you to login to servers using alternative credentials

			$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter

			Windows Authentication will be used if SqlCredential is not specified

		.PARAMETER Destination
			The destination server to use to test the restore. By default, the Destination will be set to the source server

			If a different Destination server is specified, you must ensure that the database backups are on a shared location

		.PARAMETER DestinationCredential
			Allows you to login to servers using alternative credentials

			$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter

			Windows Authentication will be used if SqlCredential is not specified

		.PARAMETER Database
			The database backups to test. If -Database is not provided, all database backups will be tested

		.PARAMETER ExcludeDatabase
			Exclude specific Database backups to test

		.PARAMETER Prefix
			The database is restored as "dbatools-testrestore-$databaseName" by default. You can change dbatools-testrestore to whatever you would like using this parameter.

		.PARAMETER DataDirectory
			The command uses the SQL Server's default data directory for all restores. Use this parameter to specify a different directory for mdfs, ndfs and so on.

		.PARAMETER LogDirectory
			The command uses the SQL Server's default log directory for all restores. Use this parameter to specify a different directory for ldfs.

		.PARAMETER VerifyOnly
			Do not perform the actual restore. Just perform a VERIFYONLY

		.PARAMETER NoCheck
			Skip DBCC CHECKDB

		.PARAMETER NoDrop
			Do not drop newly created test database

		.PARAMETER CopyFile
			Will copy the backup file to the destination default backup location unless CopyPath is specified.

		.PARAMETER CopyPath
			Specify a path relative to the SQL Server to copy backups when CopyFile is specified. If not specified will use destination default backup location. If destination SQL Server is not local, admin UNC paths will be utilized for the copy.

		.PARAMETER MaxMB
			Do not restore databases larger than MaxMB

		.PARAMETER AzureCredential
			The name of the SQL Server credential on the destination instance that holds the key to the azure storage account fied, Copy Options are not allowed.

		.PARAMETER IncludeCopyOnly
			If set, copy only backups will not be counted as a last backup

		.PARAMETER IgnoreLogBackup
			This switch tells the function to ignore transaction log backups. The process will restore to the latest full or differential backup point only

		.PARAMETER WhatIf
			Shows what would happen if the command were to run

		.PARAMETER Confirm
			Prompts for confirmation of every step. For example:

			Are you sure you want to perform this action?
			Performing the operation "Restoring model as dbatools-testrestore-model" on target "SQL2016\VNEXT".
			[Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "Y"):

		.PARAMETER EnableException
			By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.

			This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
			Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

		.NOTES
			Tags: DisasterRecovery, Backup, Restore

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Test-DbaLastBackup

		.EXAMPLE
			Test-DbaLastBackup -SqlInstance sql2016

			Determines the last full backup for ALL databases, attempts to restore all databases (with a different name and file structure), then performs a DBCC CHECKDB

			Once the test is complete, the test restore will be dropped

		.EXAMPLE
			Test-DbaLastBackup -SqlInstance sql2016 -Database master

			Determines the last full backup for master, attempts to restore it, then performs a DBCC CHECKDB

		.EXAMPLE
			Test-DbaLastBackup -SqlInstance sql2016 -NoCheck -NoDrop

			Skips the DBCC CHECKDB check. This can help speed up the tests but makes it less tested. NoDrop means that the test restores will remain on the server.

		.EXAMPLE
			Test-DbaLastBackup -SqlInstance sql2016 -DataDirectory E:\bigdrive -LogDirectory L:\bigdrive -MaxMB 10240

			Restores data and log files to alternative locations and only restores databases that are smaller than 10 GB

		.EXAMPLE
			Test-DbaLastBackup -SqlInstance sql2014 -Destination sql2016 -CopyFile

			Copies the backup files for sql2014 databases to sql2016 default backup locations and then attempts restore from there.

		.EXAMPLE
			Test-DbaLastBackup -SqlInstance sql2014 -Destination sql2016 -CopyFile -CopyPath "\\BackupShare\TestRestore\"

			Copies the backup files for sql2014 databases to sql2016 default backup locations and then attempts restore from there.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer", "Source")]
		[DbaInstanceParameter[]]$SqlInstance,
		[Alias("Credential")]
		[PSCredential]$SqlCredential,
		[DbaInstanceParameter]$Destination,
		[PSCredential]$DestinationCredential,
		[Alias("Databases")]
		[object[]]$Database,
		[object[]]$ExcludeDatabase,
		[string]$Prefix = "dbatools-testrestore-",
		[string]$DataDirectory,
		[string]$LogDirectory,
		[switch]$VerifyOnly,
		[switch]$NoCheck,
		[switch]$NoDrop,
		[switch]$CopyFile,
		[string]$CopyPath,
		[int]$MaxMB,
		[string]$AzureCredential,
		[switch]$IncludeCopyOnly,
		[switch]$IgnoreLogBackup,
		[switch][Alias('Silent')]$EnableException
	)

	process {
		foreach ($instance in $SqlIntance) {

			if (-not $Destination) {
				$Destination = $instance
				$DestinationCredential = $SqlCredential
			}

			try {
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$sourceServer = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}

			try {
				Write-Message -Level Verbose -Message "Connecting to $Destination"
				$destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationCredential
			}
			catch {
				Stop-Function -Message "Failed to connect to: $Destination" -Target $Destination -Continue
			}

			if ($destServer.VersionMajor -lt $sourceServer.VersionMajor) {
				Stop-Function -Message "$Destination is a lower version than $instance. Backups would be incompatible." -Continue
			}

			if ($destServer.VersionMajor -eq $sourceServer.VersionMajor -and $destServer.VersionMinor -lt $sourceServer.VersionMinor) {
				Stop-Function -Message "$Destination is a lower build/version than $instance. Backups would be incompatible." -Continue
			}

			if ($CopyPath) {
				$testPath = Test-DbaSqlPath -SqlInstance $destServer -Path $CopyPath
				if (!$testPath) {
					Stop-Function -Message "$destServer cannot access $CopyPath" -Continue
				}
			}
			else {
				# If not CopyPath is specified, use the destination server default backup directory
				$copyPath = $destServer.BackupDirectory
			}

			if ($instance -ne $Destination -and !$CopyFile) {
				$sourceRealName = $sourceServer.ComputerNetBiosName
				$destRealName = $destServer.ComputerNetBiosName

				if ($BackupFolder) {
					if ($BackupFolder.StartsWith("\\") -eq $false -and $sourceRealName -ne $destRealName) {
						Stop-Function -Message "Backup folder must be a network share if the source and destination servers are not the same." -Continue
					}
				}
			}

			$source = $sourceServer.DomainInstanceName
			$destination = $destServer.DomainInstanceName

			if ($DataDirectory) {
				if (!(Test-DbaSqlPath -SqlInstance $destServer -Path $DataDirectory)) {
					$serviceAccount = $destServer.ServiceAccount
					Stop-Function -Message "Can't access $DataDirectory Please check if $serviceAccount has permissions" -Continue
				}
			}
			else {
				$DataDirectory = Get-SqlDefaultPaths -SqlInstance $destServer -FileType mdf
			}

			if ($LogDirectory) {
				if (!(Test-DbaSqlPath -SqlInstance $destServer -Path $LogDirectory)) {
					$serviceAccount = $destServer.ServiceAccount
					Stop-Function -Message "$Destination can't access its local directory $LogDirectory. Please check if $serviceAccount has permissions" -Continue
				}
			}
			else {
				$LogDirectory = Get-SqlDefaultPaths -SqlInstance $destServer -FileType ldf
			}

			if ((Test-Bound "AzureCredential") -and (Test-Bound "CopyFile")) {
				Stop-Function -Message "Cannot use copyfile with Azure backups, set to false" -continue
				$CopyFile = $false
			}

			$databases = $sourceServer.Databases | Where-Object Name -NE 'tempdb'

			if ($Database) {
				$databases = $databases | Where-Object Name -In $Database
			}

			if ($ExcludeDatabase) {
				$databases = $databases | Where-Object Name -NotIn $ExcludeDatabase
			}

			if ($Database -or $ExcludeDatabase) {
				$dblist = $databases.Name

				Write-Message -Level Verbose -Message "Getting recent backup history for $instance"

				foreach ($dbName in $dblist) {
					Write-Message -Level Verbose -Message "Processing $dbName"

					$copySuccess = $true
					$db = $sourceServer.Databases[$dbName]

					# The db check is needed when the number of databases exceeds 255, then it's no longer auto-populated
					if (!$db) {
						Stop-Function -Message "$dbName does not exist on $source." -Continue
					}

					$lastBackup = Get-DbaBackupHistory -SqlInstance $sourceServer -Database $dbName -Last -IncludeCopyOnly:$IncludeCopyOnly

					if ($CopyFile) {
						try {
							Write-Message -Level Verbose -Message "Gathering information for file copy"
							$removeArray = @()

							if (Test-Bound "IgnoreLogBackup") {
								Write-Message -Level Verbose -Message "Skipping Log backups as requested"
								$lastBackup = @()

								$lastBackup += $full = Get-DbaBackupHistory -SqlInstance $sourceServer -Database $dbName -IncludeCopyOnly:$IncludeCopyOnly -LastFull

								$diff = Get-DbaBackupHistory -SqlInstance $sourceServer -Database $dbName -IncludeCopyOnly:$IncludeCopyOnly -LastDiff

								if ($full.start -le $diff.start) {
									$lastBackup += $diff
								}
							}
							else {
								$lastBackup = Get-DbaBackupHistory -SqlInstance $sourceServer -Database $dbName -Last -IncludeCopyOnly:$IncludeCopyOnly #-raw
							}

							foreach ($backup in $lastBackup) {
								foreach ($file in $backup) {
									$fileName = Split-Path -Path $file.FullName -Leaf
									Write-Message -Level Verbose -Message "Processing $fileName"

									$sourceFile = Join-AdminUnc -ServerName $sourceServer.ComputerNamePhysicalNetBIOS -FilePath $file.Path

									if ($destServer.ComputerNamePhysicalNetBIOS -ne $env:COMPUTERNAME) {
										$remoteDestDirectory = Join-AdminUnc -ServerName $destServer.ComputerNamePhysicalNetBIOS -FilePath $copyPath
									}
									else {
										$remoteDestDirectory = $copyPath
									}

									$remoteDestFile = "$remoteDestDirectory\$fileName"
									$localDestFile = "$copyPath\$fileName"
									Write-Message -Level Verbose -Message "Destination directory is $destdirectory"
									Write-Message -Level Verbose -Message "Destination filename is $remoteDestFile"

									try {
										Write-Message -Level Verbose -Message "Copying $sourceFile to $remoteDestFile"
										Copy-Item -Path $sourceFile -Destination $remoteDestFile -ErrorAction Stop
										$backup.Path = $localDestFile
										$backup.FullName = $localDestFile
										$removeArray += $remoteDestFile
									}
									catch {
										$backup.Path = $sourceFile
										$backup.FullName = $sourceFile
									}
								}
							}
							$copySuccess = $true
						}
						catch {
							Stop-Function -Level Warning -Message "Failed to copy backups for $dbName on $instance to $destdirectory" -ErrorRecord $_ -Target $dbName -Continue
							$copySuccess = $false
						}
					}
					if ($null -eq $lastBackup) {
						Write-Message -Level Verbose -Message "No backups exist for this database"
						$lastBackup = @{ Path = "No backups exist for this database" }
						$fileExists = $false
						$success = $restoreResults = $dbccResults = "Skipped"
					}
					if (!$copySuccess) {
						Write-Message -Level Verbose -Message "Failed to copy backups"
						$lastBackup = @{ Path = "Failed to copy backups" }
						$fileExists = $false
						$success = $restoreResults = $dbccResults =  "Skipped"
					}
					elseif (!($lastBackup | Where-Object { $_.type -eq 'Full' })) {
						Write-Message -Level Verbose -Message "No full backup returned from lastbackup"
						$lastBackup = @{ Path = "Not found" }
						$fileExists = $false
						$success = $restoreResults = $dbccResults = "Skipped"
					}
					elseif ($source -ne $destination -and $lastBackup[0].Path.StartsWith('\\') -eq $false -and !$CopyFile) {
						Write-Message -Level Verbose -Message "Path not UNC and source does not match destination. Use -CopyFile to move the backup file."
						$fileExists = $dbccResults = "Skipped"
						$success = $restoreResults = "Restore not located on shared location"
					}
					elseif (($lastBackup[0].Path | ForEach-Object { Test-DbaSqlPath -SqlInstance $destServer -Path $_ }) -eq $false) {
						Write-Message -Level Verbose -Message "SQL Server cannot find backup"
						$fileExists = $false
						$success = $restoreResults = $dbccResults = "Skipped"
					}
					if ($restoreResults -ne "Skipped" -or $lastBackup[0].Path -like 'http*') {
						Write-Message -Level Verbose -Message "Looking good!"

						$fileExists = $true
						$ogDbName = $dbName
						$restoreList = Read-DbaBackupHeader -SqlInstance $destServer -Path $lastBackup[0].Path -AzureCredential $AzureCredential
						$mb = $restoreList.BackupSizeMB

						if ($MaxMB -gt 0 -and $MaxMB -lt $mb) {
							$success = "The backup size for $dbName ($mb MB) exceeds the specified maximum size ($MaxMB MB)"
							$dbccResults = "Skipped"
						}
						else {
							$dbccElapsed = $restoreElapsed = $startRestore = $endRestore = $startDbcc = $endDbcc = $null

							$dbName = "$prefix$dbName"
							$destdb = $destServer.Databases[$dbName]

							if ($destdb) {
								Stop-Function -Message "$dbName already exists on $destination - skipping" -Continue
							}

							if ($Pscmdlet.ShouldProcess($destination, "Restoring $ogDbName as $dbName")) {
								Write-Message -Level Verbose -Message "Performing restore"
								$startRestore = Get-Date
								if ($VerifyOnly) {
									$restoreResults = $lastBackup | Restore-DbaDatabase -SqlInstance $destServer -RestoredDatababaseNamePrefix $prefix -DestinationFilePrefix $Prefix -DestinationDataDirectory $datadirectory -DestinationLogDirectory $LogDirectory -VerifyOnly:$VerifyOnly -IgnoreLogBackup:$IgnoreLogBackup -AzureCredential $AzureCredential -TrustDbBackupHistory
								}
								else {
									$restoreResults = $lastBackup | Restore-DbaDatabase -SqlInstance $destServer -RestoredDatababaseNamePrefix $prefix -DestinationFilePrefix $Prefix -DestinationDataDirectory $datadirectory -DestinationLogDirectory $LogDirectory -IgnoreLogBackup:$IgnoreLogBackup -AzureCredential $AzureCredential -TrustDbBackupHistory
								}

								$endRestore = Get-Date
								$restoreTs = New-TimeSpan -Start $startRestore -End $endRestore
								$ts = [timespan]::fromseconds($restoreTs.TotalSeconds)
								$restoreElapsed = "{0:HH:mm:ss}" -f ([datetime]$ts.Ticks)

								if ($restoreResults.RestoreComplete -eq $true) {
									$success = "Success"
								}
								else {
									$success = "Failure"
								}
							}

							$destServer = Connect-SqlInstance -SqlInstance $destination -SqlCredential $DestinationCredential

							if (!$NoCheck -and !$VerifyOnly) {
								# shouldprocess is taken care of in Start-DbccCheck
								if ($ogDbName -eq "master") {
									$dbccResults = "DBCC CHECKDB skipped for restored master ($dbName) database"
								}
								else {
									if ($success -eq "Success") {
										Write-Message -Level Verbose -Message "Starting DBCC"

										$startDbcc = Get-Date
										$dbccResults = Start-DbccCheck -Server $destServer -DbName $dbName 3>$null
										$endDbcc = Get-Date

										$dbccTs = New-TimeSpan -Start $startDbcc -End $endDbcc
										$ts = [timespan]::fromseconds($dbccTs.TotalSeconds)
										$dbccElapsed = "{0:HH:mm:ss}" -f ([datetime]$ts.Ticks)
									}
									else {
										$dbccResults = "Skipped"
									}
								}
							}

							if ($VerifyOnly) { $dbccResults = "Skipped" }

							if (!$NoDrop -and $null -ne $destServer.Databases[$dbName]) {
								if ($Pscmdlet.ShouldProcess($dbName, "Dropping Database $dbName on $destination")) {
									Write-Message -Level Verbose -Message "Dropping database"

									## Drop the database
									try {
										$removeResult = Remove-SqlDatabase -SqlInstance $destServer -DbName $dbName
										Write-Message -Level Verbose -Message "Dropped $dbName Database on $destination"
									}
									catch {
										$destServer.Databases.Refresh()
										if ($destServer.Databases[$dbName]) {
											Write-Message -Level Warning -Message "Failed to Drop database $dbName on $destination"
										}
									}
								}
							}

							#Cleanup BackupFiles if -CopyFile and backup was moved to destination
							if ($CopyFile) {
								Write-Message -Level Verbose -Message "Removing copied backup file from $destination"
								try {
									$removeArray | Remove-item -ErrorAction Stop
								}
								catch {
									Write-Message -Level Warning -Message $_ -ErrorRecord $_ -Target $instance
								}
							}

							$destServer.Databases.Refresh()
							if ($destServer.Databases[$dbName] -and !$NoDrop) {
								Write-Message -Level Warning -Message "$dbName was not dropped"
							}
						}
					}

					if ($Pscmdlet.ShouldProcess("console", "Showing results")) {
						[pscustomobject]@{
							SourceServer   = $source
							TestServer     = $destination
							Database       = $db.name
							FileExists     = $fileExists
							Size           = [dbasize](($lastBackup.TotalSize | Measure-Object -Sum).Sum)
							RestoreResult  = $success
							DbccResult     = $dbccResults
							RestoreStart   = [dbadatetime]$startRestore
							RestoreEnd     = [dbadatetime]$endRestore
							RestoreElapsed = $restoreElapsed
							DbccStart      = [dbadatetime]$startDbcc
							DbccEnd        = [dbadatetime]$endDbcc
							DbccElapsed    = $dbccElapsed
							BackupDate     = $lastBackup.Start
							BackupFiles    = $lastBackup.FullName
						}
					}
				}
			}
		}
	}
}
