function New-DbaLogShippingPrimaryDatabase {
    <#
.SYNOPSIS 
New-DbaLogShippingPrimaryDatabase add the primary database to log shipping

.DESCRIPTION
New-DbaLogShippingPrimaryDatabase will add the primary database to log shipping.
This is executed on the primary server.

.PARAMETER SqlInstance
SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER Database
Database to set up log shipping for.

.PARAMETER BackupDirectory
Is the path to the backup folder on the primary server.

.PARAMETER BackupJob
Is the name of the SQL Server Agent job on the primary server that copies the backup into the backup folder.

.PARAMETER BackupJobID
The SQL Server Agent job ID associated with the backup job on the primary server.

.PARAMETER BackupRetention
Is the length of time, in minutes, to retain the log backup file in the backup directory on the primary server. 

.PARAMETER BackupShare
Is the network path to the backup directory on the primary server. 

.PARAMETER BackupThreshold
Is the length of time, in minutes, after the last backup before a threshold_alert error is raised.
The default is 60.

.PARAMETER HistoryRetention
Is the length of time in minutes in which the history will be retained.
The default is 14420.

.PARAMETER MonitorServer
Is the name of the monitor server.
The default is the name of the primary server.

.PARAMETER MonitorCredential
Allows you to login to enter a secure credential. 
This is only needed in combination with MonitorServerSecurityMode having either a 0 or 'sqlserver' value.
To use: $scred = Get-Credential, then pass $scred object to the -MonitorCredential parameter. 

.PARAMETER MonitorServerSecurityMode
The security mode used to connect to the monitor server. Allowed values are 0, "sqlserver", 1, "windows"
The default is 1 or Windows.

.PARAMETER ThresholdAlertEnabled
Specifies whether an alert will be raised when backup threshold is exceeded.
The default is 0.

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
Tags: Log shippin, primary database
	
Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/New-DbaLogShippingPrimaryDatabase

.EXAMPLE   
New-DbaLogShippingPrimaryDatabase -SqlInstance sql1 -Database DB1 -BackupDirectory D:\data\logshipping -BackupJob LSBackup_DB1 -BackupRetention 4320 -BackupShare "\\sql1\logshipping" -BackupThreshold 60 -CompressBackup -HistoryRetention 14420 -MonitorServer sql1 -ThresholdAlertEnabled

#>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]

    param (
        [parameter(Mandatory = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [object]$SqlInstance,

        [System.Management.Automation.PSCredential]
        $SqlCredential = [System.Management.Automation.PSCredential]::Empty,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [object]$Database,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$BackupDirectory,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$BackupJob,

        [Parameter(Mandatory = $true)]
        [int]$BackupRetention,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$BackupShare,

        [int]$BackupThreshold = 60,

        [int]$HistoryRetention = 14420,

        [int]$BackupCompression = 0,

        [switch]$CompressBackup,

        [string]$MonitorServer,

        [ValidateSet(0, "sqlserver", 1, "windows")]
        [object]$MonitorServerSecurityMode = 1,

        [System.Management.Automation.PSCredential]
        $MonitorCredential,

        [switch]$ThresholdAlertEnabled,

        [switch]$Silent,

        [switch]$Force
    )

    # Try connecting to the instance
    Write-Message -Message "Attempting to connect to $SqlInstance" -Level Verbose
    try {
        $Server = Connect-SqlServer -SqlServer $SqlInstance -SqlCredential $SqlCredential
    }
    catch {
        Stop-Function -Message "Could not connect to Sql Server instance" -Target $SqlInstance -Continue
    }

    # Check if the backup UNC path is correct and reachable
    if ([bool]([uri]$BackupShare).IsUnc -and $BackupShare -notmatch '^\\(?:\\[^<>:`"/\\|?*]+)+$') {
        Stop-Function -Message "The backup share path $BackupShare should be formatted in the form \\server\share." -InnerErrorRecord $_ -Target $SqlInstance
        return
    }
    else {
        if (-not ((Test-Path $BackupShare -PathType Container -IsValid) -and ((Get-Item $BackupShare).PSProvider.Name -eq 'FileSystem'))) {
            Stop-Function -Message "The backup share path $BackupShare is not valid or can't be reached." -InnerErrorRecord $_ -Target $SqlInstance
            return
        }
    }

    # Check the backup compression
    if ($CompressBackup) {
        $BackupCompression = 1
        Write-Message -Message "Setting backup compression to 1." -Level Verbose
    }
    else {
        $BackupCompression = 0
        Write-Message -Message "Setting backup compression to 0." -Level Verbose
    }

    # Check of the MonitorServerSecurityMode value is of type string and set the integer value
    if ($MonitorServerSecurityMode -notin 0, 1) {
        $MonitorServerSecurityMode = switch ($MonitorServerSecurityMode) {"WINDOWS" { 1 } "SQLSERVER" { 0 } }
        Write-Message -Message "Setting monitor server security mode to $MonitorServerSecurityMode." -Level Verbose
    }

    # Check the MonitorServer
    if (-not $MonitorServer) {
        if ($Force) {
            $MonitorServer = $SqlInstance
            Write-Message -Message "Setting monitor server to $MonitorServer." -Level Verbose
        }
        else {
            Stop-Function -Message "The monitor server needs to be set. Use -Force if system name must be used." -InnerErrorRecord $_ -Target $SqlInstance 
            return
        }
    }

    # Check the MonitorServerSecurityMode if it's SQL Server authentication
    if ($MonitorServerSecurityMode -eq 0 -and -not $MonitorCredential) {
        Stop-Function -Message "The MonitorServerCredential cannot be empty when using SQL Server authentication." -InnerErrorRecord $_ -Target $SqlInstance 
        return
    }
    elseif ($MonitorServerSecurityMode -eq 0 -and $MonitorCredential) {
        # Get the username and password from the credential
        $MonitorLogin = $MonitorCredential.UserName
        $MonitorPassword = $MonitorCredential.GetNetworkCredential().Password

        # Check if the user is in the database
        if ($Server.Databases['master'].Users.Name -notcontains $MonitorLogin) {
            Stop-Function -Message "User $MonitorLogin for monitor login must be in the master database." -InnerErrorRecord $_ -Target $SqlInstance 
            return
        }
    }

    # Check if the database is present on the source sql server
    if ($Server.Databases.Name -notcontains $Database) {
        Stop-Function -Message "Database $Database is not available on instance $SqlInstance" -InnerErrorRecord $_ -Target $SqlInstance 
        return
    }

    # Check the if Threshold alert needs to be enabled
    if ($ThresholdAlertEnabled) {
        [int]$ThresholdAlertEnabled = 1
        Write-Message -Message "Setting Threshold alert to $ThresholdAlertEnabled." -Level Verbose
    }
    else {
        [int]$ThresholdAlertEnabled = 0
        Write-Message -Message "Setting Threshold alert to $ThresholdAlertEnabled." -Level Verbose
    }

    # Set the log shipping primary
    $Query = "
        DECLARE @LS_BackupJobId AS uniqueidentifier;
        DECLARE @LS_PrimaryId AS uniqueidentifier;
        EXEC master.dbo.sp_add_log_shipping_primary_database 
            @database = N'$Database'
            ,@backup_directory = N'$BackupDirectory'
            ,@backup_share = N'$BackupShare'
            ,@backup_job_name = N'$BackupJob'
            ,@backup_retention_period = $BackupRetention
            ,@backup_compression = $BackupCompression
            ,@monitor_server = N'$MonitorServer '
            ,@monitor_server_security_mode = $MonitorServerSecurityMode
            ,@backup_threshold = $BackupThreshold
            ,@threshold_alert_enabled = $ThresholdAlertEnabled
            ,@history_retention_period = $HistoryRetention
            ,@backup_job_id = @LS_BackupJobId OUTPUT
            ,@primary_id = @LS_PrimaryId OUTPUT "

    # Check the MonitorServerSecurityMode if it's SQL Server authentication
    if ($MonitorServerSecurityMode -eq 0) {
        $Query += ",@monitor_server_login = N'$MonitorLogin'
            ,@monitor_server_password = N'$MonitorPassword' "
    }

    $Query += ",@overwrite = 1;"

    # Execute the query to add the log shipping primary
    if ($PSCmdlet.ShouldProcess($SqlServer, ("Configuring logshipping for primary database $Database on $SqlInstance"))) {
        try {
            Write-Message -Message "Configuring logshipping for primary database $Database." -Level Output
            Invoke-SqlCmd2 -ServerInstance $SqlInstance -Credential $SqlCredential -Database 'master' -Query $Query
        }
        catch {
            Stop-Function -Message "Error executing the query.`n$($_.Exception.Message)`n$($Query)" -InnerErrorRecord $_ -Target $SqlInstance
            return
        }
    }

    Write-Message -Message "Finished adding the primary database $Database to log shipping." -Level Output
    
}