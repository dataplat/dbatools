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
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

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

        .PARAMETER CompressBackup
            Enables the use of backup compression

        .PARAMETER ThresholdAlert
            Is the length of time, in minutes, when the alert is to be raised when the backup threshold is exceeded.
            The default is 14,420.

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
            New-DbaLogShippingPrimaryDatabase -SqlInstance sql1 -Database DB1 -BackupDirectory D:\data\logshipping -BackupJob LSBackup_DB1 -BackupRetention 4320 -BackupShare "\\sql1\logshipping" -BackupThreshold 60 -CompressBackup -HistoryRetention 14420 -MonitorServer sql1 -ThresholdAlertEnabled

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]

    param (
        [parameter(Mandatory)]
        [object]$SqlInstance,
        [System.Management.Automation.PSCredential]$SqlCredential,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]$Database,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$BackupDirectory,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$BackupJob,
        [Parameter(Mandatory)]
        [int]$BackupRetention,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$BackupShare,
        [int]$BackupThreshold = 60,
        [switch]$CompressBackup,
        [int]$ThresholdAlert = 14420,
        [int]$HistoryRetention = 14420,
        [string]$MonitorServer,
        [ValidateSet(0, "sqlserver", 1, "windows")]
        [object]$MonitorServerSecurityMode = 1,
        [System.Management.Automation.PSCredential]$MonitorCredential,
        [switch]$ThresholdAlertEnabled,
        [switch]$EnableException,
        [switch]$Force
    )

    # Try connecting to the instance
    try {
        $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
    } catch {
        Stop-Function -Message "Could not connect to Sql Server instance" -Target $SqlInstance -Continue
    }

    # Check if the backup UNC path is correct and reachable
    if ([bool]([uri]$BackupShare).IsUnc -and $BackupShare -notmatch '^\\(?:\\[^<>:`"/\\|?*]+)+$') {
        Stop-Function -Message "The backup share path $BackupShare should be formatted in the form \\server\share." -Target $SqlInstance
        return
    } else {
        if (-not ((Test-Path $BackupShare -PathType Container -IsValid) -and ((Get-Item $BackupShare).PSProvider.Name -eq 'FileSystem'))) {
            Stop-Function -Message "The backup share path $BackupShare is not valid or can't be reached." -Target $SqlInstance
            return
        }
    }

    # Check the backup compression
    if ($CompressBackup -eq $true) {
        Write-Message -Message "Setting backup compression to 1." -Level Verbose
        $BackupCompression = 1
    } elseif ($CompressBackup -eq $false) {
        Write-Message -Message "Setting backup compression to 0." -Level Verbose
        $BackupCompression = 0
    } elseif (-not $CompressBackup) {
        $defaultCompression = (Get-DbaSpConfigure -SqlInstance $SqlInstance -ConfigName DefaultBackupCompression).ConfiguredValue
        Write-Message -Message "Setting backup compression to default value $defaultCompression." -Level Verbose
        $BackupCompression = $defaultCompression

    }

    # Check of the MonitorServerSecurityMode value is of type string and set the integer value
    if ($MonitorServerSecurityMode -notin 0, 1) {
        $MonitorServerSecurityMode = switch ($MonitorServerSecurityMode) { "WINDOWS" { 1 } "SQLSERVER" { 0 } }
        Write-Message -Message "Setting monitor server security mode to $MonitorServerSecurityMode." -Level Verbose
    }

    # Check the MonitorServer
    if (-not $MonitorServer -and $Force) {
        Write-Message -Message "Setting monitor server to $SqlInstance." -Level Verbose
        $MonitorServer = $SqlInstance
    }

    # Check the MonitorServerSecurityMode if it's SQL Server authentication
    if ($MonitorServerSecurityMode -eq 0 -and -not $MonitorCredential) {
        Stop-Function -Message "The MonitorServerCredential cannot be empty when using SQL Server authentication." -Target $SqlInstance
        return
    } elseif ($MonitorServerSecurityMode -eq 0 -and $MonitorCredential) {
        # Get the username and password from the credential
        $MonitorLogin = $MonitorCredential.UserName
        $MonitorPassword = $MonitorCredential.GetNetworkCredential().Password

        # Check if the user is in the database
        if ($server.Databases['master'].Users.Name -notcontains $MonitorLogin) {
            Stop-Function -Message "User $MonitorLogin for monitor login must be in the master database." -Target $SqlInstance
            return
        }
    }

    # Check if the database is present on the source sql server
    if ($server.Databases.Name -notcontains $Database) {
        Stop-Function -Message "Database $Database is not available on instance $SqlInstance" -Target $SqlInstance
        return
    }

    # Check the if Threshold alert needs to be enabled
    if ($ThresholdAlertEnabled) {
        [int]$ThresholdAlertEnabled = 1
        Write-Message -Message "Setting Threshold alert to $ThresholdAlertEnabled." -Level Verbose
    } else {
        [int]$ThresholdAlertEnabled = 0
        Write-Message -Message "Setting Threshold alert to $ThresholdAlertEnabled." -Level Verbose
    }

    # Set the log shipping primary
    $Query = "
        DECLARE @LS_BackupJobId AS uniqueidentifier;
        DECLARE @LS_PrimaryId AS uniqueidentifier;
        EXEC master.sys.sp_add_log_shipping_primary_database
            @database = N'$Database'
            ,@backup_directory = N'$BackupDirectory'
            ,@backup_share = N'$BackupShare'
            ,@backup_job_name = N'$BackupJob'
            ,@backup_retention_period = $BackupRetention
            ,@backup_threshold = $BackupThreshold
            ,@history_retention_period = $HistoryRetention
            ,@backup_job_id = @LS_BackupJobId OUTPUT
            ,@primary_id = @LS_PrimaryId OUTPUT "

    if ($SqlInstance.Version.Major -gt 9) {
        $Query += ",@backup_compression = $BackupCompression"
    }

    if ($MonitorServer) {
        $Query += "
            ,@monitor_server = N'$MonitorServer'
            ,@monitor_server_security_mode = $MonitorServerSecurityMode
            ,@threshold_alert = $ThresholdAlert
            ,@threshold_alert_enabled = $ThresholdAlertEnabled"

        #if ($MonitorServer -and ($SqlInstance.Version.Major -ge 16)) {
        if ($server.Version.Major -ge 12) {
            # Check the MonitorServerSecurityMode if it's SQL Server authentication
            if ($MonitorServer -and $MonitorServerSecurityMode -eq 0 ) {
                $Query += "
                    ,@monitor_server_login = N'$MonitorLogin'
                    ,@monitor_server_password = N'$MonitorPassword' "
            }
        } else {
            $Query += "
                ,@ignoreremotemonitor = 1"
        }
    }

    if ($Force -or ($server.Version.Major -gt 9)) {
        $Query += "
            ,@overwrite = 1;"
    } else {
        $Query += ";"
    }

    # Execute the query to add the log shipping primary
    if ($PSCmdlet.ShouldProcess($SqlServer, ("Configuring logshipping for primary database $Database on $SqlInstance"))) {
        try {
            Write-Message -Message "Configuring logshipping for primary database $Database." -Level Verbose
            Write-Message -Message "Executing query:`n$Query" -Level Verbose
            $server.Query($Query)

            # For versions prior to SQL Server 2014, adding a monitor works in a different way.
            # The next section makes sure the settings are being synchronized with earlier versions
            if ($MonitorServer -and ($server.Version.Major -lt 12)) {
                # Get the details of the primary database
                $query = "SELECT * FROM msdb.dbo.log_shipping_monitor_primary WHERE primary_database = '$Database'"
                $lsDetails = $server.Query($query)

                # Setup the procedure script for adding the monitor for the primary
                $query = "EXEC msdb.dbo.sp_processlogshippingmonitorprimary @mode = $MonitorServerSecurityMode
                    ,@primary_id = '$($lsDetails.primary_id)'
                    ,@primary_server = '$($lsDetails.primary_server)'
                    ,@monitor_server = '$MonitorServer' "

                # Check the MonitorServerSecurityMode if it's SQL Server authentication
                if ($MonitorServer -and $MonitorServerSecurityMode -eq 0 ) {
                    $query += "
                    ,@monitor_server_login = N'$MonitorLogin'
                    ,@monitor_server_password = N'$MonitorPassword' "
                }

                $query += "
                    ,@monitor_server_security_mode = 1
                    ,@primary_database = '$($lsDetails.primary_database)'
                    ,@backup_threshold = $($lsDetails.backup_threshold)
                    ,@threshold_alert = $($lsDetails.threshold_alert)
                    ,@threshold_alert_enabled = $([int]$lsDetails.threshold_alert_enabled)
                    ,@history_retention_period = $($lsDetails.history_retention_period)
                "

                Write-Message -Message "Configuring monitor server for primary database $Database." -Level Verbose
                Write-Message -Message "Executing query:`n$query" -Level Verbose
                Invoke-DbaQuery -SqlInstance $MonitorServer -SqlCredential $MonitorCredential -Database msdb -Query $query

                $query = "
                    UPDATE msdb.dbo.log_shipping_primary_databases
                    SET monitor_server = '$MonitorServer', user_specified_monitor = 1
                    WHERE primary_id = '$($lsDetails.primary_id)'
                "
                Write-Message -Message "Updating monitor information for the primary database $Database." -Level Verbose
                Write-Message -Message "Executing query:`n$query" -Level Verbose
                $server.Query($query)
            }
        } catch {
            Write-Message -Message "$($_.Exception.InnerException.InnerException.InnerException.InnerException.Message)" -Level Warning
            Stop-Function -Message "Error executing the query.`n$($_.Exception.Message)`n$($Query)" -ErrorRecord $_ -Target $SqlInstance -Continue
        }
    }

    Write-Message -Message "Finished adding the primary database $Database to log shipping." -Level Verbose

}