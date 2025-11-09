function Invoke-DbaDbLogShipping {
    <#
    .SYNOPSIS
        Invoke-DbaDbLogShipping sets up log shipping for one or more databases

    .DESCRIPTION
        Invoke-DbaDbLogShipping helps to easily set up log shipping for one or more databases.

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
        The copy destination must have at least read/write permission for the secondary instance agent account.

    .PARAMETER SourceSqlInstance
        Source SQL Server instance which contains the databases to be log shipped.
        You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER DestinationSqlInstance
        Destination SQL Server instance which contains the databases to be log shipped.
        You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER SourceCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER DestinationCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which database(s) to configure for log shipping. The database must be in FULL recovery model.
        Use this to target specific databases rather than setting up log shipping for all databases on the source instance.

    .PARAMETER SharedPath
        Specifies the network share path where transaction log backup files will be stored. Must be in UNC format (\\server\\share).
        The function automatically creates a subdirectory for each database under this path. Both source and destination instances need access to this location.
        Mutually exclusive with AzureBaseUrl parameter.

    .PARAMETER LocalPath
        Sets the local backup path on the source server when different from the shared path.
        Use this when the source server accesses the backup location via a local path but other servers need to access it via the network share.
        Not applicable when using Azure blob storage (AzureBaseUrl).

    .PARAMETER AzureBaseUrl
        Specifies the Azure blob storage container URL where transaction log backups will be stored.
        Format: https://storageaccount.blob.core.windows.net/container/
        When specified, traditional file-based copy jobs are skipped as backups go directly to Azure blob storage.
        Mutually exclusive with SharedPath parameter. Requires SQL Server 2012 or later.

    .PARAMETER AzureCredential
        Specifies the SQL Server credential name for Azure storage access. When omitted, uses SAS token authentication with a credential named to match the AzureBaseUrl.
        The credential must exist on both source and destination SQL Server instances before setting up log shipping.

    .PARAMETER BackupJob
        Specifies the prefix for the SQL Agent backup job name that performs transaction log backups.
        The database name is automatically appended to create the full job name. Defaults to 'LSBackup_' if not specified.

    .PARAMETER BackupRetention
        Sets how long backup files are retained before deletion, specified in minutes.
        Defaults to 4320 minutes (72 hours). Consider storage capacity and recovery requirements when setting this value.

    .PARAMETER BackupSchedule
        Name of the backup schedule created for the backup job.
        The parameter works as a prefix where the name of the database will be added to the backup job schedule name.
        Default is "LSBackupSchedule_[databasename]"

    .PARAMETER BackupScheduleDisabled
        Creates the backup job schedule in a disabled state, preventing automatic execution.
        Use this when you want to manually control when log shipping backup jobs start running.

    .PARAMETER BackupScheduleFrequencyType
        Controls how often the backup job runs. Accepts 'Daily' (most common), 'AgentStart', or 'IdleComputer'.
        Daily scheduling allows for regular transaction log backups to maintain the log shipping chain.

    .PARAMETER BackupScheduleFrequencyInterval
        The number of type periods to occur between each execution of the backup job.

    .PARAMETER BackupScheduleFrequencySubdayType
        Specifies the units for the sub-day FrequencyInterval.
        Allowed values are "Time", "Seconds", "Minutes", "Hours"

    .PARAMETER BackupScheduleFrequencySubdayInterval
        Specifies the interval between backup job executions within a day when using Minutes, Seconds, or Hours frequency.
        For example, setting 15 with FrequencySubdayType of 'Minutes' creates backups every 15 minutes.

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
        Sets the alert threshold in minutes for detecting backup delays. An alert is raised if no backup occurs within this timeframe.
        Defaults to 60 minutes. Use shorter intervals for critical databases requiring frequent log backups.

    .PARAMETER CompressBackup
        Enables backup compression for transaction log backups to reduce file size and network transfer time.
        Only available on SQL Server 2008 and later. Uses server default compression setting if not specified.

    .PARAMETER CopyDestinationFolder
        Specifies the destination folder path where backup files are copied on the secondary server.
        The function creates a database-specific subdirectory under this path. Defaults to the secondary server's backup directory if not provided.

    .PARAMETER CopyJob
        Name of the copy job that will be created in the SQL Server agent.
        The parameter works as a prefix where the name of the database will be added to the copy job name.
        The default is "LSBackup_[databasename]"

    .PARAMETER CopyRetention
        The copy retention period in minutes. Default is 4320 / 72 hours

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
        Allowed values are "Time", "Seconds", "Minutes", "Hours"

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
        Forces disconnection of users from the secondary database during transaction log restore operations.
        Use this with standby mode when you need to ensure restores complete successfully despite active connections.

    .PARAMETER FullBackupPath
        Specifies the path to an existing full database backup to initialize the secondary database.
        Use this when you have a recent backup available and want to avoid creating a new full backup for initialization.

    .PARAMETER GenerateFullBackup
        Creates a new full backup of the source database and restores it to initialize the secondary database.
        Use this when no existing backup is available or when you want to ensure the secondary starts with the most current data.

    .PARAMETER HistoryRetention
        Sets how long log shipping history information is kept in the monitor server, specified in minutes.
        Defaults to 14420 minutes (approximately 10 days). Longer retention provides more historical data for troubleshooting.

    .PARAMETER NoRecovery
        Keeps the secondary database in NORECOVERY mode, making it unavailable for read access but ready for continuous log restores.
        This is the default mode and maintains the fastest restore performance for log shipping.

    .PARAMETER NoInitialization
        Skips secondary database initialization, assuming the database already exists in NORECOVERY mode on the destination.
        Use this when you have manually restored the database or used a different method to initialize it.

    .PARAMETER PrimaryMonitorServer
        Specifies the SQL Server instance that monitors the primary server's log shipping operations.
        Defaults to the source instance itself. Use a dedicated monitor server in production environments for centralized monitoring.

    .PARAMETER PrimaryMonitorCredential
        Allows you to login to enter a secure credential. Only needs to be used when the PrimaryMonitorServerSecurityMode is 0 or "sqlserver"
        To use: $scred = Get-Credential, then pass $scred object to the -PrimaryMonitorCredential parameter.

    .PARAMETER PrimaryMonitorServerSecurityMode
        The security mode used to connect to the monitor server for the primary server. Allowed values are 0, "sqlserver", 1, "windows"
        The default is 1 or Windows.

    .PARAMETER PrimaryThresholdAlertEnabled
        Enables the Threshold alert for the primary database

    .PARAMETER RestoreDataFolder
        Sets the destination folder for database data files during secondary database initialization.
        Only used with GenerateFullBackup or UseExistingFullBackup. Defaults to the secondary instance's default data directory if not specified.

    .PARAMETER RestoreLogFolder
        Sets the destination folder for database log files during secondary database initialization.
        Only used with GenerateFullBackup or UseExistingFullBackup. Defaults to the secondary instance's default log directory if not specified.

    .PARAMETER RestoreDelay
        Introduces a delay in minutes before applying transaction log restores on the secondary database.
        Defaults to 0 (no delay). Use this to create a time buffer for recovering from accidental data changes on the primary.

    .PARAMETER RestoreAlertThreshold
        Sets the alert threshold in minutes for detecting restore operation delays on the secondary database.
        An alert is generated if no restore occurs within this timeframe. Defaults to 45 minutes.

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
        Allowed values are "Time", "Seconds", "Minutes", "Hours"

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
        Specifies the maximum time in minutes allowed between restore operations before triggering an alert.
        Defaults to 45 minutes. Set this based on your RTO requirements and backup frequency.

    .PARAMETER SecondaryDatabasePrefix
        Adds a prefix to the secondary database name to distinguish it from the primary database.
        Useful when the secondary database resides on the same instance as the primary or for naming conventions.

    .PARAMETER SecondaryDatabaseSuffix
        Adds a suffix to the secondary database name to distinguish it from the primary database.
        Common suffixes include '_LS' for log shipping or '_DR' for disaster recovery. Automatically applied when source and destination are the same instance.

    .PARAMETER SecondaryMonitorServer
        Is the name of the monitor server for the secondary server.
        Defaults to monitor on the instance provided via DestinationSqlInstance param.

    .PARAMETER SecondaryMonitorCredential
        Allows you to login to enter a secure credential. Only needs to be used when the SecondaryMonitorServerSecurityMode is 0 or "sqlserver"
        To use: $scred = Get-Credential, then pass $scred object to the -SecondaryMonitorCredential parameter.

    .PARAMETER SecondaryMonitorServerSecurityMode
        The security mode used to connect to the monitor server for the secondary server. Allowed values are 0, "sqlserver", 1, "windows"
        The default is 1 or Windows.

    .PARAMETER SecondaryThresholdAlertEnabled
        Enables the Threshold alert for the secondary database

    .PARAMETER Standby
        Places the secondary database in STANDBY mode, allowing read-only access for reporting purposes.
        Users are disconnected during log restores. Alternative to NORECOVERY mode when you need read access to secondary data.

    .PARAMETER StandbyDirectory
        Specifies the directory where standby files (.tuf) are created when using STANDBY mode.
        Required when using the Standby parameter. These files contain uncommitted transactions that are temporarily backed out during restore operations.

    .PARAMETER UseExistingFullBackup
        Uses the most recent full backup from backup history to initialize the secondary database.
        The function automatically locates and uses the latest full backup of the source database for initialization.

    .PARAMETER UseBackupFolder
        Specifies a folder containing backup files (full and/or differential) to initialize the secondary database.
        The function processes all backup files in the folder to bring the secondary database up to the latest available point in time.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        Bypasses confirmations and applies default values for missing parameters like copy destination folder.
        Also removes existing schedules with the same name and sets automatic database suffix when source and destination instances are identical.

    .NOTES
        Tags: LogShipping
        Author: Sander Stad (@sqlstad), sqlstad.nl + Claude (Azure blob storage support)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbLogShipping

    .EXAMPLE
        PS C:\> $params = @{
        >> SourceSqlInstance = 'sql1'
        >> DestinationSqlInstance = 'sql2'
        >> Database = 'db1'
        >> SharedPath= '\\sql1\logshipping'
        >> LocalPath= 'D:\Data\logshipping'
        >> BackupScheduleFrequencyType = 'daily'
        >> BackupScheduleFrequencyInterval = 1
        >> CompressBackup = $true
        >> CopyScheduleFrequencyType = 'daily'
        >> CopyScheduleFrequencyInterval = 1
        >> GenerateFullBackup = $true
        >> RestoreScheduleFrequencyType = 'daily'
        >> RestoreScheduleFrequencyInterval = 1
        >> SecondaryDatabaseSuffix = 'LS'
        >> CopyDestinationFolder = '\\sql2\logshippingdest'
        >> Force = $true
        >> }
        >>
        PS C:\> Invoke-DbaDbLogShipping @params

        Sets up log shipping for database "db1" with the backup path to a network share allowing local backups.
        It creates daily schedules for the backup, copy and restore job with all the defaults to be executed every 15 minutes daily.
        The secondary database will be called "db1_LS".

    .EXAMPLE
        PS C:\> $params = @{
        >> SourceSqlInstance = 'sql1'
        >> DestinationSqlInstance = 'sql2'
        >> Database = 'db1'
        >> SharedPath= '\\sql1\logshipping'
        >> GenerateFullBackup = $true
        >> Force = $true
        >> }
        >>
        PS C:\> Invoke-DbaDbLogShipping @params

        Sets up log shipping with all defaults except that a backup file is generated.
        The script will show a message that the copy destination has not been supplied and asks if you want to use the default which would be the backup directory of the secondary server with the folder "logshipping" i.e. "D:\SQLBackup\Logshiping".

    .EXAMPLE
        PS C:\> # First, create the SAS credential on both instances
        PS C:\> $azureUrl = "https://mystorageaccount.blob.core.windows.net/logshipping"
        PS C:\> $cred = Get-Credential -Message "Paste SAS token (without leading ?) in password field" -UserName "SHARED ACCESS SIGNATURE"
        PS C:\> $splatCred = @{
        >> SqlInstance    = "sql1", "sql2"
        >> Name           = $azureUrl
        >> Identity       = $cred.UserName
        >> SecurePassword = $cred.Password
        >> }
        PS C:\> New-DbaCredential @splatCred
        PS C:\>
        PS C:\> # Then set up log shipping
        PS C:\> $splatLogShipping = @{
        >> SourceSqlInstance        = "sql1"
        >> DestinationSqlInstance   = "sql2"
        >> Database                 = "db1"
        >> AzureBaseUrl             = $azureUrl
        >> BackupScheduleFrequencyType = "daily"
        >> BackupScheduleFrequencyInterval = 1
        >> RestoreScheduleFrequencyType = "daily"
        >> RestoreScheduleFrequencyInterval = 1
        >> GenerateFullBackup       = $true
        >> Force                    = $true
        >> }
        PS C:\> Invoke-DbaDbLogShipping @splatLogShipping

        Sets up log shipping for database "db1" to Azure blob storage using SAS token authentication.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]

    param(
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Alias("SourceServerInstance", "SourceSqlServerSqlServer", "Source")]
        [DbaInstanceParameter]$SourceSqlInstance,
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Alias("DestinationServerInstance", "DestinationSqlServer", "Destination")]
        [DbaInstanceParameter[]]$DestinationSqlInstance,
        [System.Management.Automation.PSCredential]
        $SourceSqlCredential,
        [System.Management.Automation.PSCredential]
        $SourceCredential,
        [System.Management.Automation.PSCredential]
        $DestinationSqlCredential,
        [System.Management.Automation.PSCredential]
        $DestinationCredential,
        [Parameter(Mandatory, ValueFromPipeline)]
        [object[]]$Database,
        [Alias("BackupNetworkPath")]
        [string]$SharedPath,
        [Alias("BackupLocalPath")]
        [string]$LocalPath,
        [string]$AzureBaseUrl,
        [string]$AzureCredential,
        [string]$BackupJob,
        [int]$BackupRetention,
        [string]$BackupSchedule,
        [switch]$BackupScheduleDisabled,
        [ValidateSet("Daily", "Weekly", "AgentStart", "IdleComputer")]
        [object]$BackupScheduleFrequencyType,
        [object[]]$BackupScheduleFrequencyInterval,
        [ValidateSet('Time', 'Seconds', 'Minutes', 'Hours')]
        [object]$BackupScheduleFrequencySubdayType,
        [int]$BackupScheduleFrequencySubdayInterval,
        [ValidateSet('Unused', 'First', 'Second', 'Third', 'Fourth', 'Last')]
        [object]$BackupScheduleFrequencyRelativeInterval,
        [int]$BackupScheduleFrequencyRecurrenceFactor,
        [string]$BackupScheduleStartDate,
        [string]$BackupScheduleEndDate,
        [string]$BackupScheduleStartTime,
        [string]$BackupScheduleEndTime,
        [int]$BackupThreshold,
        [switch]$CompressBackup,
        [string]$CopyDestinationFolder,
        [string]$CopyJob,
        [int]$CopyRetention,
        [string]$CopySchedule,
        [switch]$CopyScheduleDisabled,
        [ValidateSet("Daily", "Weekly", "AgentStart", "IdleComputer")]
        [object]$CopyScheduleFrequencyType,
        [object[]]$CopyScheduleFrequencyInterval,
        [ValidateSet('Time', 'Seconds', 'Minutes', 'Hours')]
        [object]$CopyScheduleFrequencySubdayType,
        [int]$CopyScheduleFrequencySubdayInterval,
        [ValidateSet('Unused', 'First', 'Second', 'Third', 'Fourth', 'Last')]
        [object]$CopyScheduleFrequencyRelativeInterval,
        [int]$CopyScheduleFrequencyRecurrenceFactor,
        [string]$CopyScheduleStartDate,
        [string]$CopyScheduleEndDate,
        [string]$CopyScheduleStartTime,
        [string]$CopyScheduleEndTime,
        [switch]$DisconnectUsers,
        [string]$FullBackupPath,
        [switch]$GenerateFullBackup,
        [int]$HistoryRetention,
        [switch]$NoRecovery,
        [switch]$NoInitialization,
        [string]$PrimaryMonitorServer,
        [System.Management.Automation.PSCredential]
        $PrimaryMonitorCredential,
        [ValidateSet(0, "sqlserver", 1, "windows")]
        [object]$PrimaryMonitorServerSecurityMode,
        [switch]$PrimaryThresholdAlertEnabled,
        [string]$RestoreDataFolder,
        [string]$RestoreLogFolder,
        [int]$RestoreDelay,
        [int]$RestoreAlertThreshold,
        [string]$RestoreJob,
        [int]$RestoreRetention,
        [string]$RestoreSchedule,
        [switch]$RestoreScheduleDisabled,
        [ValidateSet("Daily", "Weekly", "AgentStart", "IdleComputer")]
        [object]$RestoreScheduleFrequencyType,
        [object[]]$RestoreScheduleFrequencyInterval,
        [ValidateSet('Time', 'Seconds', 'Minutes', 'Hours')]
        [object]$RestoreScheduleFrequencySubdayType,
        [int]$RestoreScheduleFrequencySubdayInterval,
        [ValidateSet('Unused', 'First', 'Second', 'Third', 'Fourth', 'Last')]
        [object]$RestoreScheduleFrequencyRelativeInterval,
        [int]$RestoreScheduleFrequencyRecurrenceFactor,
        [string]$RestoreScheduleStartDate,
        [string]$RestoreScheduleEndDate,
        [string]$RestoreScheduleStartTime,
        [string]$RestoreScheduleEndTime,
        [int]$RestoreThreshold,
        [string]$SecondaryDatabasePrefix,
        [string]$SecondaryDatabaseSuffix,
        [string]$SecondaryMonitorServer,
        [System.Management.Automation.PSCredential]
        $SecondaryMonitorCredential,
        [ValidateSet(0, "sqlserver", 1, "windows")]
        [object]$SecondaryMonitorServerSecurityMode,
        [switch]$SecondaryThresholdAlertEnabled,
        [switch]$Standby,
        [string]$StandbyDirectory,
        [switch]$UseExistingFullBackup,
        [string]$UseBackupFolder,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        Write-Message -Message "Started log shipping for $SourceSqlInstance to $DestinationSqlInstance" -Level Verbose

        # Try connecting to the instance
        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $SourceSqlInstance -SqlCredential $SourceSqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SourceSqlInstance
            return
        }


        # Check the instance if it is a named instance
        $SourceServerName, $SourceInstanceName = $SourceSqlInstance.FullName.Split("\")

        if ($null -eq $SourceInstanceName) {
            $SourceInstanceName = "MSSQLSERVER"
        }

        # Set up regex strings for several checks
        $RegexDate = '(?<!\d)(?:(?:(?:1[6-9]|[2-9]\d)?\d{2})(?:(?:(?:0[13578]|1[02])31)|(?:(?:0[1,3-9]|1[0-2])(?:29|30)))|(?:(?:(?:(?:1[6-9]|[2-9]\d)?(?:0[48]|[2468][048]|[13579][26])|(?:(?:16|[2468][048]|[3579][26])00)))0229)|(?:(?:1[6-9]|[2-9]\d)?\d{2})(?:(?:0?[1-9])|(?:1[0-2]))(?:0?[1-9]|1\d|2[0-8]))(?!\d)'
        $RegexTime = '^(?:(?:([01]?\d|2[0-3]))?([0-5]?\d))?([0-5]?\d)$'
        $RegexUnc = '^\\(?:\\[^<>:`"/\\|?*]+)+$'
        $RegexAzureUrl = '^https?://[a-z0-9]{3,24}\.blob\.core\.windows\.net/[a-z0-9]([a-z0-9\-]*[a-z0-9])?/?'

        # Validate mutually exclusive parameters for backup destination
        if (-not (Test-Bound -ParameterName "SharedPath", "AzureBaseUrl" -Min 1 -Max 1)) {
            Stop-Function -Message "You must specify either -SharedPath (for traditional file share log shipping) or -AzureBaseUrl (for Azure blob storage log shipping), but not both." -Target $SourceSqlInstance
            return
        }

        # Check the connection timeout
        if ($SourceServer.ConnectionContext.StatementTimeout -ne 0) {
            $SourceServer.ConnectionContext.StatementTimeout = 0
            Write-Message -Message "Connection timeout of $SourceServer is set to 0" -Level Verbose
        }

        # Check if using Azure blob storage or traditional file share
        $UseAzure = $PSBoundParameters.ContainsKey("AzureBaseUrl")

        if ($UseAzure) {
            # Validate Azure URL format
            Write-Message -Message "Using Azure blob storage: $AzureBaseUrl" -Level Verbose

            # Trim trailing slashes
            $AzureBaseUrl = $AzureBaseUrl.TrimEnd("/")

            if ($AzureBaseUrl -notmatch $RegexAzureUrl) {
                Stop-Function -Message "Azure blob storage URL $AzureBaseUrl must be in the format https://storageaccount.blob.core.windows.net/container (example: https://mystorageaccount.blob.core.windows.net/logshipping)" -Target $SourceSqlInstance
                return
            }

            # Check SQL Server version (Azure backup requires SQL Server 2012+)
            if ($SourceServer.Version.Major -lt 11) {
                Stop-Function -Message "Azure blob storage backup requires SQL Server 2012 or later. Source instance is version $($SourceServer.Version.Major)" -Target $SourceSqlInstance
                return
            }

            # For Azure, we'll use the URL as both the backup directory and share
            $SharedPath = $AzureBaseUrl
            $LocalPath = $AzureBaseUrl
        } else {
            # Check the backup network path
            Write-Message -Message "Testing backup network path $SharedPath" -Level Verbose
            if ((Test-DbaPath -Path $SharedPath -SqlInstance $SourceSqlInstance -SqlCredential $SourceSqlCredential) -ne $true) {
                Stop-Function -Message "Backup network path $SharedPath is not valid or can't be reached." -Target $SourceSqlInstance
                return
            } elseif ($SharedPath -notmatch $RegexUnc) {
                Stop-Function -Message "Backup network path $SharedPath has to be in the form of \\server\share." -Target $SourceSqlInstance
                return
            }
        }

        # Check the backup compression
        if ($SourceServer.Version.Major -gt 9) {
            if ($CompressBackup) {
                Write-Message -Message "Setting backup compression to 1." -Level Verbose
                [bool]$BackupCompression = 1
            } else {
                $backupServerSetting = (Get-DbaSpConfigure -SqlInstance $SourceSqlInstance -SqlCredential $SourceSqlCredential -ConfigName DefaultBackupCompression).ConfiguredValue
                Write-Message -Message "Setting backup compression to default server setting $backupServerSetting." -Level Verbose
                [bool]$BackupCompression = $backupServerSetting
            }
        } else {
            Write-Message -Message "Source server $SourceServer does not support backup compression" -Level Verbose
        }

        # Check the database parameter
        if ($Database) {
            foreach ($db in $Database) {
                if ($db -notin $SourceServer.Databases.Name) {
                    Stop-Function -Message "Database $db cannot be found on instance $SourceSqlInstance" -Target $SourceSqlInstance
                }

                $DatabaseCollection = $SourceServer.Databases | Where-Object { $_.Name -in $Database }
            }
        } else {
            Stop-Function -Message "Please supply a database to set up log shipping for" -Target $SourceSqlInstance -Continue
        }

        # Set the database mode
        if ($Standby) {
            $DatabaseStatus = 1
            Write-Message -Message "Destination database status set to STANDBY" -Level Verbose
        } else {
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
            $RestoreThreshold = 45
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

        # Checking for contradicting variables
        if ($NoInitialization -and ($GenerateFullBackup -or $UseExistingFullBackup)) {
            Stop-Function -Message "Cannot use -NoInitialization with -GenerateFullBackup or -UseExistingFullBackup" -Target $DestinationSqlInstance
            return
        }

        if ($UseBackupFolder -and ($GenerateFullBackup -or $NoInitialization -or $UseExistingFullBackup)) {
            Stop-Function -Message "Cannot use -UseBackupFolder with -GenerateFullBackup, -NoInitialization or -UseExistingFullBackup" -Target $DestinationSqlInstance
            return
        }

        # Check the subday interval
        if (($BackupScheduleFrequencySubdayType -in 2, "Seconds", 4, "Minutes") -and (-not ($BackupScheduleFrequencySubdayInterval -ge 1 -or $BackupScheduleFrequencySubdayInterval -le 59))) {
            Stop-Function -Message "Backup subday interval $BackupScheduleFrequencySubdayInterval must be between 1 and 59 when subday type is 2, 'Seconds', 4 or 'Minutes'" -Target $SourceSqlInstance
            return
        } elseif (($BackupScheduleFrequencySubdayType -in 8, "Hours") -and (-not ($BackupScheduleFrequencySubdayInterval -ge 1 -and $BackupScheduleFrequencySubdayInterval -le 23))) {
            Stop-Function -Message "Backup Subday interval $BackupScheduleFrequencySubdayInterval must be between 1 and 23 when subday type is 8 or 'Hours" -Target $SourceSqlInstance
            return
        }

        # Check the subday interval
        if (($CopyScheduleFrequencySubdayType -in 2, "Seconds", 4, "Minutes") -and (-not ($CopyScheduleFrequencySubdayInterval -ge 1 -or $CopyScheduleFrequencySubdayInterval -le 59))) {
            Stop-Function -Message "Copy subday interval $CopyScheduleFrequencySubdayInterval must be between 1 and 59 when subday type is 2, 'Seconds', 4 or 'Minutes'" -Target $DestinationSqlInstance
            return
        } elseif (($CopyScheduleFrequencySubdayType -in 8, "Hours") -and (-not ($CopyScheduleFrequencySubdayInterval -ge 1 -and $CopyScheduleFrequencySubdayInterval -le 23))) {
            Stop-Function -Message "Copy subday interval $CopyScheduleFrequencySubdayInterval must be between 1 and 23 when subday type is 8 or 'Hours'" -Target $DestinationSqlInstance
            return
        }

        # Check the subday interval
        if (($RestoreScheduleFrequencySubdayType -in 2, "Seconds", 4, "Minutes") -and (-not ($RestoreScheduleFrequencySubdayInterval -ge 1 -or $RestoreScheduleFrequencySubdayInterval -le 59))) {
            Stop-Function -Message "Restore subday interval $RestoreScheduleFrequencySubdayInterval must be between 1 and 59 when subday type is 2, 'Seconds', 4 or 'Minutes'" -Target $DestinationSqlInstance
            return
        } elseif (($RestoreScheduleFrequencySubdayType -in 8, "Hours") -and (-not ($RestoreScheduleFrequencySubdayInterval -ge 1 -and $RestoreScheduleFrequencySubdayInterval -le 23))) {
            Stop-Function -Message "Restore subday interval $RestoreScheduleFrequencySubdayInterval must be between 1 and 23 when subday type is 8 or 'Hours" -Target $DestinationSqlInstance
            return
        }

        # Check the backup start date
        if (-not $BackupScheduleStartDate) {
            $BackupScheduleStartDate = (Get-Date -format "yyyyMMdd")
            Write-Message -Message "Backup start date set to $BackupScheduleStartDate" -Level Verbose
        } else {
            if ($BackupScheduleStartDate -notmatch $RegexDate) {
                Stop-Function -Message "Backup start date $BackupScheduleStartDate needs to be a valid date with format yyyyMMdd" -Target $SourceSqlInstance
                return
            }
        }

        # Check the back start time
        if (-not $BackupScheduleStartTime) {
            $BackupScheduleStartTime = '000000'
            Write-Message -Message "Backup start time set to $BackupScheduleStartTime" -Level Verbose
        } elseif ($BackupScheduleStartTime -notmatch $RegexTime) {
            Stop-Function -Message  "Backup start time $BackupScheduleStartTime needs to match between '000000' and '235959'" -Target $SourceSqlInstance
            return
        }

        # Check the back end time
        if (-not $BackupScheduleEndTime) {
            $BackupScheduleEndTime = '235959'
            Write-Message -Message "Backup end time set to $BackupScheduleEndTime" -Level Verbose
        } elseif ($BackupScheduleStartTime -notmatch $RegexTime) {
            Stop-Function -Message  "Backup end time $BackupScheduleStartTime needs to match between '000000' and '235959'" -Target $SourceSqlInstance
            return
        }

        # Check the backup end date
        if (-not $BackupScheduleEndDate) {
            $BackupScheduleEndDate = '99991231'
        } elseif ($BackupScheduleEndDate -notmatch $RegexDate) {
            Stop-Function -Message "Backup end date $BackupScheduleEndDate needs to be a valid date with format yyyyMMdd" -Target $SourceSqlInstance
            return
        }

        # Check the copy start date
        if (-not $CopyScheduleStartDate) {
            $CopyScheduleStartDate = (Get-Date -format "yyyyMMdd")
            Write-Message -Message "Copy start date set to $CopyScheduleStartDate" -Level Verbose
        } else {
            if ($CopyScheduleStartDate -notmatch $RegexDate) {
                Stop-Function -Message "Copy start date $CopyScheduleStartDate needs to be a valid date with format yyyyMMdd" -Target $SourceSqlInstance
                return
            }
        }

        # Check the copy end date
        if (-not $CopyScheduleEndDate) {
            $CopyScheduleEndDate = '99991231'
        } elseif ($CopyScheduleEndDate -notmatch $RegexDate) {
            Stop-Function -Message "Copy end date $CopyScheduleEndDate needs to be a valid date with format yyyyMMdd" -Target $SourceSqlInstance
            return
        }

        # Check the copy start time
        if (-not $CopyScheduleStartTime) {
            $CopyScheduleStartTime = '000000'
            Write-Message -Message "Copy start time set to $CopyScheduleStartTime" -Level Verbose
        } elseif ($CopyScheduleStartTime -notmatch $RegexTime) {
            Stop-Function -Message  "Copy start time $CopyScheduleStartTime needs to match between '000000' and '235959'" -Target $SourceSqlInstance
            return
        }

        # Check the copy end time
        if (-not $CopyScheduleEndTime) {
            $CopyScheduleEndTime = '235959'
            Write-Message -Message "Copy end time set to $CopyScheduleEndTime" -Level Verbose
        } elseif ($CopyScheduleEndTime -notmatch $RegexTime) {
            Stop-Function -Message  "Copy end time $CopyScheduleEndTime needs to match between '000000' and '235959'" -Target $SourceSqlInstance
            return
        }

        # Check the restore start date
        if (-not $RestoreScheduleStartDate) {
            $RestoreScheduleStartDate = (Get-Date -format "yyyyMMdd")
            Write-Message -Message "Restore start date set to $RestoreScheduleStartDate" -Level Verbose
        } else {
            if ($RestoreScheduleStartDate -notmatch $RegexDate) {
                Stop-Function -Message "Restore start date $RestoreScheduleStartDate needs to be a valid date with format yyyyMMdd" -Target $SourceSqlInstance
                return
            }
        }

        # Check the restore end date
        if (-not $RestoreScheduleEndDate) {
            $RestoreScheduleEndDate = '99991231'
        } elseif ($RestoreScheduleEndDate -notmatch $RegexDate) {
            Stop-Function -Message "Restore end date $RestoreScheduleEndDate needs to be a valid date with format yyyyMMdd" -Target $SourceSqlInstance
            return
        }

        # Check the restore start time
        if (-not $RestoreScheduleStartTime) {
            $RestoreScheduleStartTime = '000000'
            Write-Message -Message "Restore start time set to $RestoreScheduleStartTime" -Level Verbose
        } elseif ($RestoreScheduleStartTime -notmatch $RegexTime) {
            Stop-Function -Message  "Restore start time $RestoreScheduleStartTime needs to match between '000000' and '235959'" -Target $SourceSqlInstance
            return
        }

        # Check the restore end time
        if (-not $RestoreScheduleEndTime) {
            $RestoreScheduleEndTime = '235959'
            Write-Message -Message "Restore end time set to $RestoreScheduleEndTime" -Level Verbose
        } elseif ($RestoreScheduleEndTime -notmatch $RegexTime) {
            Stop-Function -Message  "Restore end time $RestoreScheduleEndTime needs to match between '000000' and '235959'" -Target $SourceSqlInstance
            return
        }
    }

    process {

        if (Test-FunctionInterrupt) { return }

        foreach ($destInstance in $DestinationSqlInstance) {

            $setupResult = "Success"
            $comment = ""

            # Try connecting to the instance
            try {
                $destinationServer = Connect-DbaInstance -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destInstance -Continue
            }

            $DestinationServerName, $DestinationInstanceName = $destInstance.FullName.Split("\")

            if ($null -eq $DestinationInstanceName) {
                $DestinationInstanceName = "MSSQLSERVER"
            }

            $IsDestinationLocal = $false

            # Check if it's local or remote
            if ($DestinationServerName -in ".", "localhost", $env:ServerName, "127.0.0.1") {
                $IsDestinationLocal = $true
            }

            # Check the instance names and the database settings
            if (($SourceSqlInstance -eq $destInstance) -and (-not $SecondaryDatabasePrefix -or $SecondaryDatabaseSuffix)) {
                $setupResult = "Failed"
                $comment = "The destination database is the same as the source"
                Stop-Function -Message "The destination database is the same as the source`nPlease enter a prefix or suffix using -SecondaryDatabasePrefix or -SecondaryDatabaseSuffix." -Target $SourceSqlInstance
                return
            }

            if ($DestinationServer.ConnectionContext.StatementTimeout -ne 0) {
                $DestinationServer.ConnectionContext.StatementTimeout = 0
                Write-Message -Message "Connection timeout of $DestinationServer is set to 0" -Level Verbose
            }

            # Check the copy destination
            if (-not $CopyDestinationFolder) {
                if ($UseAzure) {
                    # For Azure, use the same URL as source (no actual copy needed)
                    $CopyDestinationFolder = $AzureBaseUrl
                    Write-Message -Message "Using Azure blob storage URL for copy destination (no local copy): $CopyDestinationFolder" -Level Verbose
                } else {
                    # Make a default copy destination by retrieving the backup folder and adding a directory
                    $CopyDestinationFolder = "$($DestinationServer.Settings.BackupDirectory)\Logshipping"

                    # Check to see if the path already exists
                    Write-Message -Message "Testing copy destination path $CopyDestinationFolder" -Level Verbose
                    if (Test-DbaPath -Path $CopyDestinationFolder -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential) {
                        Write-Message -Message "Copy destination $CopyDestinationFolder already exists" -Level Verbose
                    } else {
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
                                            $null = New-Item -Path $CopyDestinationFolder -ItemType Directory -Force:$Force
                                        }
                                    }
                                    # If the server is local and the credential is set
                                    elseif ($DestinationCredential) {
                                        Invoke-Command2 -Credential $DestinationCredential -ScriptBlock {
                                            Write-Message -Message "Creating copy destination folder $CopyDestinationFolder" -Level Verbose
                                            $null = New-Item -Path $CopyDestinationFolder -ItemType Directory -Force:$Force
                                        }
                                    }
                                    # If the server is local and the credential is not set
                                    else {
                                        Write-Message -Message "Creating copy destination folder $CopyDestinationFolder" -Level Verbose
                                        $null = New-Item -Path $CopyDestinationFolder -ItemType Directory -Force:$Force
                                    }
                                    Write-Message -Message "Copy destination $CopyDestinationFolder created." -Level Verbose
                                } catch {
                                    $setupResult = "Failed"
                                    $comment = "Something went wrong creating the copy destination folder"
                                    Stop-Function -Message "Something went wrong creating the copy destination folder $CopyDestinationFolder. `n$_" -Target $destInstance -ErrorRecord $_
                                    return
                                }
                            }
                            1 {
                                $setupResult = "Failed"
                                $comment = "Copy destination is a mandatory parameter"
                                Stop-Function -Message "Copy destination is a mandatory parameter. Please make sure the value is entered." -Target $destInstance
                                return
                            }
                        } # switch
                    } # if not force
                    else {
                        # Try to create the copy destination on the local server
                        try {
                            Write-Message -Message "Creating copy destination folder $CopyDestinationFolder" -Level Verbose
                            $null = New-Item -Path $CopyDestinationFolder -ItemType Directory -Force:$Force
                            Write-Message -Message "Copy destination $CopyDestinationFolder created." -Level Verbose
                        } catch {
                            $setupResult = "Failed"
                            $comment = "Something went wrong creating the copy destination folder"
                            Stop-Function -Message "Something went wrong creating the copy destination folder $CopyDestinationFolder. `n$_" -Target $destInstance -ErrorRecord $_
                            return
                        }
                        } # else not force
                    } # if test path copy destination
                } # else not Azure
            } # if not copy destination

            # Validate copy destination (skip for Azure since it's a URL)
            if (-not $UseAzure) {
                Write-Message -Message "Testing copy destination path $CopyDestinationFolder" -Level Verbose
                if ((Test-DbaPath -Path $CopyDestinationFolder -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential) -ne $true) {
                    $setupResult = "Failed"
                    $comment = "Copy destination folder $CopyDestinationFolder is not valid or can't be reached"
                    Stop-Function -Message "Copy destination folder $CopyDestinationFolder is not valid or can't be reached." -Target $destInstance
                    return
                } elseif ($CopyDestinationFolder.StartsWith("\\") -and $CopyDestinationFolder -notmatch $RegexUnc) {
                    $setupResult = "Failed"
                    $comment = "Copy destination folder $CopyDestinationFolder has to be in the form of \\server\share"
                    Stop-Function -Message "Copy destination folder $CopyDestinationFolder has to be in the form of \\server\share." -Target $destInstance
                    return
                }
            }

            if (-not ($SecondaryDatabasePrefix -or $SecondaryDatabaseSuffix) -and ($SourceServer.Name -eq $DestinationServer.Name) -and ($SourceServer.InstanceName -eq $DestinationServer.InstanceName)) {
                if ($Force) {
                    $SecondaryDatabaseSuffix = "_LS"
                } else {
                    $setupResult = "Failed"
                    $comment = "Destination database is the same as source database"
                    Stop-Function -Message "Destination database is the same as source database.`nPlease check the secondary server, database prefix or suffix or use -Force to set the secondary database using a suffix." -Target $SourceSqlInstance
                    return
                }
            }

            # Check if standby is being used
            if ($Standby) {
                # Check the stand-by directory (skip for Azure SQL as it manages storage)
                if ($StandbyDirectory) {
                    # Check if the path is reachable for the destination server
                    if (-not $DestinationServer.IsAzure) {
                        if ((Test-DbaPath -Path $StandbyDirectory -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential) -ne $true) {
                            $setupResult = "Failed"
                            $comment = "The directory $StandbyDirectory cannot be reached by the destination instance"
                            Stop-Function -Message "The directory $StandbyDirectory cannot be reached by the destination instance. Please check the permission and credentials." -Target $destInstance
                            return
                        }
                    }
                } elseif (-not $StandbyDirectory -and $Force) {
                    $StandbyDirectory = $destInstance.BackupDirectory
                    Write-Message -Message "Stand-by directory was not set. Setting it to $StandbyDirectory" -Level Verbose
                } else {
                    $setupResult = "Failed"
                    $comment = "Please set the parameter -StandbyDirectory when using -Standby"
                    Stop-Function -Message "Please set the parameter -StandbyDirectory when using -Standby" -Target $SourceSqlInstance
                    return
                }
            }

            # Loop through each of the databases
            foreach ($db in $DatabaseCollection) {

                # Check the status of the database
                if ($db.RecoveryModel -ne 'Full') {
                    $setupResult = "Failed"
                    $comment = "Database $db is not in FULL recovery mode"

                    Stop-Function -Message  "Database $db is not in FULL recovery mode" -Target $SourceSqlInstance -Continue
                }

                # Set the intital destination database
                $SecondaryDatabase = $db.Name

                # Set the database prefix
                if ($SecondaryDatabasePrefix) {
                    $SecondaryDatabase = "$SecondaryDatabasePrefix$($db.Name)"
                }

                # Set the database suffix
                if ($SecondaryDatabaseSuffix) {
                    $SecondaryDatabase += $SecondaryDatabaseSuffix
                }

                # Check is the database is already initialized a check if the database exists on the secondary instance
                if ($NoInitialization -and ($DestinationServer.Databases.Name -notcontains $SecondaryDatabase)) {
                    $setupResult = "Failed"
                    $comment = "Database $SecondaryDatabase needs to be initialized before log shipping setting can continue"

                    Stop-Function -Message "Database $SecondaryDatabase needs to be initialized before log shipping setting can continue." -Target $SourceSqlInstance -Continue
                }

                # Check the local backup path
                if ($LocalPath) {
                    if ($LocalPath.EndsWith("\")) {
                        $DatabaseLocalPath = "$LocalPath$($db.Name)"
                    } else {
                        $DatabaseLocalPath = "$LocalPath\$($db.Name)"
                    }
                } else {
                    $LocalPath = $SharedPath

                    if ($LocalPath.EndsWith("\")) {
                        $DatabaseLocalPath = "$LocalPath$($db.Name)"
                    } else {
                        $DatabaseLocalPath = "$LocalPath\$($db.Name)"
                    }
                }
                Write-Message -Message "Backup local path set to $DatabaseLocalPath." -Level Verbose

                # Setting the backup network path for the database
                if ($UseAzure) {
                    # For Azure, append database name to URL path
                    $DatabaseSharedPath = "$SharedPath/$($db.Name)"
                    $DatabaseLocalPath = $DatabaseSharedPath
                    Write-Message -Message "Azure backup URL set to $DatabaseSharedPath." -Level Verbose
                } else {
                    if ($SharedPath.EndsWith("\")) {
                        $DatabaseSharedPath = "$SharedPath$($db.Name)"
                    } else {
                        $DatabaseSharedPath = "$SharedPath\$($db.Name)"
                    }
                    Write-Message -Message "Backup network path set to $DatabaseSharedPath." -Level Verbose
                }


                # Checking if the database network path exists (skip for Azure)
                if ($setupResult -ne 'Failed' -and -not $UseAzure) {
                    Write-Message -Message "Testing database backup network path $DatabaseSharedPath" -Level Verbose
                    if ((Test-DbaPath -Path $DatabaseSharedPath -SqlInstance $SourceSqlInstance -SqlCredential $SourceSqlCredential) -ne $true) {
                        # To to create the backup directory for the database
                        try {
                            Write-Message -Message "Database backup network path $DatabaseSharedPath not found. Trying to create it.." -Level Verbose

                            Invoke-Command2 -Credential $SourceCredential -ScriptBlock {
                                Write-Message -Message "Creating backup folder $DatabaseSharedPath" -Level Verbose
                                $null = New-Item -Path $DatabaseSharedPath -ItemType Directory -Force:$Force
                            }
                        } catch {
                            $setupResult = "Failed"
                            $comment = "Something went wrong creating the backup directory"

                            Stop-Function -Message "Something went wrong creating the backup directory" -ErrorRecord $_ -Target $SourceSqlInstance -Continue
                        }
                    }
                }

                # Check if the backup job name is set
                if ($BackupJob) {
                    $DatabaseBackupJob = "$($BackupJob)$($db.Name)"
                } else {
                    $DatabaseBackupJob = "LSBackup_$($db.Name)"
                }
                Write-Message -Message "Backup job name set to $DatabaseBackupJob" -Level Verbose

                # Check if the backup job schedule name is set
                if ($BackupSchedule) {
                    $DatabaseBackupSchedule = "$($BackupSchedule)$($db.Name)"
                } else {
                    $DatabaseBackupSchedule = "LSBackupSchedule_$($db.Name)"
                }
                Write-Message -Message "Backup job schedule name set to $DatabaseBackupSchedule" -Level Verbose

                # Check if secondary database is present on secondary instance
                if (-not $Force -and -not $NoInitialization -and ($DestinationServer.Databases[$SecondaryDatabase].Status -ne 'Restoring') -and ($DestinationServer.Databases.Name -contains $SecondaryDatabase)) {
                    $setupResult = "Failed"
                    $comment = "Secondary database already exists on instance"

                    Stop-Function -Message "Secondary database already exists on instance $destInstance." -Target $destInstance -Continue
                }

                # Check if the secondary database needs to be initialized
                if ($setupResult -ne 'Failed') {
                    if (-not $NoInitialization) {
                        # Check if the secondary database exists on the secondary instance
                        if ($DestinationServer.Databases.Name -notcontains $SecondaryDatabase) {
                            # Check if force is being used and no option to generate the full backup is set
                            if ($Force -and -not ($GenerateFullBackup -or $UseExistingFullBackup)) {
                                # Set the option to generate a full backup
                                Write-Message -Message "Set option to initialize secondary database with full backup" -Level Verbose
                                $GenerateFullBackup = $true
                            } elseif (-not $Force -and -not $GenerateFullBackup -and -not $UseExistingFullBackup -and -not $UseBackupFolder) {
                                # Set up the confirm part
                                $message = "The database $SecondaryDatabase does not exist on instance $destInstance. `nDo you want to initialize it by generating a full backup?"
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
                                        $setupResult = "Failed"
                                        $comment = "The database is not initialized on the secondary instance"

                                        Stop-Function -Message "The database is not initialized on the secondary instance. `nPlease initialize the database on the secondary instance, use -GenerateFullbackup or use -Force." -Target $destInstance
                                        return
                                    }
                                } # switch
                            }
                        }
                    }
                }


                # Check the parameters for initialization of the secondary database
                if (-not $NoInitialization -and ($GenerateFullBackup -or $UseExistingFullBackup -or $UseBackupFolder)) {
                    # Check if the restore data and log folder are set
                    if ($setupResult -ne 'Failed') {
                        if ($RestoreDataFolder) {
                            $DatabaseRestoreDataFolder = $RestoreDataFolder
                        } else {
                            Write-Message -Message "Restore data folder is not set. Using server default." -Level Verbose
                            $DatabaseRestoreDataFolder = $DestinationServer.DefaultFile
                        }
                        Write-Message -Message "Restore data folder is set to $DatabaseRestoreDataFolder" -Level Verbose

                        if ($RestoreLogFolder) {
                            $DatabaseRestoreLogFolder = $RestoreLogFolder
                        } else {
                            Write-Message -Message "Restore log folder is not set. Using server default." -Level Verbose
                            $DatabaseRestoreLogFolder = $DestinationServer.DefaultLog
                        }
                        Write-Message -Message "Restore log folder is set to $DatabaseRestoreLogFolder" -Level Verbose

                        # Check if the restore data folder exists (skip for Azure SQL as it manages storage)
                        if (-not $DestinationServer.IsAzure) {
                            Write-Message -Message "Testing database restore data path $DatabaseRestoreDataFolder" -Level Verbose
                            if ((Test-DbaPath  -Path $DatabaseRestoreDataFolder -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential) -ne $true) {
                                if ($PSCmdlet.ShouldProcess($DestinationServerName, "Creating database restore data folder $DatabaseRestoreDataFolder on $DestinationServerName")) {
                                    # Try creating the data folder
                                    try {
                                        Invoke-Command2 -Credential $DestinationCredential -ScriptBlock {
                                            Write-Message -Message "Creating data folder $DatabaseRestoreDataFolder" -Level Verbose
                                            $null = New-Item -Path $DatabaseRestoreDataFolder -ItemType Directory -Force:$Force
                                        }
                                    } catch {
                                        $setupResult = "Failed"
                                        $comment = "Something went wrong creating the restore data directory"
                                        Stop-Function -Message "Something went wrong creating the restore data directory" -ErrorRecord $_ -Target $SourceSqlInstance -Continue
                                    }
                                }
                            }
                        }

                        # Check if the restore log folder exists (skip for Azure SQL as it manages storage)
                        if (-not $DestinationServer.IsAzure) {
                            Write-Message -Message "Testing database restore log path $DatabaseRestoreLogFolder" -Level Verbose
                            if ((Test-DbaPath  -Path $DatabaseRestoreLogFolder -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential) -ne $true) {
                                if ($PSCmdlet.ShouldProcess($DestinationServerName, "Creating database restore log folder $DatabaseRestoreLogFolder on $DestinationServerName")) {
                                    # Try creating the log folder
                                    try {
                                        Write-Message -Message "Restore log folder $DatabaseRestoreLogFolder not found. Trying to create it.." -Level Verbose

                                        Invoke-Command2 -Credential $DestinationCredential -ScriptBlock {
                                            Write-Message -Message "Restore log folder $DatabaseRestoreLogFolder not found. Trying to create it.." -Level Verbose
                                            $null = New-Item -Path $DatabaseRestoreLogFolder -ItemType Directory -Force:$Force
                                        }
                                    } catch {
                                        $setupResult = "Failed"
                                        $comment = "Something went wrong creating the restore log directory"
                                        Stop-Function -Message "Something went wrong creating the restore log directory" -ErrorRecord $_ -Target $SourceSqlInstance -Continue
                                    }
                                }
                            }
                        }
                    }

                    # Check if the full backup path can be reached
                    if ($setupResult -ne 'Failed') {
                        if ($FullBackupPath) {
                            # Skip path validation for Azure blob URLs
                            if (-not $UseAzure) {
                                Write-Message -Message "Testing full backup path $FullBackupPath" -Level Verbose
                                if ((Test-DbaPath -Path $FullBackupPath -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential) -ne $true) {
                                    $setupResult = "Failed"
                                    $comment = "The path to the full backup could not be reached"
                                    Stop-Function -Message ("The path to the full backup could not be reached. Check the path and/or the crdential") -Target $destInstance -Continue
                                }
                            }

                            $BackupPath = $FullBackupPath
                        } elseif ($UseBackupFolder.Length -ge 1) {
                            # Skip path validation for Azure blob URLs
                            if (-not $UseAzure) {
                                Write-Message -Message "Testing backup folder $UseBackupFolder" -Level Verbose
                                if ((Test-DbaPath -Path $UseBackupFolder -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential) -ne $true) {
                                    $setupResult = "Failed"
                                    $comment = "The path to the backup folder could not be reached"
                                    Stop-Function -Message ("The path to the backup folder could not be reached. Check the path and/or the crdential") -Target $destInstance -Continue
                                }
                            }

                            $BackupPath = $UseBackupFolder
                        } elseif ($UseExistingFullBackup) {
                            Write-Message -Message "No path to the full backup is set. Trying to retrieve the last full backup for $db from $SourceSqlInstance" -Level Verbose

                            # Get the last full backup
                            $LastBackup = Get-DbaDbBackupHistory -SqlInstance $SourceSqlInstance -Database $($db.Name) -LastFull -SqlCredential $SourceSqlCredential

                            # Check if there was a last backup
                            if ($null -ne $LastBackup) {
                                # Skip path validation for Azure blob URLs
                                if (-not $UseAzure) {
                                    # Test the path to the backup
                                    Write-Message -Message "Testing last backup path $(($LastBackup[-1]).Path[-1])" -Level Verbose
                                    if ((Test-DbaPath -Path ($LastBackup[-1]).Path[-1] -SqlInstance $SourceSqlInstance -SqlCredential $SourceSqlCredential) -ne $true) {
                                        $setupResult = "Failed"
                                        $comment = "The full backup could not be found"
                                        Stop-Function -Message "The full backup could not be found on $($LastBackup.Path). Check path and/or credentials" -Target $destInstance -Continue
                                    }
                                    # Check if the source for the last full backup is remote and the backup is on a shared location
                                    elseif (($LastBackup.Computername -ne $SourceServerName) -and (($LastBackup[-1]).Path[-1].StartsWith('\\') -eq $false)) {
                                        $setupResult = "Failed"
                                        $comment = "The last full backup is not located on shared location"
                                        Stop-Function -Message "The last full backup is not located on shared location. `n$($_.Exception.Message)" -Target $destInstance -Continue
                                    }
                                }

                                if ($setupResult -ne 'Failed') {
                                    #$FullBackupPath = $LastBackup.Path
                                    $BackupPath = $LastBackup.Path
                                    Write-Message -Message "Full backup found for $db. Path $BackupPath" -Level Verbose
                                }
                            } else {
                                Write-Message -Message "No Full backup found for $db." -Level Verbose
                            }
                        }
                    }
                }

                # Set the copy destination folder to include the database name
                if ($UseAzure) {
                    # For Azure, append database name to URL path
                    $DatabaseCopyDestinationFolder = "$CopyDestinationFolder/$($db.Name)"
                    Write-Message -Message "Copy destination URL set to $DatabaseCopyDestinationFolder (Azure - no local copy)." -Level Verbose
                } else {
                    if ($CopyDestinationFolder.EndsWith("\")) {
                        $DatabaseCopyDestinationFolder = "$CopyDestinationFolder$($db.Name)"
                    } else {
                        $DatabaseCopyDestinationFolder = "$CopyDestinationFolder\$($db.Name)"
                    }
                    Write-Message -Message "Copy destination folder set to $DatabaseCopyDestinationFolder." -Level Verbose
                }

                # Check if the copy job name is set
                # For Azure, still need to set a name because sp_add_log_shipping_secondary_primary requires it
                # (the job will be deleted immediately after creation)
                if ($CopyJob) {
                    $DatabaseCopyJob = "$($CopyJob)$($db.Name)"
                } else {
                    $DatabaseCopyJob = "LSCopy_$($SourceServerName)_$($db.Name)"
                }
                if ($UseAzure) {
                    Write-Message -Message "Copy job name set to $DatabaseCopyJob (will be removed - not needed for Azure)" -Level Verbose
                } else {
                    Write-Message -Message "Copy job name set to $DatabaseCopyJob" -Level Verbose
                }

                # Check if the copy job schedule name is set
                if ($CopySchedule) {
                    $DatabaseCopySchedule = "$($CopySchedule)$($db.Name)"
                } else {
                    $DatabaseCopySchedule = "LSCopySchedule_$($SourceServerName)_$($db.Name)"
                    Write-Message -Message "Copy job schedule name set to $DatabaseCopySchedule" -Level Verbose
                }

                # Check if the copy destination folder exists (skip for Azure blob storage and Azure SQL)
                if ($setupResult -ne 'Failed' -and -not $UseAzure -and -not $DestinationServer.IsAzure) {
                    Write-Message -Message "Testing database copy destination path $DatabaseCopyDestinationFolder" -Level Verbose
                    if ((Test-DbaPath -Path $DatabaseCopyDestinationFolder -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential) -ne $true) {
                        if ($PSCmdlet.ShouldProcess($DestinationServerName, "Creating copy destination folder on $DestinationServerName")) {
                            try {
                                Invoke-Command2 -Credential $DestinationCredential -ScriptBlock {
                                    Write-Message -Message "Copy destination folder $DatabaseCopyDestinationFolder not found. Trying to create it.. ." -Level Verbose
                                    $null = New-Item -Path $DatabaseCopyDestinationFolder -ItemType Directory -Force:$Force
                                }
                            } catch {
                                $setupResult = "Failed"
                                $comment = "Something went wrong creating the database copy destination folder"
                                Stop-Function -Message "Something went wrong creating the database copy destination folder. `n$($_.Exception.Message)" -ErrorRecord $_ -Target $DestinationServerName -Continue
                            }
                        }
                    }
                }

                # Check if the restore job name is set
                if ($RestoreJob) {
                    $DatabaseRestoreJob = "$($RestoreJob)$($db.Name)"
                } else {
                    $DatabaseRestoreJob = "LSRestore_$($SourceServerName)_$($db.Name)"
                }
                Write-Message -Message "Restore job name set to $DatabaseRestoreJob" -Level Verbose

                # Check if the restore job schedule name is set
                if ($RestoreSchedule) {
                    $DatabaseRestoreSchedule = "$($RestoreSchedule)$($db.Name)"
                } else {
                    $DatabaseRestoreSchedule = "LSRestoreSchedule_$($SourceServerName)_$($db.Name)"
                }
                Write-Message -Message "Restore job schedule name set to $DatabaseRestoreSchedule" -Level Verbose

                # If the database needs to be backed up first
                if ($setupResult -ne 'Failed') {
                    if ($GenerateFullBackup) {
                        if ($PSCmdlet.ShouldProcess($SourceSqlInstance, "Backing up database $db")) {

                            Write-Message -Message "Generating full backup." -Level Verbose
                            Write-Message -Message "Backing up database $db to $DatabaseSharedPath" -Level Verbose

                            try {
                                $Timestamp = Get-Date -format "yyyyMMddHHmmss"

                                if ($UseAzure) {
                                    # Backup to Azure blob storage - use container base URL only
                                    # Azure blob names can contain slashes for virtual folders
                                    $AzureBlobName = "$($db.Name)_FullBackup_PreLogShipping_$Timestamp.bak"
                                    $splatBackup = @{
                                        SqlInstance    = $SourceSqlInstance
                                        SqlCredential  = $SourceSqlCredential
                                        Database       = $($db.Name)
                                        AzureBaseUrl   = $SharedPath
                                        BackupFileName = $AzureBlobName
                                        Type           = "Full"
                                    }

                                    # Only specify credential for storage account key authentication
                                    # For SAS tokens, SQL Server finds credential automatically by URL
                                    if ($AzureCredential) {
                                        $splatBackup.AzureCredential = $AzureCredential
                                    }

                                    $LastBackup = Backup-DbaDatabase @splatBackup
                                } else {
                                    # Backup to file share
                                    $splatBackup = @{
                                        SqlInstance     = $SourceSqlInstance
                                        SqlCredential   = $SourceSqlCredential
                                        BackupDirectory = $DatabaseSharedPath
                                        BackupFileName  = "FullBackup_$($db.Name)_PreLogShipping_$Timestamp.bak"
                                        Database        = $($db.Name)
                                        Type            = "Full"
                                    }

                                    $LastBackup = Backup-DbaDatabase @splatBackup
                                }

                                Write-Message -Message "Backup completed." -Level Verbose

                                # Get the last full backup path
                                #$FullBackupPath = $LastBackup.BackupPath
                                $BackupPath = $LastBackup.BackupPath

                                Write-Message -Message "Backup is located at $BackupPath" -Level Verbose
                            } catch {
                                $setupResult = "Failed"
                                $comment = "Something went wrong generating the full backup"
                                Stop-Function -Message "Something went wrong generating the full backup" -ErrorRecord $_ -Target $DestinationServerName -Continue
                            }
                        }
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
                        $setupResult = "Failed"
                        $comment = "The PrimaryMonitorServerLogin cannot be empty"
                        Stop-Function -Message "The PrimaryMonitorServerLogin cannot be empty when using SQL Server authentication." -Target $SourceSqlInstance -Continue
                    }

                    if ($PrimaryMonitorServerPassword) {
                        $setupResult = "Failed"
                        $comment = "The PrimaryMonitorServerPassword cannot be empty"
                        Stop-Function -Message "The PrimaryMonitorServerPassword cannot be empty when using SQL Server authentication." -Target $ -Continue
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
                        $setupResult = "Failed"
                        $comment = "The SecondaryMonitorServerLogin cannot be empty"
                        Stop-Function -Message "The SecondaryMonitorServerLogin cannot be empty when using SQL Server authentication." -Target $SourceSqlInstance -Continue
                    }

                    if ($SecondaryMonitorServerPassword) {
                        $setupResult = "Failed"
                        $comment = "The SecondaryMonitorServerPassword cannot be empty"
                        Stop-Function -Message "The SecondaryMonitorServerPassword cannot be empty when using SQL Server authentication." -Target $SourceSqlInstance -Continue
                    }
                }

                # Now that all the checks have been done we can start with the fun stuff !

                # Restore the full backup
                if ($setupResult -ne 'Failed') {
                    if ($PSCmdlet.ShouldProcess($destInstance, "Restoring database $db to $SecondaryDatabase on $destInstance")) {
                        if ($GenerateFullBackup -or $UseExistingFullBackup -or $UseBackupFolder) {
                            try {
                                Write-Message -Message "Start database restore" -Level Verbose
                                if ($NoRecovery -or (-not $Standby)) {
                                    if ($Force) {
                                        $splatRestore = @{
                                            SqlInstance               = $destInstance
                                            SqlCredential             = $DestinationSqlCredential
                                            Path                      = $BackupPath
                                            DestinationFilePrefix     = $SecondaryDatabasePrefix
                                            DestinationFileSuffix     = $SecondaryDatabaseSuffix
                                            DestinationDataDirectory  = $DatabaseRestoreDataFolder
                                            DestinationLogDirectory   = $DatabaseRestoreLogFolder
                                            DatabaseName              = $SecondaryDatabase
                                            DirectoryRecurse          = $true
                                            NoRecovery                = $true
                                            WithReplace               = $true
                                        }
                                        $null = Restore-DbaDatabase @splatRestore
                                    } else {
                                        $splatRestore = @{
                                            SqlInstance               = $destInstance
                                            SqlCredential             = $DestinationSqlCredential
                                            Path                      = $BackupPath
                                            DestinationFilePrefix     = $SecondaryDatabasePrefix
                                            DestinationFileSuffix     = $SecondaryDatabaseSuffix
                                            DestinationDataDirectory  = $DatabaseRestoreDataFolder
                                            DestinationLogDirectory   = $DatabaseRestoreLogFolder
                                            DatabaseName              = $SecondaryDatabase
                                            DirectoryRecurse          = $true
                                            NoRecovery                = $true
                                        }
                                        $null = Restore-DbaDatabase @splatRestore
                                    }
                                }

                                # If the database needs to be in standby
                                if ($Standby) {
                                    # Setup the path to the standby file
                                    $StandbyDirectory = "$DatabaseCopyDestinationFolder"

                                    # Check if credentials need to be used
                                    if ($DestinationSqlCredential) {
                                        $splatRestoreStandby = @{
                                            SqlInstance               = $destInstance
                                            SqlCredential             = $DestinationSqlCredential
                                            Path                      = $BackupPath
                                            DestinationFilePrefix     = $SecondaryDatabasePrefix
                                            DestinationFileSuffix     = $SecondaryDatabaseSuffix
                                            DestinationDataDirectory  = $DatabaseRestoreDataFolder
                                            DestinationLogDirectory   = $DatabaseRestoreLogFolder
                                            DatabaseName              = $SecondaryDatabase
                                            DirectoryRecurse          = $true
                                            StandbyDirectory          = $StandbyDirectory
                                        }
                                        $null = Restore-DbaDatabase @splatRestoreStandby
                                    } else {
                                        $splatRestoreStandby = @{
                                            SqlInstance               = $destInstance
                                            Path                      = $BackupPath
                                            DestinationFilePrefix     = $SecondaryDatabasePrefix
                                            DestinationFileSuffix     = $SecondaryDatabaseSuffix
                                            DestinationDataDirectory  = $DatabaseRestoreDataFolder
                                            DestinationLogDirectory   = $DatabaseRestoreLogFolder
                                            DatabaseName              = $SecondaryDatabase
                                            DirectoryRecurse          = $true
                                            StandbyDirectory          = $StandbyDirectory
                                        }
                                        $null = Restore-DbaDatabase @splatRestoreStandby
                                    }
                                }
                            } catch {
                                $setupResult = "Failed"
                                $comment = "Something went wrong restoring the secondary database"
                                Stop-Function -Message "Something went wrong restoring the secondary database" -ErrorRecord $_ -Target $SourceSqlInstance -Continue
                            }

                            Write-Message -Message "Restore completed." -Level Verbose
                        }
                    }
                }

                #region Set up log shipping on the primary instance
                # Set up log shipping on the primary instance
                if ($setupResult -ne 'Failed') {
                    if ($PSCmdlet.ShouldProcess($SourceSqlInstance, "Configuring logshipping for primary database $db on $SourceSqlInstance")) {
                        try {

                            Write-Message -Message "Configuring logshipping for primary database" -Level Verbose

                            $splatPrimary = @{
                                SqlInstance                 = $SourceSqlInstance
                                SqlCredential               = $SourceSqlCredential
                                Database                    = $($db.Name)
                                BackupDirectory             = $DatabaseLocalPath
                                BackupJob                   = $DatabaseBackupJob
                                BackupRetention             = $BackupRetention
                                BackupShare                 = $DatabaseSharedPath
                                BackupThreshold             = $BackupThreshold
                                CompressBackup              = $BackupCompression
                                HistoryRetention            = $HistoryRetention
                                MonitorServer               = $PrimaryMonitorServer
                                MonitorServerSecurityMode   = $PrimaryMonitorServerSecurityMode
                                MonitorCredential           = $PrimaryMonitorCredential
                                ThresholdAlertEnabled       = $PrimaryThresholdAlertEnabled
                                Force                       = $Force
                            }

                            # Add Azure credential if provided (for storage account key authentication)
                            if ($AzureCredential) {
                                $splatPrimary.AzureCredential = $AzureCredential
                            }
                            New-DbaLogShippingPrimaryDatabase @splatPrimary

                            # Check if the backup job needs to be enabled or disabled
                            if ($BackupScheduleDisabled) {
                                $null = Set-DbaAgentJob -SqlInstance $SourceSqlInstance -SqlCredential $SourceSqlCredential -Job $DatabaseBackupJob -Disabled
                                Write-Message -Message "Disabling backup job $DatabaseBackupJob" -Level Verbose
                            } else {
                                $null = Set-DbaAgentJob -SqlInstance $SourceSqlInstance -SqlCredential $SourceSqlCredential -Job $DatabaseBackupJob -Enabled
                                Write-Message -Message "Enabling backup job $DatabaseBackupJob" -Level Verbose
                            }

                            Write-Message -Message "Create backup job schedule $DatabaseBackupSchedule" -Level Verbose

                            #Variable $BackupJobSchedule marked as unused by PSScriptAnalyzer replaced with $null for catching output
                            $splatBackupSchedule = @{
                                SqlInstance                  = $SourceSqlInstance
                                SqlCredential                = $SourceSqlCredential
                                Job                          = $DatabaseBackupJob
                                Schedule                     = $DatabaseBackupSchedule
                                FrequencyType                = $BackupScheduleFrequencyType
                                FrequencyInterval            = $BackupScheduleFrequencyInterval
                                FrequencySubdayType          = $BackupScheduleFrequencySubdayType
                                FrequencySubdayInterval      = $BackupScheduleFrequencySubdayInterval
                                FrequencyRelativeInterval    = $BackupScheduleFrequencyRelativeInterval
                                FrequencyRecurrenceFactor    = $BackupScheduleFrequencyRecurrenceFactor
                                StartDate                    = $BackupScheduleStartDate
                                EndDate                      = $BackupScheduleEndDate
                                StartTime                    = $BackupScheduleStartTime
                                EndTime                      = $BackupScheduleEndTime
                                Force                        = $Force
                            }
                            $null = New-DbaAgentSchedule @splatBackupSchedule

                            Write-Message -Message "Configuring logshipping from primary to secondary database." -Level Verbose

                            $splatPrimarySecondary = @{
                                SqlInstance             = $SourceSqlInstance
                                SqlCredential           = $SourceSqlCredential
                                PrimaryDatabase         = $($db.Name)
                                SecondaryDatabase       = $SecondaryDatabase
                                SecondaryServer         = $destInstance
                                SecondarySqlCredential  = $DestinationSqlCredential
                            }
                            New-DbaLogShippingPrimarySecondary @splatPrimarySecondary
                        } catch {
                            $setupResult = "Failed"
                            $comment = "Something went wrong setting up log shipping for primary instance"
                            Stop-Function -Message "Something went wrong setting up log shipping for primary instance" -ErrorRecord $_ -Target $SourceSqlInstance -Continue
                        }
                    }
                }
                #endregion Set up log shipping on the primary instance

                #region Set up log shipping on the secondary instance
                # Set up log shipping on the secondary instance
                if ($setupResult -ne 'Failed') {
                    if ($PSCmdlet.ShouldProcess($destInstance, "Configuring logshipping for secondary database $SecondaryDatabase on $destInstance")) {
                        try {

                            Write-Message -Message "Configuring logshipping from secondary database $SecondaryDatabase to primary database $db." -Level Verbose

                            $splatSecondaryPrimary = @{
                                SqlInstance                 = $destInstance
                                SqlCredential               = $DestinationSqlCredential
                                BackupSourceDirectory       = $DatabaseSharedPath
                                BackupDestinationDirectory  = $DatabaseCopyDestinationFolder
                                CopyJob                     = $DatabaseCopyJob
                                FileRetentionPeriod         = $BackupRetention
                                MonitorServer               = $SecondaryMonitorServer
                                MonitorServerSecurityMode   = $SecondaryMonitorServerSecurityMode
                                MonitorCredential           = $SecondaryMonitorCredential
                                PrimaryServer               = $SourceSqlInstance
                                PrimarySqlCredential        = $SourceSqlCredential
                                PrimaryDatabase             = $($db.Name)
                                RestoreJob                  = $DatabaseRestoreJob
                                Force                       = $Force
                            }

                            # Add Azure credential if provided (for storage account key authentication)
                            if ($AzureCredential) {
                                $splatSecondaryPrimary.AzureCredential = $AzureCredential
                            }
                            New-DbaLogShippingSecondaryPrimary @splatSecondaryPrimary

                            # For Azure: Remove the copy job created by sp_add_log_shipping_secondary_primary
                            # Azure backups go directly to blob storage, so no copy is needed
                            if ($UseAzure) {
                                Write-Message -Message "Removing unnecessary copy job for Azure: $DatabaseCopyJob" -Level Verbose
                                $null = Remove-DbaAgentJob -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential -Job $DatabaseCopyJob -Confirm:$false
                            }

                            # Skip copy job schedule for Azure (backups are already in the cloud)
                            if (-not $UseAzure) {
                                Write-Message -Message "Create copy job schedule $DatabaseCopySchedule" -Level Verbose
                                #Variable $CopyJobSchedule marked as unused by PSScriptAnalyzer replaced with $null for catching output
                                $splatCopySchedule = @{
                                    SqlInstance                  = $destInstance
                                    SqlCredential                = $DestinationSqlCredential
                                    Job                          = $DatabaseCopyJob
                                    Schedule                     = $DatabaseCopySchedule
                                    FrequencyType                = $CopyScheduleFrequencyType
                                    FrequencyInterval            = $CopyScheduleFrequencyInterval
                                    FrequencySubdayType          = $CopyScheduleFrequencySubdayType
                                    FrequencySubdayInterval      = $CopyScheduleFrequencySubdayInterval
                                    FrequencyRelativeInterval    = $CopyScheduleFrequencyRelativeInterval
                                    FrequencyRecurrenceFactor    = $CopyScheduleFrequencyRecurrenceFactor
                                    StartDate                    = $CopyScheduleStartDate
                                    EndDate                      = $CopyScheduleEndDate
                                    StartTime                    = $CopyScheduleStartTime
                                    EndTime                      = $CopyScheduleEndTime
                                    Force                        = $Force
                                }
                                $null = New-DbaAgentSchedule @splatCopySchedule
                            }

                            Write-Message -Message "Create restore job schedule $DatabaseRestoreSchedule" -Level Verbose

                            #Variable $RestoreJobSchedule marked as unused by PSScriptAnalyzer replaced with $null for catching output
                            $splatRestoreSchedule = @{
                                SqlInstance                  = $destInstance
                                SqlCredential                = $DestinationSqlCredential
                                Job                          = $DatabaseRestoreJob
                                Schedule                     = $DatabaseRestoreSchedule
                                FrequencyType                = $RestoreScheduleFrequencyType
                                FrequencyInterval            = $RestoreScheduleFrequencyInterval
                                FrequencySubdayType          = $RestoreScheduleFrequencySubdayType
                                FrequencySubdayInterval      = $RestoreScheduleFrequencySubdayInterval
                                FrequencyRelativeInterval    = $RestoreScheduleFrequencyRelativeInterval
                                FrequencyRecurrenceFactor    = $RestoreScheduleFrequencyRecurrenceFactor
                                StartDate                    = $RestoreScheduleStartDate
                                EndDate                      = $RestoreScheduleEndDate
                                StartTime                    = $RestoreScheduleStartTime
                                EndTime                      = $RestoreScheduleEndTime
                                Force                        = $Force
                            }
                            $null = New-DbaAgentSchedule @splatRestoreSchedule

                            Write-Message -Message "Configuring logshipping for secondary database." -Level Verbose

                            $splatSecondaryDatabase = @{
                                SqlInstance                 = $destInstance
                                SqlCredential               = $DestinationSqlCredential
                                SecondaryDatabase           = $SecondaryDatabase
                                PrimaryServer               = $SourceSqlInstance
                                PrimarySqlCredential        = $SourceSqlCredential
                                PrimaryDatabase             = $($db.Name)
                                RestoreDelay                = $RestoreDelay
                                RestoreMode                 = $DatabaseStatus
                                DisconnectUsers             = $DisconnectUsers
                                RestoreThreshold            = $RestoreThreshold
                                ThresholdAlertEnabled       = $SecondaryThresholdAlertEnabled
                                HistoryRetention            = $HistoryRetention
                                MonitorServer               = $SecondaryMonitorServer
                                MonitorServerSecurityMode   = $SecondaryMonitorServerSecurityMode
                                MonitorCredential           = $SecondaryMonitorCredential
                            }
                            New-DbaLogShippingSecondaryDatabase @splatSecondaryDatabase

                            # Skip copy job enable/disable for Azure (no copy job exists)
                            if (-not $UseAzure) {
                                # Check if the copy job needs to be enabled or disabled
                                if ($CopyScheduleDisabled) {
                                    $null = Set-DbaAgentJob -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential -Job $DatabaseCopyJob -Disabled
                                } else {
                                    $null = Set-DbaAgentJob -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential -Job $DatabaseCopyJob -Enabled
                                }
                            }

                            # Check if the restore job needs to be enabled or disabled
                            if ($RestoreScheduleDisabled) {
                                $null = Set-DbaAgentJob -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential -Job $DatabaseRestoreJob -Disabled
                            } else {
                                $null = Set-DbaAgentJob -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential -Job $DatabaseRestoreJob -Enabled
                            }

                        } catch {
                            $setupResult = "Failed"
                            $comment = "Something went wrong setting up log shipping for secondary instance"
                            Stop-Function -Message "Something went wrong setting up log shipping for secondary instance.`n$($_.Exception.Message)" -ErrorRecord $_ -Target $destInstance -Continue
                        }
                    }
                }
                #endregion Set up log shipping on the secondary instance

                Write-Message -Message "Completed configuring log shipping for database $db" -Level Verbose

                [PSCustomObject]@{
                    PrimaryInstance   = $SourceServer.DomainInstanceName
                    SecondaryInstance = $DestinationServer.DomainInstanceName
                    PrimaryDatabase   = $($db.Name)
                    SecondaryDatabase = $SecondaryDatabase
                    Result            = $setupResult
                    Comment           = $comment
                }

            } # for each database
        } # end for each destination server
    } # end process
    end {
        Write-Message -Message "Finished setting up log shipping." -Level Verbose
    }
}