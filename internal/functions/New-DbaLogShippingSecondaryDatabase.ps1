function New-DbaLogShippingSecondaryDatabase {
    <#
        .SYNOPSIS
            New-DbaLogShippingSecondaryDatabase sets up a secondary databases for log shipping.

        .DESCRIPTION
            New-DbaLogShippingSecondaryDatabase sets up a secondary databases for log shipping.
            This is executed on the secondary server.

        .PARAMETER SqlInstance
            SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER BufferCount
            The total number of buffers used by the backup or restore operation.
            The default is -1.

        .PARAMETER BlockSize
            The size, in bytes, that is used as the block size for the backup device.
            The default is -1.

        .PARAMETER DisconnectUsers
            If set to 1, users are disconnected from the secondary database when a restore operation is performed.
            Te default is 0.

        .PARAMETER HistoryRetention
            Is the length of time in minutes in which the history is retained.
            The default is 14420.

        .PARAMETER MaxTransferSize
            The size, in bytes, of the maximum input or output request which is issued by SQL Server to the backup device.

        .PARAMETER PrimaryServer
            The name of the primary instance of the Microsoft SQL Server Database Engine in the log shipping configuration.

        .PARAMETER PrimaryDatabase
            Is the name of the database on the primary server.

        .PARAMETER RestoreAll
            If set to 1, the secondary server restores all available transaction log backups when the restore job runs.
            The default is 1.

        .PARAMETER RestoreDelay
            The amount of time, in minutes, that the secondary server waits before restoring a given backup file.
            The default is 0.

        .PARAMETER RestoreMode
            The restore mode for the secondary database. The default is 0.
            0 = Restore log with NORECOVERY.
            1 = Restore log with STANDBY.

        .PARAMETER RestoreThreshold
            The number of minutes allowed to elapse between restore operations before an alert is generated.

        .PARAMETER SecondaryDatabase
            Is the name of the secondary database.

        .PARAMETER ThresholdAlert
            Is the alert to be raised when the backup threshold is exceeded.
            The default is 14420.

        .PARAMETER ThresholdAlertEnabled
            Specifies whether an alert is raised when backup_threshold is exceeded.

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

        .PARAMETER WhatIf
            Shows what would happen if the command were to run. No actions are actually performed.

        .PARAMETER Confirm
            Prompts you for confirmation before executing any changing operations within the command.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .PARAMETER Force
            The force parameter will ignore some errors in the parameters and assume defaults.
            It will also remove the any present schedules with the same name for the specific job.

        .NOTES
            Author: Sander Stad (@sqlstad, sqlstad.nl)
            Website: https://dbatools.io
            Copyright: (c) 2018 by dbatools, licensed under MIT
            License: MIT https://opensource.org/licenses/MIT

        .EXAMPLE
            New-DbaLogShippingSecondaryDatabase -SqlInstance sql2 -SecondaryDatabase DB1_DR -PrimaryServer sql1 -PrimaryDatabase DB1 -RestoreDelay 0 -RestoreMode standby -DisconnectUsers -RestoreThreshold 45 -ThresholdAlertEnabled -HistoryRetention 14420
    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]

    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [int]$BufferCount = -1,
        [int]$BlockSize = -1,
        [switch]$DisconnectUsers,
        [int]$HistoryRetention = 14420,
        [int]$MaxTransferSize,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [DbaInstanceParameter]$PrimaryServer,
        [PSCredential]$PrimarySqlCredential,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]$PrimaryDatabase,
        [int]$RestoreAll = 1,
        [int]$RestoreDelay = 0,
        [ValidateSet(0, 'NoRecovery', 1, 'Standby')]
        [object]$RestoreMode = 0,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [int]$RestoreThreshold,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]$SecondaryDatabase,
        [int]$ThresholdAlert = 14420,
        [switch]$ThresholdAlertEnabled,
        [string]$MonitorServer,
        [ValidateSet(0, "sqlserver", 1, "windows")]
        [object]$MonitorServerSecurityMode = 1,
        [System.Management.Automation.PSCredential]$MonitorCredential,
        [switch]$EnableException,
        [switch]$Force
    )

    # Try connecting to the instance
    try {
        $ServerSecondary = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
    } catch {
        Stop-Function -Message "Error occurred while establishing connection to $SqlInstance" -Category ConnectionError -Target $SqlInstance -ErrorRecord $_ -Continue
    }

    # Try connecting to the instance
    try {
        $ServerPrimary = Connect-SqlInstance -SqlInstance $PrimaryServer -SqlCredential $PrimarySqlCredential
    } catch {
        Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -Target $PrimaryServer -ErrorRecord $_ -Continue
    }

    # Check if the database is present on the primary sql server
    if ($ServerPrimary.Databases.Name -notcontains $PrimaryDatabase) {
        Stop-Function -Message "Database $PrimaryDatabase is not available on instance $PrimaryServer" -Target $PrimaryServer -Continue
    }

    # Check if the database is present on the primary sql server
    if ($ServerSecondary.Databases.Name -notcontains $SecondaryDatabase) {
        Stop-Function -Message "Database $SecondaryDatabase is not available on instance $ServerSecondary" -Target $SqlInstance -Continue
    }

    # Check the restore mode
    if ($RestoreMode -notin 0, 1) {
        $RestoreMode = switch ($RestoreMode) { "NoRecovery" { 0 }  "Standby" { 1 } }
        Write-Message -Message "Setting restore mode to $RestoreMode." -Level Verbose
    }

    # Check the if Threshold alert needs to be enabled
    if ($ThresholdAlertEnabled) {
        [int]$ThresholdAlertEnabled = 1
        Write-Message -Message "Setting Threshold alert to $ThresholdAlertEnabled." -Level Verbose
    } else {
        [int]$ThresholdAlertEnabled = 0
        Write-Message -Message "Setting Threshold alert to $ThresholdAlertEnabled." -Level Verbose
    }

    # Checking the option to disconnect users
    if ($DisconnectUsers) {
        [int]$DisconnectUsers = 1
        Write-Message -Message "Setting disconnect users to $DisconnectUsers." -Level Verbose
    } else {
        [int]$DisconnectUsers = 0
        Write-Message -Message "Setting disconnect users to $DisconnectUsers." -Level Verbose
    }

    # Check hte combination of the restore mode with the option to disconnect users
    if ($RestoreMode -eq 0 -and $DisconnectUsers -ne 0) {
        if ($Force) {
            [int]$DisconnectUsers = 0
            Write-Message -Message "Illegal combination of database restore mode $RestoreMode and disconnect users $DisconnectUsers. Setting it to $DisconnectUsers." -Level Warning
        } else {
            Stop-Function -Message "Illegal combination of database restore mode $RestoreMode and disconnect users $DisconnectUsers." -Target $SqlInstance -Continue
        }
    }

    # Set up the query
    $Query = "EXEC master.sys.sp_add_log_shipping_secondary_database
        @secondary_database = '$SecondaryDatabase'
        ,@primary_server = '$PrimaryServer'
        ,@primary_database = '$PrimaryDatabase'
        ,@restore_delay = $RestoreDelay
        ,@restore_all = $RestoreAll
        ,@restore_mode = $RestoreMode
        ,@disconnect_users = $DisconnectUsers
        ,@restore_threshold = $RestoreThreshold
        ,@threshold_alert = $ThresholdAlert
        ,@threshold_alert_enabled = $ThresholdAlertEnabled
        ,@history_retention_period = $HistoryRetention "


    if ($ServerSecondary.Version.Major -le 12) {
        $Query += "
        ,@ignoreremotemonitor = 1"
    }

    # Add inf extra options to the query when needed
    if ($BlockSize -ne -1) {
        $Query += ",@block_size = $BlockSize"
    }

    if ($BufferCount -ne -1) {
        $Query += ",@buffer_count = $BufferCount"
    }

    if ($MaxTransferSize -ge 1) {
        $Query += ",@max_transfer_size = $MaxTransferSize"
    }

    if ($Force -and ($ServerSecondary.Version.Major -gt 9)) {
        $Query += ",@overwrite = 1;"
    } else {
        $Query += ";"
    }

    # Execute the query to add the log shipping primary
    if ($PSCmdlet.ShouldProcess($SqlServer, ("Configuring logshipping for secondary database $SecondaryDatabase on $SqlInstance"))) {
        try {
            Write-Message -Message "Configuring logshipping for secondary database $SecondaryDatabase on $SqlInstance." -Level Verbose
            Write-Message -Message "Executing query:`n$Query" -Level Verbose
            $ServerSecondary.Query($Query)

            # For versions prior to SQL Server 2014, adding a monitor works in a different way.
            # The next section makes sure the settings are being synchronized with earlier versions
            if ($MonitorServer -and ($SqlInstance.Version.Major -lt 12)) {
                # Get the details of the primary database
                $query = "SELECT * FROM msdb.dbo.log_shipping_monitor_secondary WHERE primary_database = '$PrimaryDatabase' AND primary_server = '$PrimaryServer'"
                $lsDetails = $ServerSecondary.Query($query)

                # Setup the procedure script for adding the monitor for the primary
                $query = "EXEC msdb.dbo.sp_processlogshippingmonitorsecondary @mode = $MonitorServerSecurityMode
                    ,@secondary_server = '$SqlInstance'
                    ,@secondary_database = '$SecondaryDatabase'
                    ,@secondary_id = '$($lsDetails.secondary_id)'
                    ,@primary_server = '$($lsDetails.primary_server)'
                    ,@primary_database = '$($lsDetails.primary_database)'
                    ,@restore_threshold = $($lsDetails.restore_threshold)
                    ,@threshold_alert = $([int]$lsDetails.threshold_alert)
                    ,@threshold_alert_enabled = $([int]$lsDetails.threshold_alert_enabled)
                    ,@history_retention_period = $([int]$lsDetails.history_retention_period)
                    ,@monitor_server = '$MonitorServer'
                    ,@monitor_server_security_mode = $MonitorServerSecurityMode "

                # Check the MonitorServerSecurityMode if it's SQL Server authentication
                if ($MonitorServer -and $MonitorServerSecurityMode -eq 0 ) {
                    $query += ",@monitor_server_login = N'$MonitorLogin'
                        ,@monitor_server_password = N'$MonitorPassword' "
                }

                Write-Message -Message "Configuring monitor server for secondary database $SecondaryDatabase." -Level Verbose
                Write-Message -Message "Executing query:`n$query" -Level Verbose
                Invoke-DbaQuery -SqlInstance $MonitorServer -SqlCredential $MonitorCredential -Database msdb -Query $query

                $query = "
                UPDATE msdb.dbo.log_shipping_secondary
                SET monitor_server = '$MonitorServer', user_specified_monitor = 1
                WHERE secondary_id = '$($lsDetails.secondary_id)'
                "

                Write-Message -Message "Updating monitor information for the secondary database $Database." -Level Verbose
                Write-Message -Message "Executing query:`n$query" -Level Verbose
                $ServerSecondary.Query($query)

            }
        } catch {
            Write-Message -Message "$($_.Exception.InnerException.InnerException.InnerException.InnerException.Message)" -Level Warning
            Stop-Function -Message "Error executing the query.`n$($_.Exception.Message)`n$Query"  -ErrorRecord $_ -Target $SqlInstance -Continue
        }
    }

    Write-Message -Message "Finished adding the secondary database $SecondaryDatabase to log shipping." -Level Verbose

}