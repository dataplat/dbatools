function Invoke-DbaLogShipping {
	<#
.SYNOPSIS 
Invoke-DbaLogShipping sets up log shipping for one or more databases

.DESCRIPTION
Invoke-DbaLogShipping helps to easily set up log shipping for one or more databases.

This function will make a lot of decisions for you assuming you want default values like a daily interval for the schedules with a 15 minute interval on the day.
There are some settings that cannot be made by the function and they need to be prepared before the function is executed.

The following settings need to be made before log shipping can be initiated:
- Backup destination (the folder and the privileges)
- Copy destination (the folder and the privileges)

* Privileges
Make sure your agent service on both the primary and the secondary instance is an Active Directory account.
Also have the credentials ready to set the folder permissions

** Network share
The backup destination needs to be shared and have the share privileges of FULL CONTROL to Everyone.

** NTFS permissions
The backup destination must have at least read/write permissions for the primary instance agent account. 
The backup destination must have at least read permissions for the secondary instance agent account.
The copy destination must have at least read/write permission for the secondary instance agent acount.

.PARAMETER SourceSqlInstance
Source SQL Server instance which contains the databases to be log shipped. 
You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER DestinationSqlInstance
Destination SQL Server instance which contains the databases to be log shipped. 
You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SourceSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter. 
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER SourceCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
$scred = Get-Credential, then pass $scred object to the -SourceCredential parameter. 
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER DestinationSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
$scred = Get-Credential, then pass $scred object to the -DestinationSqlCredential parameter. 
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER DestinationCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
$scred = Get-Credential, then pass $scred object to the -DestinationCredential parameter. 
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER Database
Database to set up log shipping for.

.PARAMETER BackupNetworkPath
The backup unc path to place the backup files. This is the root directory.
A directory with the name of the database will be created in this path.

.PARAMETER BackupLocalPath
If the backup path is locally for the source server you can also set this value.

.PARAMETER BackupJob
Name of the backup that will be created in the SQL Server agent.
The parameter works as a prefix where the name of the database will be added to the backup job name.
The default is "LSBackup_[databasename]"

.PARAMETER BackupRetention
The backup retention period in minutes. Default is 4320 / 72 hours

.PARAMETER BackupSchedule
Name of the backup schedule created for the backup job.
The parameter works as a prefix where the name of the database will be added to the backup job schedule name.
Default is "LSBackupSchedule_[databasename]"

.PARAMETER BackupScheduleDisabled
Parameter to set the backup schedule to disabled upon creation.
By default the schedule is enabled.

.PARAMETER BackupScheduleFrequencyType
A value indicating when a job is to be executed.
Allowed values are "Daily", "AgentStart", "IdleComputer"

.PARAMETER BackupScheduleFrequencyInterval
The number of type periods to occur between each execution of the backup job.

.PARAMETER BackupScheduleFrequencySubdayType
Specifies the units for the subday FrequencyInterval.
Allowed values are "Seconds", "Minutes", "Hours"

.PARAMETER BackupScheduleFrequencySubdayInterval
The number of subday type periods to occur between each execution of the backup job.

.PARAMETER BackupScheduleFrequencyRelativeInterval
A job's occurrence of FrequencyInterval in each month, if FrequencyInterval is 32 (monthlyrelative).

.PARAMETER BackupScheduleFrequencyRecurrenceFactor
The number of weeks or months between the scheduled execution of a job. FrequencyRecurrenceFactor is used only if FrequencyType is 8, "Weekly", 16, "Monthly", 32 or "MonthlyRelative". 

.PARAMETER BackupScheduleStartDate
The date on which execution of a job can begin.

.PARAMETER BackupScheduleEndDate
The date on which execution of a job can stop.

.PARAMETER BackupScheduleStartTime
The time on any day to begin execution of a job. Format HHMMSS / 24 hour clock.
Example: '010000' for 01:00:00 AM. 
Example: '140000' for 02:00:00 PM.

.PARAMETER BackupScheduleEndTime
The time on any day to end execution of a job. Format HHMMSS / 24 hour clock.
Example: '010000' for 01:00:00 AM. 
Example: '140000' for 02:00:00 PM.

.PARAMETER BackupThreshold
Is the length of time, in minutes, after the last backup before a threshold alert error is raised.
The default is 60.

.PARAMETER CompressBackup
Do the backups need to be compressed. By default the backupss are not compressed.

.PARAMETER CopyDestinationFolder
The path to copy the transaction log backup files to. This is the root directory.
A directory with the name of the database will be created in this path.

.PARAMETER CopyJob
Name of the copy job that will be created in the SQL Server agent.
The parameter works as a prefix where the name of the database will be added to the copy job name.
The default is "LSBackup_[databasename]"

.PARAMETER CopyRetention
The copy retention period in minutes. Default is 4320 / 72 hours.

.PARAMETER CopySchedule
Name of the backup schedule created for the copy job.
The parameter works as a prefix where the name of the database will be added to the copy job schedule name.
Default is "LSCopy_[DestinationServerName]_[DatabaseName]"

.PARAMETER CopyScheduleDisabled
Parameter to set the copy schedule to disabled upon creation.
By default the schedule is enabled.

.PARAMETER CopyScheduleFrequencyType
A value indicating when a job is to be executed.
Allowed values are "Daily", "AgentStart", "IdleComputer"

.PARAMETER CopyScheduleFrequencyInterval
The number of type periods to occur between each execution of the copy job.

.PARAMETER CopyScheduleFrequencySubdayType
Specifies the units for the subday FrequencyInterval.
Allowed values are "Seconds", "Minutes", "Hours"

.PARAMETER CopyScheduleFrequencySubdayInterval
The number of subday type periods to occur between each execution of the copy job.

.PARAMETER CopyScheduleFrequencyRelativeInterval
A job's occurrence of FrequencyInterval in each month, if FrequencyInterval is 32 (monthlyrelative).

.PARAMETER CopyScheduleFrequencyRecurrenceFactor
The number of weeks or months between the scheduled execution of a job. FrequencyRecurrenceFactor is used only if FrequencyType is 8, "Weekly", 16, "Monthly", 32 or "MonthlyRelative". 

.PARAMETER CopyScheduleStartDate
The date on which execution of a job can begin.

.PARAMETER CopyScheduleEndDate
The date on which execution of a job can stop.

.PARAMETER CopyScheduleStartTime
The time on any day to begin execution of a job. Format HHMMSS / 24 hour clock.
Example: '010000' for 01:00:00 AM. 
Example: '140000' for 02:00:00 PM.

.PARAMETER CopyScheduleEndTime
The time on any day to end execution of a job. Format HHMMSS / 24 hour clock.
Example: '010000' for 01:00:00 AM. 
Example: '140000' for 02:00:00 PM.

.PARAMETER DisconnectUsers
If this parameter is set in combinations of standby the users will be disconnected during restore.

.PARAMETER FullBackupPath
Path to an existing full backup. Use this when an existing backup needs to used to initialize the database on the secondary instance.

.PARAMETER GenerateFullBackup
If the database is not initialized on the secondary instance it can be done by creating a new full backup and
restore it for you.

.PARAMETER HistoryRetention
Is the length of time in minutes in which the history is retained.
The default value is 14420

.PARAMETER NoRecovery
If this parameter is set the database will be in recoery mode. The database will not be readable.
This setting is default.

.PARAMETER PrimaryMonitorServer
Is the name of the monitor server for the primary server.
If Monitor server is not provided then none will be configured

.PARAMETER PrimaryMonitorCredential
Allows you to login to enter a secure credential. Only needs to be used when the PrimaryMonitorServerSecurityMode is 0 or "sqlserver" 
To use: $scred = Get-Credential, then pass $scred object to the -PrimaryMonitorCredential parameter. 

.PARAMETER PrimaryMonitorServerSecurityMode
The security mode used to connect to the monitor server for the primary server. Allowed values are 0, "sqlserver", 1, "windows"
The default is 1 or Windows.

.PARAMETER PrimaryThresholdAlertEnabled
Enables the Threshold alert for the primary database

.PARAMETER RestoreDataFolder
Folder to be used to restore the database data files. Only used when parameter GenerateFullBackup or UseExistingFullBackup are set.
If the parameter is not set the default data folder of the secondary instance will be used including the name of the database.
If the folder is set but doesn't exist the default data folder of the secondary instance will be used including the name of the database.

.PARAMETER RestoreLogFolder
Folder to be used to restore the database log files. Only used when parameter GenerateFullBackup or UseExistingFullBackup are set.
If the parameter is not set the default transaction log folder of the secondary instance will be used.
If the folder is set but doesn't exist the default transaction log folder of the secondary instance will be used.

.PARAMETER RestoreDelay
In case a delay needs to be set for the restore.
The default is 0.

.PARAMETER RestoreAlertThreshold
The amount of minutes after which an alert will be raised is no restore has taken place.
The default is 45 minutes.

.PARAMETER RestoreJob
Name of the restore job that will be created in the SQL Server agent.
The parameter works as a prefix where the name of the database will be added to the restore job name.
The default is "LSRestore_[databasename]"

.PARAMETER RestoreRetention
The backup retention period in minutes. Default is 4320 / 72 hours

.PARAMETER RestoreSchedule
Name of the backup schedule created for the restore job.
The parameter works as a prefix where the name of the database will be added to the restore job schedule name.
Default is "LSRestore_[DestinationServerName]_[DatabaseName]"

.PARAMETER RestoreScheduleDisabled
Parameter to set the restore schedule to disabled upon creation.
By default the schedule is enabled.

.PARAMETER RestoreScheduleFrequencyType
A value indicating when a job is to be executed.
Allowed values are "Daily", "AgentStart", "IdleComputer"

.PARAMETER RestoreScheduleFrequencyInterval
The number of type periods to occur between each execution of the restore job.

.PARAMETER RestoreScheduleFrequencySubdayType
Specifies the units for the subday FrequencyInterval.
Allowed values are "Seconds", "Minutes", "Hours"

.PARAMETER RestoreScheduleFrequencySubdayInterval
The number of subday type periods to occur between each execution of the restore job.

.PARAMETER RestoreScheduleFrequencyRelativeInterval
A job's occurrence of FrequencyInterval in each month, if FrequencyInterval is 32 (monthlyrelative).

.PARAMETER RestoreScheduleFrequencyRecurrenceFactor
The number of weeks or months between the scheduled execution of a job. FrequencyRecurrenceFactor is used only if FrequencyType is 8, "Weekly", 16, "Monthly", 32 or "MonthlyRelative". 

.PARAMETER RestoreScheduleStartDate
The date on which execution of a job can begin.

.PARAMETER RestoreScheduleEndDate
The date on which execution of a job can stop.

.PARAMETER RestoreScheduleStartTime
The time on any day to begin execution of a job. Format HHMMSS / 24 hour clock.
Example: '010000' for 01:00:00 AM. 
Example: '140000' for 02:00:00 PM.

.PARAMETER RestoreScheduleEndTime
The time on any day to end execution of a job. Format HHMMSS / 24 hour clock.
Example: '010000' for 01:00:00 AM. 
Example: '140000' for 02:00:00 PM.

.PARAMETER RestoreThreshold
The number of minutes allowed to elapse between restore operations before an alert is generated. 
The default value = 0

.PARAMETER SecondaryDatabaseSuffix
The secondary database can be renamed to include a suffix.

.PARAMETER SecondaryMonitorServer
Is the name of the monitor server for the secondary server.
The default is the name of the secondary sql server.

.PARAMETER SecondaryMonitorCredential
Allows you to login to enter a secure credential. Only needs to be used when the SecondaryMonitorServerSecurityMode is 0 or "sqlserver" 
To use: $scred = Get-Credential, then pass $scred object to the -SecondaryMonitorCredential parameter. 

.PARAMETER SecondaryMonitorServerSecurityMode
The security mode used to connect to the monitor server for the secondary server. Allowed values are 0, "sqlserver", 1, "windows"
The default is 1 or Windows.

.PARAMETER SecondaryThresholdAlertEnabled
ENables the Threshold alert for the secondary database

.PARAMETER Standby
If this parameter is set the database will be set to standby mode making the database readable.
If not set the database will be in recovery mode.

.PARAMETER UseExistingFullBackup
If the database is not initialized on the secondary instance it can be done by selecting an existing full backup 
and restore it for you.

.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed.

.PARAMETER Confirm
Prompts you for confirmation before executing any changing operations within the command.

.PARAMETER Silent
Use this switch to disable any kind of verbose messages

.PARAMETER Force
The force parameter will ignore some errors in the parameters and assume defaults.
It will also remove the any present schedules with the same name for the specific job.

.NOTES 
Original Author: Sander Stad (@sqlstad, sqlstad.nl)
Tags: Log shippin, disaster recovery
	
Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Invoke-DbaLogShipping

.EXAMPLE   
Invoke-DbaLogShipping -SourceSqlInstance sql1 -DestinationSqlInstance sql2 -Database db1 -BackupNetworkPath \\sql1\logshipping -BackupLocalPath D:\Data\logshipping -BackupScheduleFrequencyType daily -BackupScheduleFrequencyInterval 1 -CompressBackup -CopyScheduleFrequencyType daily -CopyScheduleFrequencyInterval 1 -GenerateFullBackup -RestoreScheduleFrequencyType daily -RestoreScheduleFrequencyInterval 1 -SecondaryDatabaseSuffix DR -CopyDestinationFolder \\sql2\logshippingdest -Force

Sets up log shiping for database "db1" with the backup path to a network share allowing local backups. 
It creates daily schedules for the backup, copy and restore job with all the defaults to be executed every 15 minutes daily.
The secondary databse will be called "db1_LS".

.EXAMPLE
Invoke-DbaLogShipping -SourceSqlInstance sql1 -DestinationSqlInstance sql2 -Database db1 -BackupNetworkPath \\sql1\logshipping -GenerateFullBackup -Force

Sets up log shipping with all defaults except that a backup file is generated.
The script will show a message that the copy destination has not been supplied and asks if you want to use the default which would be the backup directory of the secondary server with the folder "logshipping" i.e. "D:\SQLBackup\Logshiping".

#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]

	param(
		[parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[Alias("SourceServerInstance", "SourceSqlServerSqlServer")]
		[object]$SourceSqlInstance,

		[parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[Alias("DestinationServerInstance", "DestinationSqlServer")]
		[object]$DestinationSqlInstance,

		[Parameter(Mandatory = $false)]
		[System.Management.Automation.PSCredential]
		$SourceSqlCredential,

		[Parameter(Mandatory = $false)]
		[System.Management.Automation.PSCredential]
		$SourceCredential,

		[Parameter(Mandatory = $false)]
		[System.Management.Automation.PSCredential]
		$DestinationSqlCredential,

		[Parameter(Mandatory = $false)]
		[System.Management.Automation.PSCredential]
		$DestinationCredential,

		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[object[]]$Database,

		[parameter(Mandatory = $true)]
		[string]$BackupNetworkPath,

		[parameter(Mandatory = $false)]
		[string]$BackupLocalPath,

		[parameter(Mandatory = $false)]
		[string]$BackupJob,

		[parameter(Mandatory = $false)]
		[int]$BackupRetention,

		[parameter(Mandatory = $false)]
		[string]$BackupSchedule,

		[parameter(Mandatory = $false)]
		[switch]$BackupScheduleDisabled,

		[parameter(Mandatory = $false)]
		[ValidateSet("Daily", "Weekly", "AgentStart", "IdleComputer")]
		[object]$BackupScheduleFrequencyType,

		[parameter(Mandatory = $false)]
		[object[]]$BackupScheduleFrequencyInterval,

		[parameter(Mandatory = $false)]
		[ValidateSet("Seconds", "Minutes", "Hours")]
		[object]$BackupScheduleFrequencySubdayType,

		[parameter(Mandatory = $false)]
		[int]$BackupScheduleFrequencySubdayInterval,

		[Parameter(Mandatory = $false)]
		[ValidateSet('Unused', 'First', 'Second', 'Third', 'Fourth', 'Last')]
		[object]$BackupScheduleFrequencyRelativeInterval,

		[Parameter(Mandatory = $false)]
		[int]$BackupScheduleFrequencyRecurrenceFactor,

		[parameter(Mandatory = $false)]
		[string]$BackupScheduleStartDate,

		[parameter(Mandatory = $false)]
		[string]$BackupScheduleEndDate,

		[parameter(Mandatory = $false)]
		[string]$BackupScheduleStartTime,

		[parameter(Mandatory = $false)]
		[string]$BackupScheduleEndTime,

		[parameter(Mandatory = $false)]
		[int]$BackupThreshold,

		[parameter(Mandatory = $false)]
		[switch]$CompressBackup,

		[parameter(Mandatory = $false)]
		[string]$CopyDestinationFolder,

		[parameter(Mandatory = $false)]
		[string]$CopyJob,

		[parameter(Mandatory = $false)]
		[int]$CopyRetention,

		[parameter(Mandatory = $false)]
		[string]$CopySchedule,

		[parameter(Mandatory = $false)]
		[switch]$CopyScheduleDisabled,

		[parameter(Mandatory = $false)]
		[ValidateSet("Daily", "Weekly", "AgentStart", "IdleComputer")]
		[object]$CopyScheduleFrequencyType,

		[parameter(Mandatory = $false)]
		[object]$CopyScheduleFrequencyInterval,

		[parameter(Mandatory = $false)]
		[ValidateSet("Seconds", "Minutes", "Hours")]
		[object]$CopyScheduleFrequencySubdayType,

		[parameter(Mandatory = $false)]
		[int]$CopyScheduleFrequencySubdayInterval,

		[Parameter(Mandatory = $false)]
		[ValidateSet('Unused', 'First', 'Second', 'Third', 'Fourth', 'Last')]
		[object]$CopyScheduleFrequencyRelativeInterval,

		[Parameter(Mandatory = $false)]
		[int]$CopyScheduleFrequencyRecurrenceFactor,

		[parameter(Mandatory = $false)]
		[string]$CopyScheduleStartDate,

		[parameter(Mandatory = $false)]
		[string]$CopyScheduleEndDate,

		[parameter(Mandatory = $false)]
		[string]$CopyScheduleStartTime,

		[parameter(Mandatory = $false)]
		[string]$CopyScheduleEndTime,

		[parameter(Mandatory = $false)]
		[switch]$DisconnectUsers,

		[parameter(Mandatory = $false)]
		[string]$FullBackupPath,

		[parameter(Mandatory = $false)]
		[switch]$GenerateFullBackup,

		[parameter(Mandatory = $false)]
		[int]$HistoryRetention,

		[parameter(Mandatory = $false)]
		[switch]$NoRecovery,

		[Parameter(Mandatory = $false)]
		[string]$PrimaryMonitorServer,

		[Parameter(Mandatory = $false)]
		[System.Management.Automation.PSCredential]
		$PrimaryMonitorCredential, 

		[Parameter(Mandatory = $false)]
		[ValidateSet(0, "sqlserver", 1, "windows")]
		[object]$PrimaryMonitorServerSecurityMode,

		[Parameter(Mandatory = $false)]
		[switch]$PrimaryThresholdAlertEnabled,

		[parameter(Mandatory = $false)]
		[string]$RestoreDataFolder,

		[parameter(Mandatory = $false)]
		[string]$RestoreLogFolder,

		[parameter(Mandatory = $false)]
		[int]$RestoreDelay,

		[parameter(Mandatory = $false)]
		[int]$RestoreAlertThreshold,

		[parameter(Mandatory = $false)]
		[string]$RestoreJob,

		[parameter(Mandatory = $false)]
		[int]$RestoreRetention,

		[parameter(Mandatory = $false)]
		[string]$RestoreSchedule,

		[parameter(Mandatory = $false)]
		[switch]$RestoreScheduleDisabled,

		[parameter(Mandatory = $false)]
		[ValidateSet("Daily", "Weekly", "AgentStart", "IdleComputer")]
		[object]$RestoreScheduleFrequencyType,

		[parameter(Mandatory = $false)]
		[object]$RestoreScheduleFrequencyInterval,

		[parameter(Mandatory = $false)]
		[ValidateSet("Seconds", "Minutes", "Hours")]
		[object]$RestoreScheduleFrequencySubdayType,

		[parameter(Mandatory = $false)]
		[int]$RestoreScheduleFrequencySubdayInterval,

		[Parameter(Mandatory = $false)]
		[ValidateSet('Unused', 'First', 'Second', 'Third', 'Fourth', 'Last')]
		[object]$RestoreScheduleFrequencyRelativeInterval,

		[Parameter(Mandatory = $false)]
		[int]$RestoreScheduleFrequencyRecurrenceFactor,

		[parameter(Mandatory = $false)]
		[string]$RestoreScheduleStartDate,

		[parameter(Mandatory = $false)]
		[string]$RestoreScheduleEndDate,

		[parameter(Mandatory = $false)]
		[string]$RestoreScheduleStartTime,

		[parameter(Mandatory = $false)]
		[string]$RestoreScheduleEndTime,

		[parameter(Mandatory = $false)]
		[int]$RestoreThreshold,

		[parameter(Mandatory = $false)]
		[string]$SecondaryDatabaseSuffix,

		[Parameter(Mandatory = $false)]
		[string]$SecondaryMonitorServer,

		[Parameter(Mandatory = $false)]
		[System.Management.Automation.PSCredential]
		$SecondaryMonitorCredential, 

		[Parameter(Mandatory = $false)]
		[ValidateSet(0, "sqlserver", 1, "windows")]
		[object]$SecondaryMonitorServerSecurityMode,

		[Parameter(Mandatory = $false)]
		[switch]$SecondaryThresholdAlertEnabled,

		[parameter(Mandatory = $false)]
		[switch]$Standby,

		[parameter(Mandatory = $false)]
		[switch]$UseExistingFullBackup,

		[switch]$Force,

		[switch]$Silent
	)

	begin {
		Write-Message -Message "Started log shipping for $SourceSqlInstance to $DestinationSqlInstance" -Level Output

		# Try connecting to the instance
		Write-Message -Message "Attempting to connect to source Sql Server $SourceSqlInstance.." -Level Output
		try {
			$SourceServer = Connect-SqlInstance -SqlInstance $SourceSqlInstance -SqlCredential $SourceSqlCredential
		}
		catch {
			Stop-Function -Message "Could not connect to Sql Server instance $SourceSqlInstance" -InnerErrorRecord $_ -Target $SourceSqlInstance 
			return
		}

		# Try connecting to the instance
		Write-Message -Message "Attempting to connect to destination Sql Server $DestinationSqlInstance.." -Level Output
		try {
			$DestinationServer = Connect-SqlInstance -SqlInstance $DestinationSqlInstance -SqlCredential $DestinationSqlCredential
		}
		catch {
			Stop-Function -Message "Could not connect to Sql Server instance $DestinationSqlInstance" -InnerErrorRecord $_ -Target $DestinationSqlInstance 
			return
		}

		# Check the instance if it is a named instance
		$SourceServerName, $SourceInstanceName = $SourceSqlInstance.Split("\")
		$DestinationServerName, $DestinationInstanceName = $DestinationSqlInstance.Split("\")
        
		if ($SourceInstanceName -eq $null) {
			$SourceInstanceName = "MSSQLSERVER"
		}

		if ($DestinationInstanceName -eq $null) {
			$DestinationInstanceName = "MSSQLSERVER"
		}
        
		$IsSourceLocal = $false
		$IsDestinationLocal = $false
        
		# Check if it's local or remote
		if ($SourceServerName -in ".", "localhost", $env:ServerName, "127.0.0.1") {
			$IsSourceLocal = $true
		}
		if ($DestinationServerName -in ".", "localhost", $env:ServerName, "127.0.0.1") {
			$IsDestinationLocal = $true
		}

		# Set up regex strings for several checks
		$RegexDate = '(?<!\d)(?:(?:(?:1[6-9]|[2-9]\d)?\d{2})(?:(?:(?:0[13578]|1[02])31)|(?:(?:0[1,3-9]|1[0-2])(?:29|30)))|(?:(?:(?:(?:1[6-9]|[2-9]\d)?(?:0[48]|[2468][048]|[13579][26])|(?:(?:16|[2468][048]|[3579][26])00)))0229)|(?:(?:1[6-9]|[2-9]\d)?\d{2})(?:(?:0?[1-9])|(?:1[0-2]))(?:0?[1-9]|1\d|2[0-8]))(?!\d)'
		$RegexTime = '^(?:(?:([01]?\d|2[0-3]))?([0-5]?\d))?([0-5]?\d)$'
		$RegexUnc = '^\\(?:\\[^<>:`"/\\|?*]+)+$'

		# Check the instance names and the database settings
		if (($SourceSqlInstance -eq $DestinationSqlInstance) -and (-not $SecondaryDatabaseSuffix)) {
			Stop-Function -Message "If the destination is same as source please enter a suffix with paramater SecondaryDatabaseSuffix." -Target $SourceSqlInstance 
			return
		}

		# Check the backup network path
		if ((Test-DbaSqlPath -Path $BackupNetworkPath -SqlInstance $SourceSqlInstance -SqlCredential $SourceCredential) -ne $true){
			Stop-Function -Message "Backup network path $BackupNetworkPath is not valid or can't be reached." -Target $SourceSqlInstance 
			return
		}
		elseif ($BackupNetworkPath -notmatch $RegexUnc) {
			Stop-Function -Message "Backup network path $BackupNetworkPath has to be in the form of \\server\share." -Target $SourceSqlInstance 
			return
		}

		# Check the copy destination
		if (-not $CopyDestinationFolder) {
			# Make a default copy destination by retrieving the backup folder and adding a directory
			$CopyDestinationFolder = "$($DestinationServer.Settings.BackupDirectory)\Logshipping"

			# Check to see if the path already exists
            
			if (Test-DbaSqlPath -Path $CopyDestinationFolder -SqlInstance $DestinationSqlInstance -SqlCredential $DestinationCredential) {
				Write-Message -Message "Copy destination $CopyDestinationFolder already exists" -Level Verbose
			}
			else {
				# Check if force is being used
				if (-not $Force) {
					# Set up the confirm part
					$message = "The copy destination is missing. Do you want to use the default $($CopyDestinationFolder)?"
					$choiceYes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Answer Yes."
					$choiceNo = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Answer No."
					$options = [System.Management.Automation.Host.ChoiceDescription[]]($choiceYes, $choiceNo)
					$result = $host.ui.PromptForChoice($title, $message, $options, 0)
            
					# Check the result from the confirm
					switch ($result) {
						# If yes
						0 {
							# Try to create the new directory
							try {
								# If the destination server is remote and the credential is set
								if (-not $IsDestinationLocal -and $DestinationCredential) {
									Invoke-Command2 -ComputerName $DestinationServerName -Credential $DestinationCredential -ScriptBlock {
										Write-Message -Message "Creating copy destination folder $CopyDestinationFolder" -Level Verbose
										New-Item -Path $CopyDestinationFolder -ItemType Directory -Credential $DestinationCredential -Force:$Force | Out-Null
									}
								}
								# If the server is local and the credential is set
								elseif ($DestinationCredential) {
									Invoke-Command2 -Credential $DestinationCredential -ScriptBlock {
										Write-Message -Message "Creating copy destination folder $CopyDestinationFolder" -Level Verbose
										New-Item -Path $CopyDestinationFolder -ItemType Directory -Credential $DestinationCredential -Force:$Force | Out-Null
									}
								}
								# If the server is local and the credential is not set
								else {
									Write-Message -Message "Creating copy destination folder $CopyDestinationFolder" -Level Verbose
									New-Item -Path $CopyDestinationFolder -ItemType Directory -Force:$Force | Out-Null
								}
								Write-Message -Message "Copy destination $CopyDestinationFolder created." -Level Verbose
							}
							catch {
								Stop-Function -Message "Something went wrong creating the copy destination folder $CopyDestinationFolder. `n$_" -Target $DestinationSqlInstance -InnerErrorRecord $_
								return
							}
						}
						1 {
							Stop-Function -Message "Copy destination is a mandatory parameter. Please make sure the value is entered." -Target $DestinationSqlInstance 
							return
						} 
					} # switch
				} # if not force
				else {
					# Try to create the copy destination on the local server
					try {
						Write-Message -Message "Creating copy destination folder $CopyDestinationFolder" -Level Verbose
						New-Item $CopyDestinationFolder -ItemType Directory -Credential $DestinationCredential -Force:$Force | Out-Null
						Write-Message -Message "Copy destination $CopyDestinationFolder created." -Level Verbose
					}
					catch {
						Stop-Function -Message "Something went wrong creating the copy destination folder $CopyDestinationFolder. `n$_" -Target $DestinationSqlInstance -InnerErrorRecord $_
						return
					} 
				} # else not force
			} # if test path copy destination
		} # if not copy destination
		elseif ((Test-DbaSqlPath -Path $CopyDestinationFolder -SqlInstance $DestinationSqlInstance -SqlCredential $DestinationCredential) -ne $true) {
			Stop-Function -Message "Copy destination folder $CopyDestinationFolder is not valid or can't be reached." -Target $DestinationSqlInstance 
			return
		}
		elseif ($CopyDestinationFolder.StartsWith("\\") -and $CopyDestinationFolder -notmatch $RegexUnc) {
			Stop-Function -Message "Copy destination folder $CopyDestinationFolder has to be in the form of \\server\share." -Target $DestinationSqlInstance 
			return
		}

		# Check the backup compression
		if ($CompressBackup) {
			Write-Message -Message "Setting backup compression to 1." -Level Verbose
			[int]$BackupCompression = 1
		}
		else {
			Write-Message -Message "Setting backup compression to 0." -Level Verbose
			[int]$BackupCompression = 0
		}

		# Set the database mode
		if ($Standby) {
			$DatabaseStatus = 1
			Write-Message -Message "Destination database status set to STANDBY" -Level Verbose
		}
		else {
			$DatabaseStatus = 0
			Write-Message -Message "Destination database status set to NO RECOVERY" -Level Verbose
		}

		# Setting defaults
		if (-not $BackupRetention) {
			$BackupRetention = 4320 
			Write-Message -Message "Backup retention set to $BackupRetention" -Level Verbose
		}
		if (-not $BackupThreshold) {
			$BackupThreshold = 60
			Write-Message -Message "Backup Threshold set to $BackupThreshold" -Level Verbose 
		}
		if (-not $CopyRetention) {
			$CopyRetention = 4320
			Write-Message -Message "Copy retention set to $CopyRetention" -Level Verbose 
		}
		if (-not $HistoryRetention) {
			$HistoryRetention = 14420
			Write-Message -Message "History retention set to $HistoryRetention" -Level Verbose 
		}
		if (-not $RestoreAlertThreshold) {
			$RestoreAlertThreshold = 45
			Write-Message -Message "Restore alert Threshold set to $RestoreAlertThreshold" -Level Verbose 
		}
		if (-not $RestoreDelay) {
			$RestoreDelay = 0
			Write-Message -Message "Restore delay set to $RestoreDelay" -Level Verbose 
		}
		if (-not $RestoreRetention) {
			$RestoreRetention = 4320
			Write-Message -Message "Restore retention set to $RestoreRetention" -Level Verbose 
		}
		if (-not $RestoreThreshold) {
			$RestoreThreshold = 0
			Write-Message -Message "Restore Threshold set to $RestoreThreshold" -Level Verbose 
		}
		if (-not $PrimaryMonitorServerSecurityMode) {
			$PrimaryMonitorServerSecurityMode = 1 
			Write-Message -Message "Primary monitor server security mode set to $PrimaryMonitorServerSecurityMode" -Level Verbose 
		}
		if (-not $SecondaryMonitorServerSecurityMode) {
			$SecondaryMonitorServerSecurityMode = 1 
			Write-Message -Message "Secondary monitor server security mode set to $SecondaryMonitorServerSecurityMode" -Level Verbose 
		}
		if (-not $BackupScheduleFrequencyType) {
			$BackupScheduleFrequencyType = "Daily" 
			Write-Message -Message "Backup frequency type set to $BackupScheduleFrequencyType" -Level Verbose 
		}
		if (-not $BackupScheduleFrequencyInterval) {
			$BackupScheduleFrequencyInterval = "EveryDay" 
			Write-Message -Message "Backup frequency interval set to $BackupScheduleFrequencyInterval" -Level Verbose 
		}
		if (-not $BackupScheduleFrequencySubdayType) {
			$BackupScheduleFrequencySubdayType = "Minutes" 
			Write-Message -Message "Backup frequency subday type set to $BackupScheduleFrequencySubdayType" -Level Verbose 
		}
		if (-not $BackupScheduleFrequencySubdayInterval) {
			$BackupScheduleFrequencySubdayInterval = 15 
			Write-Message -Message "Backup frequency subday interval set to $BackupScheduleFrequencySubdayInterval" -Level Verbose 
		}
		if (-not $BackupScheduleFrequencyRelativeInterval) {
			$BackupScheduleFrequencyRelativeInterval = "Unused" 
			Write-Message -Message "Backup frequency relative interval set to $BackupScheduleFrequencyRelativeInterval" -Level Verbose 
		}
		if (-not $BackupScheduleFrequencyRecurrenceFactor) {
			$BackupScheduleFrequencyRecurrenceFactor = 0 
			Write-Message -Message "Backup frequency recurrence factor set to $BackupScheduleFrequencyRecurrenceFactor" -Level Verbose 
		}
		if (-not $CopyScheduleFrequencyType) {
			$CopyScheduleFrequencyType = "Daily" 
			Write-Message -Message "Copy frequency type set to $CopyScheduleFrequencyType" -Level Verbose 
		}
		if (-not $CopyScheduleFrequencyInterval) {
			$CopyScheduleFrequencyInterval = "EveryDay" 
			Write-Message -Message "Copy frequency interval set to $CopyScheduleFrequencyInterval" -Level Verbose 
		}
		if (-not $CopyScheduleFrequencySubdayType) {
			$CopyScheduleFrequencySubdayType = "Minutes" 
			Write-Message -Message "Copy frequency subday type set to $CopyScheduleFrequencySubdayType" -Level Verbose 
		}
		if (-not $CopyScheduleFrequencySubdayInterval) {
			$CopyScheduleFrequencySubdayInterval = 15 
			Write-Message -Message "Copy frequency subday interval set to $CopyScheduleFrequencySubdayInterval" -Level Verbose 
		}
		if (-not $CopyScheduleFrequencyRelativeInterval) {
			$CopyScheduleFrequencyRelativeInterval = "Unused" 
			Write-Message -Message "Copy frequency relative interval set to $CopyScheduleFrequencyRelativeInterval" -Level Verbose 
		}
		if (-not $CopyScheduleFrequencyRecurrenceFactor) {
			$CopyScheduleFrequencyRecurrenceFactor = 0 
			Write-Message -Message "Copy frequency recurrence factor set to $CopyScheduleFrequencyRecurrenceFactor" -Level Verbose 
		}
		if (-not $RestoreScheduleFrequencyType) {
			$RestoreScheduleFrequencyType = "Daily" 
			Write-Message -Message "Restore frequency type set to $RestoreScheduleFrequencyType" -Level Verbose 
		}
		if (-not $RestoreScheduleFrequencyInterval) {
			$RestoreScheduleFrequencyInterval = "EveryDay"
			Write-Message -Message "Restore frequency interval set to $RestoreScheduleFrequencyInterval" -Level Verbose 
		}
		if (-not $RestoreScheduleFrequencySubdayType) {
			$RestoreScheduleFrequencySubdayType = "Minutes" 
			Write-Message -Message "Restore frequency subday type set to $RestoreScheduleFrequencySubdayType" -Level Verbose 
		}
		if (-not $RestoreScheduleFrequencySubdayInterval) {
			$RestoreScheduleFrequencySubdayInterval = 15 
			Write-Message -Message "Restore frequency subday interval set to $RestoreScheduleFrequencySubdayInterval" -Level Verbose 
		}
		if (-not $RestoreScheduleFrequencyRelativeInterval) {
			$RestoreScheduleFrequencyRelativeInterval = "Unused" 
			Write-Message -Message "Restore frequency relative interval set to $RestoreScheduleFrequencyRelativeInterval" -Level Verbose 
		}
		if (-not $RestoreScheduleFrequencyRecurrenceFactor) {
			$RestoreScheduleFrequencyRecurrenceFactor = 0 
			Write-Message -Message "Restore frequency recurrence factor set to $RestoreScheduleFrequencyRecurrenceFactor" -Level Verbose 
		}
		if (-not $SecondaryDatabaseSuffix -and ($SourceServer.Name -eq $DestinationServer.Name) -and ($SourceServer.InstanceName -eq $DestinationServer.InstanceName)) {
			if ($Force) {
				$SecondaryDatabaseSuffix = "LS"
			}
			else {
				Stop-Function -Message "Destination database is the same as source database.`nPlease check the secondary server, databse suffix or use -Force to set the secondary databse using a suffix." -Target $SourceSqlInstance 
				return
			}
		}

		# Check the subday interval
		if (($BackupScheduleFrequencySubdayType -in 2, "Seconds", 4, "Minutes") -and (-not ($BackupScheduleFrequencySubdayInterval -ge 1 -or $BackupScheduleFrequencySubdayInterval -le 59))) {
			Stop-Function -Message "Backup subday interval $BackupScheduleFrequencySubdayInterval must be between 1 and 59 when subday type is 2, 'Seconds', 4 or 'Minutes'" -Target $SourceSqlInstance 
			return
		}
		elseif (($BackupScheduleFrequencySubdayType -in 8, "Hours") -and (-not ($BackupScheduleFrequencySubdayInterval -ge 1 -and $BackupScheduleFrequencySubdayInterval -le 23))) {
			Stop-Function -Message "Backup Subday interval $BackupScheduleFrequencySubdayInterval must be between 1 and 23 when subday type is 8 or 'Hours" -Target $SourceSqlInstance 
			return
		}

		# Check the subday interval
		if (($CopyScheduleFrequencySubdayType -in 2, "Seconds", 4, "Minutes") -and (-not ($CopyScheduleFrequencySubdayInterval -ge 1 -or $CopyScheduleFrequencySubdayInterval -le 59))) {
			Stop-Function -Message "Copy subday interval $CopyScheduleFrequencySubdayInterval must be between 1 and 59 when subday type is 2, 'Seconds', 4 or 'Minutes'" -Target $DestinationSqlInstance 
			return
		}
		elseif (($CopyScheduleFrequencySubdayType -in 8, "Hours") -and (-not ($CopyScheduleFrequencySubdayInterval -ge 1 -and $CopyScheduleFrequencySubdayInterval -le 23))) {
			Stop-Function -Message "Copy subday interval $CopyScheduleFrequencySubdayInterval must be between 1 and 23 when subday type is 8 or 'Hours" -Target $DestinationSqlInstance 
			return
		}

		# Check the subday interval
		if (($RestoreScheduleFrequencySubdayType -in 2, "Seconds", 4, "Minutes") -and (-not ($RestoreScheduleFrequencySubdayInterval -ge 1 -or $RestoreScheduleFrequencySubdayInterval -le 59))) {
			Stop-Function -Message "Restore subday interval $RestoreScheduleFrequencySubdayInterval must be between 1 and 59 when subday type is 2, 'Seconds', 4 or 'Minutes'" -Target $DestinationSqlInstance 
			return
		}
		elseif (($RestoreScheduleFrequencySubdayType -in 8, "Hours") -and (-not ($RestoreScheduleFrequencySubdayInterval -ge 1 -and $RestoreScheduleFrequencySubdayInterval -le 23))) {
			Stop-Function -Message "Restore subday interval $RestoreScheduleFrequencySubdayInterval must be between 1 and 23 when subday type is 8 or 'Hours" -Target $DestinationSqlInstance 
			return
		}

		# Check the backup start date
		if (-not $BackupScheduleStartDate) {
			$BackupScheduleStartDate = (Get-Date -format "yyyyMMdd")
			Write-Message -Message "Backup start date set to $BackupScheduleStartDate" -Level Verbose
		}
		else {
			if ($BackupScheduleStartDate -notmatch $RegexDate) {
				Stop-Function -Message "Backup start date $BackupScheduleStartDate needs to be a valid date with format yyyyMMdd" -Target $SourceSqlInstance 
				return
			}  
		}

		# Check the back start time
		if (-not $BackupScheduleStartTime) {
			$BackupScheduleStartTime = '000000'
			Write-Message -Message "Backup start time set to $BackupScheduleStartTime" -Level Verbose
		}
		elseif ($BackupScheduleStartTime -notmatch $RegexTime) {
			Stop-Function -Message  "Backup start time $BackupScheduleStartTime needs to match between '000000' and '235959'" -Target $SourceSqlInstance 
			return
		}

		# Check the back end time
		if (-not $BackupScheduleEndTime) {
			$BackupScheduleEndTime = '235959'
			Write-Message -Message "Backup end time set to $BackupScheduleEndTime" -Level Verbose
		}
		elseif ($BackupScheduleStartTime -notmatch $RegexTime) {
			Stop-Function -Message  "Backup end time $BackupScheduleStartTime needs to match between '000000' and '235959'" -Target $SourceSqlInstance 
			return
		}

		# Check the backup end date
		if (-not $BackupScheduleEndDate) {
			$BackupScheduleEndDate = '99991231'
		}
		elseif ($BackupScheduleEndDate -notmatch $RegexDate) {
			Stop-Function -Message "Backup end date $BackupScheduleEndDate needs to be a valid date with format yyyyMMdd" -Target $SourceSqlInstance 
			return
		}

		# Check the copy start date
		if (-not $CopyScheduleStartDate) {
			$CopyScheduleStartDate = (Get-Date -format "yyyyMMdd")
			Write-Message -Message "Copy start date set to $CopyScheduleStartDate" -Level Verbose
		}
		else {
			if ($CopyScheduleStartDate -notmatch $RegexDate) {
				Stop-Function -Message "Copy start date $CopyScheduleStartDate needs to be a valid date with format yyyyMMdd" -Target $SourceSqlInstance 
				return
			}  
		}

		# Check the copy end date
		if (-not $CopyScheduleEndDate) {
			$CopyScheduleEndDate = '99991231'
		}
		elseif ($CopyScheduleEndDate -notmatch $RegexDate) {
			Stop-Function -Message "Copy end date $CopyScheduleEndDate needs to be a valid date with format yyyyMMdd" -Target $SourceSqlInstance 
			return
		}

		# Check the copy start time
		if (-not $CopyScheduleStartTime) {
			$CopyScheduleStartTime = '000000'
			Write-Message -Message "Copy start time set to $CopyScheduleStartTime" -Level Verbose
		}
		elseif ($CopyScheduleStartTime -notmatch $RegexTime) {
			Stop-Function -Message  "Copy start time $CopyScheduleStartTime needs to match between '000000' and '235959'" -Target $SourceSqlInstance 
			return
		}

		# Check the copy end time
		if (-not $CopyScheduleEndTime) {
			$CopyScheduleEndTime = '235959'
			Write-Message -Message "Copy end time set to $CopyScheduleEndTime" -Level Verbose
		}
		elseif ($CopyScheduleEndTime -notmatch $RegexTime) {
			Stop-Function -Message  "Copy end time $CopyScheduleEndTime needs to match between '000000' and '235959'" -Target $SourceSqlInstance 
			return
		}

		# Check the restore start date
		if (-not $RestoreScheduleStartDate) {
			$RestoreScheduleStartDate = (Get-Date -format "yyyyMMdd")
			Write-Message -Message "Restore start date set to $RestoreScheduleStartDate" -Level Verbose
		}
		else {
			if ($RestoreScheduleStartDate -notmatch $RegexDate) {
				Stop-Function -Message "Restore start date $RestoreScheduleStartDate needs to be a valid date with format yyyyMMdd" -Target $SourceSqlInstance 
				return
			}  
		}

		# Check the restore end date
		if (-not $RestoreScheduleEndDate) {
			$RestoreScheduleEndDate = '99991231'
		}
		elseif ($RestoreScheduleEndDate -notmatch $RegexDate) {
			Stop-Function -Message "Restore end date $RestoreScheduleEndDate needs to be a valid date with format yyyyMMdd" -Target $SourceSqlInstance 
			return
		}

		# Check the restore start time
		if (-not $RestoreScheduleStartTime) {
			$RestoreScheduleStartTime = '000000'
			Write-Message -Message "Restore start time set to $RestoreScheduleStartTime" -Level Verbose
		}
		elseif ($RestoreScheduleStartTime -notmatch $RegexTime) {
			Stop-Function -Message  "Restore start time $RestoreScheduleStartTime needs to match between '000000' and '235959'" -Target $SourceSqlInstance 
			return
		}

		# Check the restore end time
		if (-not $RestoreScheduleEndTime) {
			$RestoreScheduleEndTime = '235959'
			Write-Message -Message "Restore end time set to $RestoreScheduleEndTime" -Level Verbose
		}
		elseif ($RestoreScheduleEndTime -notmatch $RegexTime) {
			Stop-Function -Message  "Restore end time $RestoreScheduleEndTime needs to match between '000000' and '235959'" -Target $SourceSqlInstance 
			return
		}

	}

	process {

		if (Test-FunctionInterrupt) { return }
        
		foreach ($db in $Database) {
			# Check if the database is present on the source sql server
			if (($SourceServer.Databases).Name -notcontains $db) {
				Write-Message -Message "Database $db is not available on instance $SourceSqlInstance" -Warning
			}
			else {
				Write-Message -Message "Start configuring log shipping for database $db on instance $SourceSqlInstance" -Level Output	
 				
				if ($BackupLocalPath) {
					if ($BackupLocalPath.EndsWith("\")) {
						$DatabaseBackupLocalPath = "$BackupLocalPath$db"
					}
					else {
						$DatabaseBackupLocalPath = "$BackupLocalPath\$db"
					}
				}
				else {
					$BackupLocalPath = $BackupNetworkPath

					if ($BackupLocalPath.EndsWith("\")) {
						$DatabaseBackupLocalPath = "$BackupLocalPath$db"
					}
					else {
						$DatabaseBackupLocalPath = "$BackupLocalPath\$db"
					}
				}
				Write-Message -Message "Backup local path set to $DatabaseBackupLocalPath." -Level Verbose

				# Setting the backup network path for the database
				if ($BackupNetworkPath.EndsWith("\")) {
					$DatabaseBackupNetworkPath = "$BackupNetworkPath$db"
				}
				else {
					$DatabaseBackupNetworkPath = "$BackupNetworkPath\$db"
				}
				Write-Message -Message "Backup network path set to $DatabaseBackupNetworkPath." -Level Verbose

				# Checking if the database network path exists
				if ((Test-DbaSqlPath -Path $DatabaseBackupNetworkPath -SqlInstance $SourceSqlInstance -SqlCredential $SourceCredential) -ne $true) {
					# To to create the backup directory for the database 
					try {
						Write-Message -Message "Backup network path not found. Trying to create it.." -Level Verbose
                        Invoke-Command2 -Credential $DestinationCredential -ScriptBlock {
						    Write-Message -Message "Creating backup folder $DatabaseBackupNetworkPath" -Level Verbose
							New-Item -Path $DatabaseBackupNetworkPath -ItemType Directory -Credential $SourceCredential -Force:$Force | Out-Null
                        }
					}
					catch {
						Stop-Function -Message "Something went wrong creating the directory. `n$($_.Exception.Message)" -InnerErrorRecord $_ -Target $SourceSqlInstance -Continue
					}   
				}

				# Check if the backup job name is set
				if ($BackupJob) {
					$DatabaseBackupJob = "$BackupJob_$db"
				}
				else {
					$DatabaseBackupJob = "LSBackup_$db"
				}
				Write-Message -Message "Backup job name set to $DatabaseBackupJob" -Level Verbose

				# Check if the backup job schedule name is set
				if ($BackupSchedule) {
					$DatabaseBackupSchedule = "$BackupSchedule_$db"
				}
				else {
					$DatabaseBackupSchedule = "LSBackupSchedule_$db"
				}
				Write-Message -Message "Backup job schedule name set to $DatabaseBackupSchedule" -Level Verbose

				# Set the database suffix
				if ($SecondaryDatabaseSuffix) {
					$SecondaryDatabase = "$($db)_$($SecondaryDatabaseSuffix)"
				}
				else {
					$SecondaryDatabase = $db
				}
            
				# Check if secondary database is present on secondary instance
				if (-not $Force -and ($DestinationServer.Databases.Name -contains $SecondaryDatabase)) {
					Stop-Function -Message "Secondary database already exists on instance $DestinationSqlInstance." -InnerErrorRecord $_ -Target $DestinationSqlInstance -Continue
				}

				# Check if the secondary database exists on the secondary instance
				if ($DestiationServer.Databases.Name -notcontains $SecondaryDatabase) {
					# Check if force is being used and no option to generate the full backup is set
					if ($Force -and -not $GenerateFullBackup) {
						# Set the option to generate a full backup
						Write-Message -Message "Set option to initialize secondary database with full backup." -Level Verbose
						$GenerateFullBackup = $true
					}
					# Else give the user the option to generate the full backup
					else {
						# Set up the confirm part
						$message = "The database $SecondaryDatabase does not exist on instance $DestinationSqlInstance. `nDo you want to initialize it by generating a full backup?"
						$choiceYes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Answer Yes."
						$choiceNo = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Answer No."
						$options = [System.Management.Automation.Host.ChoiceDescription[]]($choiceYes, $choiceNo)
						$result = $host.ui.PromptForChoice($title, $message, $options, 0)
				
						# Check the result from the confirm
						switch ($result) {
							# If yes
							0 {
								# Set the option to generate a full backup
								Write-Message -Message "Set option to initialize secondary database with full backup." -Level Verbose
								$GenerateFullBackup = $true
							}
							1 {
								Stop-Function -Message "The database is not initialized on the secondary instance. `nPlease initialize the database on the secondary instance, use -GenerateFullbackup or use -Force." -Target $DestinationSqlInstance 
								return
							} 
						} # switch
					}
				}
				elseif (-not $Force -and ($DestiationServer.Databases.Name -notcontains $SecondaryDatabase)) {
					Stop-Function -Message "The database is not initialized on the secondary instance. `nPlease initialize the database on the secondary instance, use -GenerateFullbackup or use -Force." -Target $DestinationSqlInstance 
					return
				}

				# Check the parameters for initialization of the secondary database
				if ($GenerateFullBackup -or $UseExistingFullBackup) {
					# Check if the restore data and log folder are set
					if (-not $RestoreDataFolder -or -not $RestoreLogFolder) {
						Write-Message -Message "Restore data folder or restore log folder are not set. Using server defaults" -Level Verbose

						# Get the default data folder
						if (-not $RestoreDataFolder) {
							$DatabaseRestoreDataFolder = $DestinationServer.DefaultFile  
						}
						else {
							# Set the restore data folder
							if ($RestoreDataFolder.EndsWith("\")) {
								$DatabaseRestoreDataFolder = "$RestoreDataFolder$db"
							}
							else {
								$DatabaseRestoreDataFolder = "$RestoreDataFolder\$db"
							}
						}
                    
						Write-Message -Message "Restore data folder set to $DatabaseRestoreDataFolder" -Level Verbose

						# Get the default log folder
						if (-not $RestoreLogFolder) {
							$DatabaseRestoreLogFolder = $DestinationServer.DefaultLog
						}

						Write-Message -Message "Restore log folder set to $DatabaseRestoreLogFolder" -Level Verbose

						# Check if the restore data folder exists
						if ((Test-DbaSqlPath  -Path $DatabaseRestoreDataFolder -SqlInstance $DestinationSqlInstance -SqlCredential $DestinationCredential)-ne $true) {
							if ($PSCmdlet.ShouldProcess($DestinationServerName, "Creating database restore data folder on $DestinationServerName")) {
								# Try creating the data folder
								try {
                                    Invoke-Command2 -Credential $DestinationCredential -ScriptBlock {
						                Write-Message -Message "Creating data folder $DatabaseRestoreDataFolder" -Level Verbose
							            New-Item -Path $DatabaseRestoreDataFolder -ItemType Directory -Credential $DestinationCredential -Force:$Force | Out-Null
                                    }
								}
								catch {
									Stop-Function -Message "Something went wrong creating the restore data directory. `n$($_.Exception.Message)" -InnerErrorRecord $_ -Target $SourceSqlInstance -Continue
								}
							}
						}

						# Check if the restore log folder exists
						if ((Test-DbaSqlPath  -Path $DatabaseRestoreLogFolder -SqlInstance $DestinationSqlInstance -SqlCredential $DestinationCredential)-ne $true) {
							if ($PSCmdlet.ShouldProcess($DestinationServerName, "Creating database restore log folder on $DestinationServerName")) {
								# Try creating the log folder
								try {
                                    Invoke-Command2 -Credential $DestinationCredential -ScriptBlock {
						               Write-Message -Message "Restore log folder $DatabaseRestoreLogFolder not found. Trying to create it.." -Level Verbose
							            New-Item -Path $DatabaseRestoreLogFolder -ItemType Directory -Credential $DestinationCredential -Force:$Force | Out-Null
                                    }
								}
								catch {
									Stop-Function -Message "Something went wrong creating the restore log directory. `n$($_.Exception.Message)" -InnerErrorRecord $_ -Target $SourceSqlInstance -Continue
								}
							}
						}
					} 
					else {
                    
					}

					# Chech if the full backup patk can be reached
					if ($FullBackupPath) {
						if ((Test-DbaSqlPath -Path $FullBackupPath -SqlInstance $DestinationSqlInstance -SqlCredential $DestinationCredential) -ne $true) {
							Stop-Function -Message ("The path to the full backup could not be reached. Check the path and/or the crdential. `n$($_.Exception.Message)") -InnerErrorRecord $_ -Target $SourceSqlInstance -Continue
						}
					} 
					elseif ($UseExistingFullBackup) {
						Write-Message -Message "No path to the full backup is set. Trying to retrieve the last full backup for $db from $SourceSqlInstance" -Level Verbose

						# Get the last full backup
						$LastBackup = Get-DbaBackupHistory -SqlServer $SourceSqlInstance -Databases $db -LastFull -Credential $SourceSqlCredential

						# Check if there was a last backup
						if ($LastBackup -ne $null) {
							# Check if the source for the last full backup is remote and the backup is on a shared location
							if (($LastBackup.Computername -ne $SourceServerName) -and ($LastBackup[0].Path.StartsWith('\\') -eq $false)) {
								Stop-Function -Message "The last full backup is not located on shared location. `n$($_.Exception.Message)" -InnerErrorRecord $_ -Target $SourceSqlInstance -Continue
							}
							# Test the path to the backup
							elseif ((Test-DbaSqlPath -Path $LastBackup.Path -SqlInstance $SourceSqlInstance -SqlCredential $SourceCredential) -ne $true) {
								Stop-Function -Message "The full backup could not be found on $($LastBackup.Path). Check path and/or credentials. `n$($_.Exception.Message)" -InnerErrorRecord $_ -Target $SourceSqlInstance -Continue
							}
							else {
								$FullBackupPath = $LastBackup.Path  
								Write-Message -Message "Full backup found for $db. Path $FullBackupPath" -Level Verbose    
							}
						}
						else {
							Write-Message -Message "No Full backup found for $db." -Level Output  
						}
					}  
				}

				# Set the copy destination folder to include the database name
				if ($CopyDestinationFolder.EndsWith("\")) {
					$DatabaseCopyDestinationFolder = "$CopyDestinationFolder$db"
				}
				else {
					$DatabaseCopyDestinationFolder = "$CopyDestinationFolder\$db"
				}
				Write-Message -Message "Copy destination folder set to $DatabaseCopyDestinationFolder." -Level Verbose

				# Check if the copy job name is set
				if ($CopyJob) {
					$DatabaseCopyJob = "$CopyJob_$SourceServerName_$db"
				}
				else {
					$DatabaseCopyJob = "LSCopy_$SourceServerName_$db"                    
				}
				Write-Message -Message "Copy job name set to $DatabaseCopyJob" -Level Verbose

				# Check if the copy job schedule name is set
				if ($CopySchedule) {
					$DatabaseCopySchedule = "$CopySchedule_$db"
				}
				else {
					$DatabaseCopySchedule = "LSCopySchedule_$db"
					Write-Message -Message "Copy job schedule name set to $DatabaseCopySchedule" -Level Verbose                    
				}

				# Check if the copy destination folder exists
				if ((Test-DbaSqlPath -Path $DatabaseCopyDestinationFolder -SqlInstance $DestinationSqlInstance -SqlCredential $DestinationCredential) -ne $true) {
					if ($PSCmdlet.ShouldProcess($DestinationServerName, "Creating copy destination folder on $DestinationServerName")) {
						try {
                                Invoke-Command2 -Credential $DestinationCredential -ScriptBlock {
						            Write-Message -Message "Copy destination folder $DatabaseCopyDestinationFolder not found. Trying to create it.. ." -Level Verbose
							        New-Item -Path $DatabaseCopyDestinationFolder -ItemType Directory -Credential $DestinationCredential -Force:$Force | Out-Null
                                }
						}
						catch {
							Stop-Function -Message "Something went wrong creating the database copy destination folder. `n$($_.Exception.Message)" -InnerErrorRecord $_ -Target $DestinationServerName -Continue
						}
					}
				}

				# Check if the restore job name is set
				if ($RestoreJob) {
					$DatabaseRestoreJob = "$RestoreJob_$SourceServerName_$db"
				}
				else {
					$DatabaseRestoreJob = "LSRestore_$DestinationServerName_$db"
				}
				Write-Message -Message "Restore job name set to $DatabaseRestoreJob" -Level Verbose

				# Check if the restore job schedule name is set
				if ($RestoreSchedule) {
					$DatabaseRestoreSchedule = "$RestoreSchedule_$db"
				}
				else {
					$DatabaseRestoreSchedule = "LSRestoreSchedule_$db"
				}
				Write-Message -Message "Restore job schedule name set to $DatabaseRestoreSchedule" -Level Verbose

				# If the database needs to be backed up first
				if ($PSCmdlet.ShouldProcess($SourceSqlInstance, "Backing up database $db")) {
					if ($GenerateFullBackup) {
						Write-Message -Message "Generating full backup." -Level Output
						Write-Message -Message "Backing up database $db to $DatabaseBackupNetworkPath" -Level Output
                    
						$Timestamp = Get-Date -format "yyyyMMddHHmmss"

						$LastBackup = Backup-DbaDatabase -SqlInstance $SourceSqlInstance `
							-SqlCredential $SourceSqlCredential `
							-BackupDirectory $DatabaseBackupNetworkPath `
							-BackupFileName "FullBackup_$db_PreLogShipping_$Timestamp.bak" `
							-Databases $db `
							-Type Full 

						Write-Message -Message "Backup completed." -Level Output

						# Get the last full backup path
						$FullBackupPath = $LastBackup.BackupPath  

						Write-Message -Message "Backup is located at $FullBackupPath" -Level Verbose
					}
				}
            
				# Check of the MonitorServerSecurityMode value is of type string and set the integer value
				if ($PrimaryMonitorServerSecurityMode -notin 0, 1) {
					$PrimaryMonitorServerSecurityMode = switch ($PrimaryMonitorServerSecurityMode) {
						"SQLSERVER" { 0 } "WINDOWS" { 1 } default { 1 }
					}
				}

				# Check the PrimaryMonitorServerSecurityMode if it's SQL Server authentication
				if ($PrimaryMonitorServerSecurityMode -eq 0) {
					if ($PrimaryMonitorServerLogin) {
						Stop-Function -Message "The PrimaryMonitorServerLogin cannot be empty when using SQL Server authentication." -InnerErrorRecord $_ -Target $SourceSqlInstance -Continue
					}

					if ($PrimaryMonitorServerPassword) {
						Stop-Function -Message "The PrimaryMonitorServerPassword cannot be empty when using SQL Server authentication." -InnerErrorRecord $_ -Target $ -Continue
					}
				}

				# Check of the SecondaryMonitorServerSecurityMode value is of type string and set the integer value
				if ($SecondaryMonitorServerSecurityMode -notin 0, 1) {
					$SecondaryMonitorServerSecurityMode = switch ($SecondaryMonitorServerSecurityMode) {
						"SQLSERVER" { 0 } "WINDOWS" { 1 } default { 1 }
					}
				}

				# Check the MonitorServerSecurityMode if it's SQL Server authentication
				if ($SecondaryMonitorServerSecurityMode -eq 0) {
					if ($SecondaryMonitorServerLogin) {
						Stop-Function -Message "The SecondaryMonitorServerLogin cannot be empty when using SQL Server authentication." -InnerErrorRecord $_ -Target $SourceSqlInstance -Continue
					}

					if ($SecondaryMonitorServerPassword) {
						Stop-Function -Message "The SecondaryMonitorServerPassword cannot be empty when using SQL Server authentication." -InnerErrorRecord $_ -Target $SourceSqlInstance -Continue
					}
				}

				# Now that all the checks have been done we can start with the fun stuff !

				# Restore the full backup
				if ($PSCmdlet.ShouldProcess($DestinationSqlInstance, "Restoring database $db to $SecondaryDatabase on $DestinationSqlInstance")) {
					if ($GenerateFullBackup -or $UseExistingFullBackup) {
						try {   
							Write-Message -Message "Start database restore" -Level Output
							if ($NoRecovery -or (-not $Standby)) {
								if ($Force) {
									Restore-DbaDatabase -SqlServer $DestinationSqlInstance `
										-SqlCredential $DestinationSqlCredential `
										-Path $FullBackupPath `
										-DestinationFilePrefix $SecondaryDatabaseSuffix `
										-DestinationDataDirectory $DatabaseRestoreDataFolder `
										-DestinationLogDirectory $DatabaseRestoreLogFolder `
										-DatabaseName $SecondaryDatabase `
										-NoRecovery `
										-WithReplace | Out-Null
								}
								else {
									Restore-DbaDatabase -SqlServer $DestinationSqlInstance `
										-SqlCredential $DestinationSqlCredential `
										-Path $FullBackupPath `
										-DestinationFilePrefix $SecondaryDatabaseSuffix `
										-DestinationDataDirectory $DatabaseRestoreDataFolder `
										-DestinationLogDirectory $DatabaseRestoreLogFolder `
										-DatabaseName $SecondaryDatabase `
										-NoRecovery | Out-Null
								}
							}
                        
							# If the database needs to be in standby
							if ($Standby) {
								# Setup the path to the standby file
								$StandbyFile = "$DatabaseCopyDestinationFolder\$SecondaryDatabase_RollbackUndo.bak"

								if ($DestinationSqlCredential -ne $null) {
									Restore-SqlDatabase -ServerInstance $DestinationSqlInstance `
										-SqlCredential $DestinationSqlCredential `
										-Database $SecondaryDatabase `
										-BackupFile $FullBackupPath `
										-ReplaceDatabase `
										-StandbyFile $StandbyFile 
								}
								else {
									<# 
                                    As soon as the Restore-SqlDatabase is able to restore to standby the code below needs to 
                                    be replaced with the supporting function from dbtools
                                    #>
                                
									# Create the backup device
									$BackupDeviceItem = New-Object Microsoft.SqlServer.Management.Smo.BackupDeviceItem $FullBackupPath, 'File'

									# Create the restore object
									$Restore = New-Object 'Microsoft.SqlServer.Management.Smo.Restore'

									# Set the properties of the restore object
									$Restore.Database = $SecondaryDatabase
									$Restore.Devices.Add($BackupDeviceItem)
									$Restore.StandbyFile = $StandbyFile

									# If force is needed replace the database
									if ($Force) {
										$Restore.ReplaceDatabase = 1
									}

									# Setup the physical file name
									$PhysicalFileName = $SecondaryDatabase

									# Number to use in case of multiple data files
									$DataFileNumber = 0

									# Loop through the files
									foreach ($File in $Restore.ReadFileList($DestinationSqlInstance)) {
										# Create the relocate object to place the files in somewhere else
										$RelocateFile = New-Object 'Microsoft.SqlServer.Management.Smo.RelocateFile'
										$RelocateFile.LogicalFileName = $File.LogicalName

										# Use the number in the physical file name if there are multiple data files
										if ($DataFileNumber -gt 1) {
											$PhysicalFileName += "_$DataFileNumber.ndf"
										}
										else {
											$PhysicalFileName += ".mdf"
										}
                                    
										# Check the type of the file
										if ($File.Type -eq 'D') {

											$RelocateFile.PhysicalFileName = "$DatabaseRestoreDataFolder\$PhysicalFileName"

											$DataFileNumber ++;
										}
										else {
											$RelocateFile.PhysicalFileName = "$DatabaseRestoreLogFolder\$SecondaryDatabase.ldf"
										}

										# Add the relocate objects to the restore
										$Restore.RelocateFiles.Add($RelocateFile) | Out-Null
									}    
									# Execute the restore
									$Restore.SqlRestore($DestinationSqlInstance)
                                
								}
							}
						}
						catch {
							Stop-Function -Message "Something went wrong restoring the secondary database.`n$($_.Exception.Message)" -InnerErrorRecord $_ -Target $SourceSqlInstance -Continue
						}
                    
						Write-Message -Message "Restore completed." -Level Output
					}
				}
            
				#region Set up log shipping on the primary instance
				# Set up log shipping on the primary instance
				if ($PSCmdlet.ShouldProcess($SourceSqlInstance, "Configuring logshipping for primary database $db on $SourceSqlInstance")) {
					try {

						Write-Message -Message "Configuring logshipping for primary database" -Level Output
                        if($PrimaryMonitorServer) {
						    New-DbaLogShippingPrimaryDatabase -SqlInstance $SourceSqlInstance `
						    	-SqlCredential $SourceSqlCredential `
						    	-Database $db `
						    	-BackupDirectory $DatabaseBackupLocalPath `
						    	-BackupJob $DatabaseBackupJob `
						    	-BackupRetention $BackupRetention `
						    	-BackupShare $DatabaseBackupNetworkPath `
						    	-BackupThreshold $BackupThreshold `
						    	-CompressBackup:$CompressBackup `
						    	-HistoryRetention $HistoryRetention `
						    	-MonitorServer $PrimaryMonitorServer `
						    	-MonitorServerSecurityMode $PrimaryMonitorServerSecurityMode `
						    	-MonitorCredential $PrimaryMonitorCredential `
						    	-ThresholdAlertEnabled:$PrimaryThresholdAlertEnabled `
						    	-Force:$Force 
                        }
                        else {
                        	New-DbaLogShippingPrimaryDatabase -SqlInstance $SourceSqlInstance `
						    	-SqlCredential $SourceSqlCredential `
						    	-Database $db `
						    	-BackupDirectory $DatabaseBackupLocalPath `
						    	-BackupJob $DatabaseBackupJob `
						    	-BackupRetention $BackupRetention `
						    	-BackupShare $DatabaseBackupNetworkPath `
						    	-BackupThreshold $BackupThreshold `
						    	-CompressBackup:$CompressBackup `
						    	-HistoryRetention $HistoryRetention `
						    	-ThresholdAlertEnabled:$PrimaryThresholdAlertEnabled `
						    	-Force:$Force 
                        }
                        
						# Check if the backup job needs to be enabled or disabled
						if ($BackupScheduleDisabled) {
							Set-DbaAgentJob -SqlInstance $SourceSqlInstance -SqlCredential $SourceSqlCredential -Job $DatabaseBackupJob -Disabled
							Write-Message -Message "Disabling backup job $DatabaseBackupJob" -Level Output
						}
						else {
							Set-DbaAgentJob -SqlInstance $SourceSqlInstance -SqlCredential $SourceSqlCredential -Job $DatabaseBackupJob -Enabled
							Write-Message -Message "Enabling backup job $DatabaseBackupJob" -Level Output
						}

						Write-Message -Message "Create backup job schedule $DatabaseBackupSchedule" -Level Output

						$BackupJobSchedule = New-DbaAgentSchedule -SqlInstance $SourceSqlInstance `
							-SqlCredential $SourceSqlCredential `
							-Job $DatabaseBackupJob `
							-Schedule $DatabaseBackupSchedule `
							-FrequencyType $BackupScheduleFrequencyType `
							-FrequencyInterval $BackupScheduleFrequencyInterval `
							-FrequencySubdayType $BackupScheduleFrequencySubdayType `
							-FrequencySubdayInterval $BackupScheduleFrequencySubdayInterval `
							-FrequencyRelativeInterval $BackupScheduleFrequencyRelativeInterval `
							-FrequencyRecurrenceFactor $BackupScheduleFrequencyRecurrenceFactor `
							-StartDate $BackupScheduleStartDate `
							-EndDate $BackupScheduleEndDate `
							-StartTime $BackupScheduleStartTime `
							-EndTime $BackupScheduleEndTime `
							-Force:$Force
                  
						Write-Message -Message "Configuring logshipping from primary to secondary database." -Level Output

						New-DbaLogShippingPrimarySecondary -SqlInstance $SourceSqlInstance `
							-SqlCredential $SourceSqlCredential `
							-PrimaryDatabase $db `
							-SecondaryDatabase $SecondaryDatabase `
							-SecondaryServer $DestinationSqlInstance `
							-SecondarySqlCredential $DestinationSqlCredential
					}
					catch {
						Stop-Function -Message "Something went wrong setting up log shipping for primary instance.`n$($_.Exception.Message)" -InnerErrorRecord $_ -Target $SourceSqlInstance -Continue
					}
				}
				#endregion Set up log shipping on the primary instance

				#region Set up log shipping on the secondary instance
				# Set up log shipping on the secondary instance
				if ($PSCmdlet.ShouldProcess($DestinationSqlInstance, "Configuring logshipping for secondary database $SecondaryDatabase on $DestinationSqlInstance")) {
					try {

						Write-Message -Message "Configuring logshipping from secondary database $SecondaryDatabase to primary database $db." -Level Output
                        if($SecondaryMonitorServer) {
						    New-DbaLogShippingSecondaryPrimary -SqlInstance $DestinationSqlInstance `
							    -SqlCredential $DestinationSqlCredential `
							    -BackupSourceDirectory $DatabaseBackupNetworkPath `
							    -BackupDestinationDirectory $DatabaseCopyDestinationFolder `
							    -CopyJob $DatabaseCopyJob `
							    -FileRetentionPeriod $BackupRetention `
							    -MonitorServer $SecondaryMonitorServer `
							    -MonitorServerSecurityMode $SecondaryMonitorServerSecurityMode `
							    -MonitorCredential $SecondaryMonitorCredential `
							    -PrimaryServer $SourceSqlInstance `
							    -PrimaryDatabase $db `
							    -RestoreJob $DatabaseRestoreJob `
							    -Force:$Force
                        }
                        else {
                        	New-DbaLogShippingSecondaryPrimary -SqlInstance $DestinationSqlInstance `
							    -SqlCredential $DestinationSqlCredential `
							    -BackupSourceDirectory $DatabaseBackupNetworkPath `
							    -BackupDestinationDirectory $DatabaseCopyDestinationFolder `
							    -CopyJob $DatabaseCopyJob `
							    -FileRetentionPeriod $BackupRetention `
							    -PrimaryServer $SourceSqlInstance `
							    -PrimaryDatabase $db `
							    -RestoreJob $DatabaseRestoreJob `
							    -Force:$Force
                        }

						Write-Message -Message "Create copy job schedule $DatabaseCopySchedule" -Level Output

						$CopyJobSchedule = New-DbaAgentSchedule -SqlInstance $DestinationSqlInstance `
							-SqlCredential $DestinationSqlCredential `
							-Job $DatabaseCopyJob `
							-Schedule $DatabaseCopySchedule `
							-FrequencyType $CopyScheduleFrequencyType `
							-FrequencyInterval $CopyScheduleFrequencyInterval `
							-FrequencySubdayType $CopyScheduleFrequencySubdayType `
							-FrequencySubdayInterval $CopyScheduleFrequencySubdayInterval `
							-FrequencyRelativeInterval $CopyScheduleFrequencyRelativeInterval `
							-FrequencyRecurrenceFactor $CopyScheduleFrequencyRecurrenceFactor `
							-StartDate $CopyScheduleStartDate `
							-EndDate $CopyScheduleEndDate `
							-StartTime $CopyScheduleStartTime `
							-EndTime $CopyScheduleEndTime `
							-Force:$Force

						Write-Message -Message "Create restore job schedule $DatabaseRestoreSchedule" -Level Output

						$RestoreJobSchedule = New-DbaAgentSchedule -SqlInstance $DestinationSqlInstance `
							-SqlCredential $DestinationSqlCredential `
							-Job $DatabaseRestoreJob `
							-Schedule $DatabaseRestoreSchedule `
							-FrequencyType $RestoreScheduleFrequencyType `
							-FrequencyInterval $RestoreScheduleFrequencyInterval `
							-FrequencySubdayType $RestoreScheduleFrequencySubdayType `
							-FrequencySubdayInterval $RestoreScheduleFrequencySubdayInterval `
							-FrequencyRelativeInterval $RestoreScheduleFrequencyRelativeInterval `
							-FrequencyRecurrenceFactor $RestoreScheduleFrequencyRecurrenceFactor `
							-StartDate $RestoreScheduleStartDate `
							-EndDate $RestoreScheduleEndDate `
							-StartTime $RestoreScheduleStartTime `
							-EndTime $RestoreScheduleEndTime `
							-Force:$Force

						Write-Message -Message "Configuring logshipping for secondary database." -Level Output

						New-DbaLogShippingSecondaryDatabase -SqlInstance $DestinationSqlInstance `
							-SqlCredential $DestinationSqlCredential `
							-SecondaryDatabase $SecondaryDatabase `
							-PrimaryServer $SourceSqlInstance `
							-PrimaryDatabase $db `
							-RestoreDelay $RestoreDelay `
							-RestoreMode $DatabaseStatus `
							-DisconnectUsers:$DisconnectUsers `
							-RestoreThreshold $RestoreThreshold `
							-ThresholdAlertEnabled:$SecondaryThresholdAlertEnabled `
							-HistoryRetention $HistoryRetention

						# Check if the copy job needs to be enabled or disabled
						if ($CopyScheduleDisabled) {
							Set-DbaAgentJob -SqlInstance $DestinationSqlInstance -SqlCredential $DestinationSqlCredential -Job $DatabaseCopyJob -Disabled
						}
						else {
							Set-DbaAgentJob -SqlInstance $DestinationSqlInstance -SqlCredential $DestinationSqlCredential -Job $DatabaseCopyJob -Enabled    
						}

						# Check if the restore job needs to be enabled or disabled
						if ($RestoreScheduleDisabled) {
							Set-DbaAgentJob -SqlInstance $DestinationSqlInstance -SqlCredential $DestinationSqlCredential -Job $DatabaseRestoreJob -Disabled
						}
						else {
							Set-DbaAgentJob -SqlInstance $DestinationSqlInstance -SqlCredential $DestinationSqlCredential -Job $DatabaseRestoreJob -Enabled    
						}

					}
					catch {
						Stop-Function -Message "Something went wrong setting up log shipping for secondary instance.`n$($_.Exception.Message)" -InnerErrorRecord $_ -Target $DestinationSqlInstance -Continue
					}
				}
				#endregion Set up log shipping on the secondary instance

				Write-Message -Message "Completed configuring log shipping for database $db" -Level Output
			}

		}
	}

	end {
		Write-Message -Message "Finished setting up log shipping." -Level Output
	}
}




