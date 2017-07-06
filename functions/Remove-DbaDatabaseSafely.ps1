function Remove-DbaDatabaseSafely {
<#
.SYNOPSIS
Safely removes a SQL Database and creates an Agent Job to restore it

.DESCRIPTION
Performs a DBCC CHECKDB on the database, backs up the database with Checksum and verify only to a Final Backup location, creates an Agent Job to restore from that backup, Drops the database, runs the agent job to restore the database,
performs a DBCC CHECKDB and drops the database

By default the initial DBCC CHECKDB is performed
By default the jobs and databases are created on the same server. Use -Destination to use a seperate server

It will start the SQL Agent Service on the Destination Server if it is not running

 With huge thanks to Grant Fritchey and his verify your backups video
 Take a look its only 3 minutes long
 http://sqlps.io/backuprant

.PARAMETER SqlInstance
The SQL Server instance holding the databases to be removed.You must have sysadmin access and server version must be SQL Server version 2000 or higher.

.PARAMETER SqlCredential
Allows you to login to servers using alternative credentials

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter

Windows Authentication will be used if SqlCredential is not specified

.PARAMETER DestinationCredential
Allows you to login to servers using alternative credentials

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter

Windows Authentication will be used if SqlCredential is not specified

.PARAMETER Destination
If specified this is the server that the Agent Jobs will be created on. By default this is the same server as the SQLServer.You must have sysadmin access and server version must be SQL Server version 2000 or higher.

.PARAMETER Database
The database name to remove or an array of database names eg $Database = 'DB1','DB2','DB3'

.PARAMETER NoDbccCheckDb
If this switch is used the initial DBCC CHECK DB will be skipped. This will make the process quicker but will also create an agent job to restore a database backup containing a corrupt database.
A second DBCC CHECKDB is performed on the restored database so you will still be notified BUT USE THIS WITH CARE

.PARAMETER BackupFolder
Final (Golden) Backup Folder for storing the backups. Be Careful if you are using a source and destination server that you use the full UNC path eg \\SERVER1\BACKUPSHARE\

.PARAMETER JobOwner
The account that will own the Agent Jobs - Defaults to sa

.PARAMETER UseDefaultFilePaths
Use the instance default file paths for the mdf and ldf files to restore the database if not set will use the original file paths

.PARAMETER CategoryName
The Category Name for the Agent Job that gets created defaults to Rationalisation

.PARAMETER BackupCompression
The setting for the backup compression for the backup defaults to the default setting for the server but accepts On or Off to override that setting

.PARAMETER AllDatabases
Runs the script for every user databases on a server - Useful when decommissioning a server - That would need a DestinationServer set

.PARAMETER ReuseSourceFolderStructure
Reuse source folder structure on restore instead of using destination default.

.PARAMETER Force
This switch will continue to perform rest of the actions and will create an Agent Job with DBCCERROR in the name and a Backup file with DBCC in the name

.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed.

.PARAMETER Confirm
Prompts you for confirmation before executing any changing operations within the command.

.PARAMETER Silent
Use this switch to disable any kind of verbose messages

.NOTES
Tags: DisasterRecovery, Backup, Restore, Databases
Author: Rob Sewell @SQLDBAWithBeard, sqldbawithabeard.com

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Remove-DbaDatabaseSafely

.EXAMPLE
Remove-DbaDatabaseSafely -SqlInstance 'Fade2Black' -Database RideTheLightning -BackupFolder 'C:\MSSQL\Backup\Rationalised - DO NOT DELETE'

For the database RideTheLightning on the server Fade2Black Will perform a DBCC CHECKDB and if there are no errors
backup the database to the folder C:\MSSQL\Backup\Rationalised - DO NOT DELETE. It will then create an Agent Job to restore the database
from that backup. It will drop the database, run the agent job to restore it, perform a DBCC ChECK DB and then drop the database.

Any DBCC errors will be written to your documents folder

.EXAMPLE
$Database = 'DemoNCIndex','RemoveTestDatabase'
Remove-DbaDatabaseSafely -SqlInstance 'Fade2Black' -Database $Database -BackupFolder 'C:\MSSQL\Backup\Rationalised - DO NOT DELETE'

For the databases 'DemoNCIndex','RemoveTestDatabase' on the server Fade2Black Will perform a DBCC CHECKDB and if there are no errors
backup the database to the folder C:\MSSQL\Backup\Rationalised - DO NOT DELETE. It will then create an Agent Job for each database
to restore the database from that backup. It will drop the database, run the agent job, perform a DBCC ChECK DB and then drop the database

Any DBCC errors will be written to your documents folder

.EXAMPLE
Remove-DbaDatabaseSafely -SqlInstance 'Fade2Black' -DestinationServer JusticeForAll -Database RideTheLightning -BackupFolder '\\BACKUPSERVER\BACKUPSHARE\MSSQL\Rationalised - DO NOT DELETE'

For the database RideTheLightning on the server Fade2Black Will perform a DBCC CHECKDB and if there are no errors
backup the database to the folder \\BACKUPSERVER\BACKUPSHARE\MSSQL\Rationalised - DO NOT DELETE It will then create an Agent Job on the server
JusticeForAll to restore the database from that backup. It will drop the database on Fade2Black, run the agent job to restore it on JusticeForAll,
perform a DBCC ChECK DB and then drop the database

Any DBCC errors will be written to your documents folder

.EXAMPLE
Remove-DbaDatabaseSafely -SqlInstance IronMaiden -Database $Database -DestinationServer TheWildHearts -BackupFolder z:\Backups -NoDbccCheckDb -UseDefaultFilePaths -JobOwner 'THEBEARD\Rob'

For the databases $Database on the server IronMaiden Will NOT perform a DBCC CHECKDB
It will backup the databases to the folder Z:\Backups It will then create an Agent Job on the server with a Job Owner of THEBEARD\Rob
TheWildHearts to restore the database from that backup using the instance default filepaths.
It will drop the database on IronMaiden, run the agent job to restore it on TheWildHearts using the default file paths for the instance, perform
a DBCC ChECK DB and then drop the database

Any DBCC errors will be written to your documents folder

.EXAMPLE
Remove-DbaDatabaseSafely -SqlInstance IronMaiden -Database $Database -DestinationServer TheWildHearts -BackupFolder z:\Backups -UseDefaultFilePaths -ContinueAfterDbccError

For the databases $Database on the server IronMaiden will backup the databases to the folder Z:\Backups It will then create an Agent Job
TheWildHearts to restore the database from that backup using the instance default filepaths.
It will drop the database on IronMaiden, run the agent job to restore it on TheWildHearts using the default file paths for the instance, perform
a DBCC ChECK DB and then drop the database

If there is a DBCC Error it will continue to perform rest of the actions and will create an Agent Job with DBCCERROR in the name and a Backup file with DBCCError in the name
#>
	[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = "Default")]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter]$SqlInstance,
		[Alias("Credential")]
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SqlCredential,
		[Alias("Databases")]
		[object[]]$Database,
		[parameter(Mandatory = $false)]
		[DbaInstanceParameter]$Destination = $sqlinstance,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$DestinationCredential,
		[parameter(Mandatory = $false)]
		[Alias("NoCheck")]
		[switch]$NoDbccCheckDb,
		[parameter(Mandatory = $true)]
		[string]$BackupFolder,
		[parameter(Mandatory = $false)]
		[string]$CategoryName = 'Rationalisation',
		[parameter(Mandatory = $false)]
		[string]$JobOwner,
		[parameter(Mandatory = $false)]
		[switch]$AllDatabases,
		[ValidateSet("Default", "On", "Of")]
		[string]$BackupCompression = 'Default',
		[switch]$ReuseSourceFolderStructure,
		[switch]$Force,
		[switch]$Silent
	)

	begin {
		if (!$AllDatabases -and !$Database) {
			Stop-Function -Message "You must specify at least one database. Use -Database or -AllDatabases." -InnerErrorRecord $_
			return
		}

		$sourceserver = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $sqlCredential -ParameterConnection

		if (-not $destination) {
			$destination = $sqlinstance
			$DestinationCredential = $SqlCredential
		}

		if ($sqlinstance -ne $destination) {

			$destserver = Connect-SqlInstance -SqlInstance $destination -SqlCredential $DestinationCredential

			$sourcenb = $sourceserver.ComputerNamePhysicalNetBIOS
			$destnb = $sourceserver.ComputerNamePhysicalNetBIOS

			if ($BackupFolder.StartsWith("\\") -eq $false -and $sourcenb -ne $destnb) {
				Stop-Function -Message "Backup folder must be a network share if the source and destination servers are not the same." -InnerErrorRecord $_ -Target $backupFolder
				return
			}
		}
		else {
			$destserver = $sourceserver
		}

		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName

		if (!$jobowner) {
			$jobowner = Get-SqlSaLogin $destserver
		}

		if ($alldatabases -or !$Database) {
			$database = ($sourceserver.databases | Where-Object{ $_.IsSystemObject -eq $false -and ($_.Status -match 'Offline') -eq $false }).Name
		}

		if (!(Test-DbaSqlPath -SqlInstance $destserver -Path $backupFolder)) {
			$serviceaccount = $destserver.ServiceAccount
			Stop-Function -Message "Can't access $backupFolder Please check if $serviceaccount has permissions" -InnerErrorRecord $_ -Target $backupFolder
		}

		$jobname = "Rationalised Final Database Restore for $dbname"
		$jobStepName = "Restore the $dbname database from Final Backup"

		if (!($destserver.Logins | Where-Object{ $_.Name -eq $jobowner })) {
			Stop-Function -Message "$destination does not contain the login $jobowner - Please fix and try again - Aborting" -InnerErrorRecord $_ -Target $jobowner
		}

		function Start-SqlAgent {
			[CmdletBinding(SupportsShouldProcess = $true)]
			param ()
			if ($destserver.VersionMajor -eq 8) {
				$serviceName = 'MSSQLSERVER'
			}
			else {
				$instance = $destserver.InstanceName
				if ($instance.length -eq 0) { $instance = "MSSQLSERVER" }
				$serviceName = "SQL Server Agent ($instance)"
			}

			if ($Pscmdlet.ShouldProcess($destination, "Starting Sql Agent")) {
				try {
					$ipaddr = Resolve-SqlIpAddress $destserver
					$agentservice = Get-Service -ComputerName $ipaddr -DisplayName $serviceName

					if ($agentservice.Status -ne 'Running') {
						$agentservice.Start()
						$timeout = New-Timespan -seconds 60
						$sw = [diagnostics.stopwatch]::StartNew()
						$agentstatus = (Get-Service -ComputerName $ipaddr -DisplayName $serviceName).Status
						while ($AgentStatus -ne 'Running' -and $sw.elapsed -lt $timeout) {
							$agentStatus = (Get-Service -ComputerName $ipaddr -DisplayName $serviceName).Status
						}
					}
				}

				catch {
					Stop-Function -Message "Error occured: $_" -Target $agentservice -InnerExceptionRecord $_
					return
				}

				if ($agentservice.Status -ne 'Running') {
					throw "Cannot start Agent Service on $destination - Aborting"
				}
			}
		}

		Function Start-DbccCheck {

			[CmdletBinding(SupportsShouldProcess = $true)]
			param (
				[object]$server,
				[string]$dbname
			)

			$servername = $server.name
			$db = $server.databases[$dbname]

			if ($Pscmdlet.ShouldProcess($sourceserver, "Running dbcc check on $dbname on $servername")) {
				try {
					$null = $db.CheckTables('None')
					Write-Message -Level Verbose -Message "Dbcc CHECKDB finished successfully for $dbname on $servername"
				}

				catch {
					Write-Message -Level Warning -Message "DBCC CHECKDB failed"
					Stop-Function -Message "Error occured: $_" -Target $agentservice -InnerExceptionRecord $_ -Continue

					if ($force) {
						return $true
					}
					else {
						return $false
					}
				}
			}
		}

		Function New-SqlAgentJobCategory {

			[CmdletBinding(SupportsShouldProcess = $true)]
			param ([string]$categoryname,
				[object]$jobServer)

			if (!$jobServer.JobCategories[$categoryname]) {
				if ($Pscmdlet.ShouldProcess($sourceserver, "Running dbcc check on $dbname on $sourceserver")) {
					try {
						Write-Message -Level Verbose -Message "Creating Agent Job Category $categoryname"
						$category = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobCategory
						$category.Parent = $jobServer
						$category.Name = $categoryname
						$category.Create()
						Write-Message -Level Verbose -Message "Created Agent Job Category $categoryname"
					}
					catch {
						Stop-Function -Message "FAILED : To Create Agent Job Category - $categoryname - Aborting" -Target $categoryname -InnerExceptionRecord $_
						return
					}
				}
			}
		}

		Function Restore-Database {
			<#
				.SYNOPSIS
				Internal function. Restores .bak file to Sql database. Creates db if it doesn't exist. $filestructure is
				a custom object that contains logical and physical file locations.

				ALTERED To Add TSql switch and remove norecovery switch default
			#>

			param (
				[Parameter(Mandatory = $true)]
				[Alias('ServerInstance', 'SqlInstance', 'SqlServer')]
				[object]$server,
				[Parameter(Mandatory = $true)]
				[ValidateNotNullOrEmpty()]
				[string]$dbname,
				[Parameter(Mandatory = $true)]
				[string]$backupfile,
				[string]$filetype = 'Database',
				[Parameter(Mandatory = $true)]
				[object]$filestructure,
				[switch]$norecovery,
				[PSCredential][System.Management.Automation.CredentialAttribute()]$sqlCredential,
				[switch]$TSql = $false
			)

			$server = Connect-SqlInstance -SqlInstance $server -SqlCredential $sqlCredential
			$servername = $server.name
			$server.ConnectionContext.StatementTimeout = 0
			$restore = New-Object 'Microsoft.SqlServer.Management.Smo.Restore'
			$restore.ReplaceDatabase = $true

			foreach ($file in $filestructure.values) {
				$movefile = New-Object 'Microsoft.SqlServer.Management.Smo.RelocateFile'
				$movefile.LogicalFileName = $file.logical
				$movefile.PhysicalFileName = $file.physical
				$null = $restore.RelocateFiles.Add($movefile)
			}

			try {
				if ($TSql) {
					$restore.PercentCompleteNotification = 1
					$restore.add_Complete($complete)
					$restore.ReplaceDatabase = $true
					$restore.Database = $dbname
					$restore.Action = $filetype
					$restore.NoRecovery = $norecovery
					$device = New-Object -TypeName Microsoft.SqlServer.Management.Smo.BackupDeviceItem
					$device.name = $backupfile
					$device.devicetype = 'File'
					$restore.Devices.Add($device)
					$restorescript = $restore.script($server)
					return $restorescript
				}
				else {
					$percent = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] {
						Write-Progress -id 1 -activity "Restoring $dbname to $servername" -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent))
					}
					$restore.add_PercentComplete($percent)
					$restore.PercentCompleteNotification = 1
					$restore.add_Complete($complete)
					$restore.ReplaceDatabase = $true
					$restore.Database = $dbname
					$restore.Action = $filetype
					$restore.NoRecovery = $norecovery
					$device = New-Object -TypeName Microsoft.SqlServer.Management.Smo.BackupDeviceItem
					$device.name = $backupfile
					$device.devicetype = 'File'
					$restore.Devices.Add($device)

					Write-Progress -id 1 -activity "Restoring $dbname to $servername" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
					$restore.sqlrestore($server)
					Write-Progress -id 1 -activity "Restoring $dbname to $servername" -status 'Complete' -Completed

					return $true
				}
			}
			catch {
				Write-Message -Level Error -Message "Restore failed: $($_.Exception)"
				return $false
			}
		}

	}
	process {
		if (Test-FunctionInterrupt) { return }
		Start-SqlAgent

		$start = Get-Date
		Write-Message -Level Verbose -Message "Starting Rationalisation Script at $start"

		foreach ($dbname in $Database) {

			$db = $sourceserver.databases[$dbname]

			# The db check is needed when the number of databases exceeds 255, then it's no longer auto-populated
			if (!$db) {
				Stop-Function -Message "$dbname does not exist on $source. Aborting routine for this database" -Continue
			}

			$lastFullBckDuration = (Get-DbaBackupHistory -SqlInstance $sourceserver -Database $dbname -LastFull).Duration

			if (-NOT ([string]::IsNullOrEmpty($lastFullBckDuration))) {
				$lastFullBckDurationSec = $lastFullBckDuration.TotalSeconds
				$lastFullBckDurationMin = [Math]::Round($lastFullBckDuration.TotalMinutes, 2)

				Write-Message -Level Verbose -Message "From the backup history the last full backup took $lastFullBckDurationSec seconds ($lastFullBckDurationMin minutes)"
				if ($lastFullBckDurationSec -gt 600) {
					Write-Message -Level Verbose -Message "Last full backup took more than 10 minutes. Do you want to continue?"

					# Set up the parts for the user choice
					$Title = "Backup duration"
					$Info = "Last full backup took more than $lastFullBckDurationMin minutes. Do you want to continue?"

					$Options = [System.Management.Automation.Host.ChoiceDescription[]] @("&Yes", "&No (Skip)")
					[int]$Defaultchoice = 0
					$choice = $host.UI.PromptForChoice($Title, $Info, $Options, $Defaultchoice)
					# Check the given option
					if ($choice -eq 1) {
						Stop-Function -Message "You have chosen skipping the database $dbname  because of last known backup time ($lastFullBckDurationMin minutes)" -InnerErrorRecord $_ -Target $dbname -Continue
						Continue
					}
				}
			}
			else {
				Write-Message -Level Verbose -Message "Couldn't find last full backup time for database $dbname using Get-DbaBackupHistory"
			}

			$jobname = "Rationalised Database Restore Script for $dbname"
			$jobStepName = "Restore the $dbname database from Final Backup"
			$jobServer = $destserver.JobServer

			if ($jobServer.Jobs[$jobname].count -gt 0) {
				if ($force -eq $false) {
					Stop-Function -Message "FAILED: The Job $jobname already exists. Have you done this before? Rename the existing job and try again or use -Force to drop and recreate." -Continue
				}
				else {
					if ($Pscmdlet.ShouldProcess($dbname, "Dropping $jobname on $source")) {
						Write-Message -Level Verbose -Message "Dropping $jobname on $source"
						$jobServer.Jobs[$jobname].Drop()
						$jobServer.Jobs.Refresh()
					}
				}
			}


			Write-Message -Level Verbose -Message "Starting Rationalisation of $dbname"
			## if we want to Dbcc before to abort if we have a corrupt database to start with
			if ($NoDbccCheckDb -eq $false) {
				if ($Pscmdlet.ShouldProcess($dbname, "Running dbcc check on $dbname on $source")) {
					Write-Message -Level Verbose -Message "Starting Dbcc CHECKDB for $dbname on $source"
					$dbccgood = Start-DbccCheck -Server $sourceserver -DBName $dbname

					if ($dbccgood -eq $false) {
						if ($force -eq $false) {
							Write-Message -Level Verbose -Message "DBCC failed for $dbname (you should check that).  Aborting routine for this database"
							continue
						}
						else {
							Write-Message -Level Verbose -Message "DBCC failed, but Force specified. Continuing."
						}
					}
				}
			}

			if ($Pscmdlet.ShouldProcess($source, "Backing up $dbname")) {
				Write-Message -Level Verbose -Message "Starting Backup for $dbname on $source"
				## Take a Backup
				try {
					$timenow = [DateTime]::Now.ToString('yyyyMMdd_HHmmss')
					$backup = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Backup
					$backup.Action = [Microsoft.SqlServer.Management.SMO.BackupActionType]::Database
					$backup.BackupSetDescription = "Final Full Backup of $dbname Prior to Dropping"
					$backup.Database = $dbname
					$backup.Checksum = $True
					if ($sourceserver.versionMajor -gt 9) {
						$backup.CompressionOption = $BackupCompression
					}
					if ($force -and $dbccgood -eq $false) {

						$filename = "$backupFolder\$($dbname)_DBCCERROR_$timenow.bak"
					}
					else {
						$filename = "$backupFolder\$($dbname)_Final_Before_Drop_$timenow.bak"
					}

					$devicetype = [Microsoft.SqlServer.Management.Smo.DeviceType]::File
					$backupDevice = New-Object -TypeName Microsoft.SqlServer.Management.Smo.BackupDeviceItem($filename, $devicetype)

					$backup.Devices.Add($backupDevice)
					#Progress
					$percent = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] {
						Write-Progress -id 1 -activity "Backing up database $dbname on $source to $filename" -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent))
					}
					$backup.add_PercentComplete($percent)
					$backup.add_Complete($complete)
					Write-Progress -id 1 -activity "Backing up database $dbname on $source to $filename" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
					$backup.SqlBackup($sourceserver)
					$null = $backup.Devices.Remove($backupDevice)
					Write-Progress -id 1 -activity "Backing up database $dbname  on $source to $filename" -status "Complete" -Completed
					Write-Message -Level Verbose -Message "Backup Completed for $dbname on $source "

					Write-Message -Level Verbose -Message "Running Restore Verify only on Backup of $dbname on $source"
					try {
						$restoreverify = New-Object 'Microsoft.SqlServer.Management.Smo.Restore'
						$restoreverify.Database = $dbname
						$restoreverify.Devices.AddDevice($filename, $devicetype)
						$result = $restoreverify.SqlVerify($sourceserver)

						if ($result -eq $false) {
							Write-Message -Level Warning -Message "FAILED : Restore Verify Only failed for $filename on $server - aborting routine for this database"
							continue
						}

						Write-Message -Level Verbose -Message "Restore Verify Only for $filename Succeeded "
					}
					catch {
						Stop-Function -Message "FAILED : Restore Verify Only failed for $filename on $server - aborting routine for this database. Exception: $_" -Target $filename -InnerExceptionRecord $_ -Continue
					}
				}
				catch {
					Stop-Function -Message "FAILED : Restore Verify Only failed for $filename on $server - aborting routine for this database. Exception: $_" -Target $filename -InnerExceptionRecord $_ -Continue
				}
			}

			if ($Pscmdlet.ShouldProcess($destination, "Creating Automated Restore Job from Golden Backup for $dbname on $destination")) {
				Write-Message -Level Verbose -Message "Creating Automated Restore Job from Golden Backup for $dbname on $destination "
				try {
					if ($force -eq $true -and $dbccgood -eq $false) {
						$jobName = $jobname -replace "Rationalised", "DBCC ERROR"
					}

					## Create an agent job to restore the database
					$job = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job $jobServer, $jobname
					$job.Name = $jobname
					$job.OwnerLoginName = $jobowner
					$job.Description = "This job will restore the $dbname database using the final backup located at $filename"

					## Create a Job Category
					if (!$jobServer.JobCategories[$categoryname]) {
						New-SqlAgentJobCategory -JobServer $jobServer -categoryname $categoryname
					}

					$job.Category = $categoryname
					try {
						if ($Pscmdlet.ShouldProcess($destination, "Creating Agent Job on $destination")) {
							Write-Message -Level Verbose -Message "Created Agent Job $jobname on $destination "
							$job.Create()
						}
					}
					catch {
						Stop-Function -Message "FAILED : To Create Agent Job $jobname on $destination - aborting routine for this database" -Target $categoryname -InnerExceptionRecord $_ -Continue
					}

					## Create Job Step
					## Aarons Suggestion: In the restore script, add a comment block that tells the last known size of each file in the database.
					## Suggestion check for disk space before restore
					## Create Restore Script
					try {
						$restore = New-Object Microsoft.SqlServer.Management.Smo.Restore
						$device = New-Object -TypeName Microsoft.SqlServer.Management.Smo.BackupDeviceItem $filename, 'FILE'
						$restore.Devices.Add($device)
						try {
							$filelist = $restore.ReadFileList($destserver)
						}

						catch {
							throw 'File list could not be determined. This is likely due to connectivity issues or tiemouts with the Sql Server, the database version is incorrect, or the Sql Server service account does not have access to the file share. Script terminating.'
						}

						$filestructure = Get-OfflineSqlFileStructure $destserver $dbname $filelist $ReuseSourceFolderStructure

						#if ($filestructure -eq $false)
						#{
						#	Write-Message -Level Warning -Message "$dbname contains FILESTREAM and filestreams are not supported by destination server. Skipping."
						#	continue
						#}

						$jobStepCommmand = Restore-Database $destserver $dbname $filename "Database" $filestructure -TSql -ErrorAction Stop
						$jobStep = new-object Microsoft.SqlServer.Management.Smo.Agent.JobStep $job, $jobStepName
						$jobStep.SubSystem = 'TransactSql' # 'PowerShell'
						$jobStep.DatabaseName = 'master'
						$jobStep.Command = $jobStepCommmand
						$jobStep.OnSuccessAction = 'QuitWithSuccess'
						$jobStep.OnFailAction = 'QuitWithFailure'
						if ($Pscmdlet.ShouldProcess($destination, "Creating Agent JobStep on $destination")) {
							$null = $jobStep.Create()
						}
						$jobStartStepid = $jobStep.ID
						Write-Message -Level Verbose -Message "Created Agent JobStep $jobStepName on $destination "
					}
					catch {
						Stop-Function -Message "FAILED : To Create Agent JobStep $jobStepName on $destination - Aborting" -Target $jobStepName -InnerExceptionRecord $_ -Continue
					}
					if ($Pscmdlet.ShouldProcess($destination, "Applying Agent Job $jobname to $destination")) {
						$job.ApplyToTargetServer($destination)
						$job.StartStepID = $jobStartStepid
						$job.Alter()
					}
				}
				catch {
					Stop-Function -Message "FAILED : To Create Agent Job $jobname on $destination - aborting routine for $dbname. Exception: $_" -Target $jobname -InnerExceptionRecord $_ -Continue
				}
			}

			if ($Pscmdlet.ShouldProcess($destination, "Dropping Database $dbname on $sourceserver")) {
				## Drop the database
				try {
					# Remove-SqlDatabase is a function in SharedFunctions.ps1 that tries 3 different ways to drop a database
					Remove-SqlDatabase -SqlInstance $sourceserver -DbName $dbname
					Write-Message -Level Verbose -Message "Dropped $dbname Database  on $source prior to running the Agent Job"
				}
				catch {
					Stop-Function -Message "FAILED : To Drop database $dbname on $server - aborting routine for $dbname. Exception: $_" -Continue
					}
			}

			if ($Pscmdlet.ShouldProcess($destination, "Running Agent Job on $destination to restore $dbname")) {
				## Run the restore job to restore it
				Write-Message -Level Verbose -Message "Starting $jobname on $destination "
				try {
					$job = $destserver.JobServer.Jobs[$jobname]
					$job.Start()
					$job.Refresh()
					$status = $job.CurrentRunStatus

					while ($status -ne 'Idle') {
						Write-Message -Level Verbose -Message "Restore Job for $dbname on $destination is $status..."
						Start-Sleep -Seconds 15
						$job.Refresh()
						$status = $job.CurrentRunStatus
					}

					Write-Message -Level Verbose -Message "Restore Job $jobname has completed on $destination "
					Write-Message -Level Verbose -Message "Sleeping for a few seconds to ensure the next step (DBCC) succeeds"
					Start-Sleep -Seconds 10 ## This is required to ensure the next DBCC Check succeeds
				}
				catch {
					Stop-Function -Message "FAILED : Restore Job $jobname failed on $destination - aborting routine for $dbname. Exception: $_" -Continue
				}

				if ($job.LastRunOutcome -ne 'Succeeded') {
					# LOL, love the plug.
					Write-Message -Level Warning -Message "FAILED : Restore Job $jobname failed on $destination - aborting routine for $dbname"
					Write-Message -Level Warning -Message "Check the Agent Job History on $destination - if you have SSMS2016 July release or later"
					Write-Message -Level Warning -Message "Get-SqlAgentJobHistory -JobName $jobname -ServerInstance $destination -OutcomesType Failed "
					continue
				}
			}

			$refreshRetries = 1

			while (($destserver.databases[$dbname] -eq $null) -and $refreshRetries -lt 6) {
				Write-Message -Level verbose -Message "Database $dbname not found! Refreshing collection"

				#refresh database list, otherwise the next step (DBCC) can fail
				$destserver.Databases.Refresh()

				Start-Sleep -Seconds 1

				$refreshRetries += 1
			}


			## Run a Dbcc No choice here
			if ($Pscmdlet.ShouldProcess($dbname, "Running Dbcc CHECKDB on $dbname on $destination")) {
				Write-Message -Level Verbose -Message "Starting Dbcc CHECKDB for $dbname on $destination"
				$null = Start-DbccCheck -Server $destserver -DbName $dbname
			}

			if ($Pscmdlet.ShouldProcess($dbname, "Dropping Database $dbname on $destination")) {
				## Drop the database
				try {
					$null = Remove-SqlDatabase -SqlInstance $sourceserver -DbName $dbname
					Write-Message -Level Verbose -Message "Dropped $dbname database on $destination"
				}
				catch {
					Stop-Function -Message "FAILED : To Drop database $dbname on $destination - Aborting. Exception: $_" -Target $dbname -InnerExceptionRecord $_ -Continue
				}
			}
			Write-Message -Level Verbose -Message "Rationalisation Finished for $dbname"

			[PSCustomObject]@{
				SqlInstance = $source
				DatabaseName = $dbname
				JobName = $jobname
				TestingInstance = $destination
				BackupFolder = $backupFolder
			}
		}
	}

	end {
		if ($Pscmdlet.ShouldProcess("console", "Showing final message")) {
			$End = Get-Date
			Write-Message -Level Verbose -Message "Finished at $End"
			$Duration = $End - $start
			Write-Message -Level Verbose -Message "Script Duration: $Duration"
		}

		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Remove-SqlDatabaseSafely
	}
}
