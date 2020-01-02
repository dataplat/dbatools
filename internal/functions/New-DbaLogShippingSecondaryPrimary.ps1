function New-DbaLogShippingSecondaryPrimary {
    <#
        .SYNOPSIS
            New-DbaLogShippingPrimarySecondary sets up the primary information for the primary database.

        .DESCRIPTION
            New-DbaLogShippingPrimarySecondary sets up the primary information, adds local and remote monitor links,
            and creates copy and restore jobs for the specified primary database.
            This is executed on the secondary server.

        .PARAMETER SqlInstance
            SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER BackupSourceDirectory
            The directory where transaction log backup files from the primary server are stored.

        .PARAMETER BackupDestinationDirectory
            The directory on the secondary server where backup files are copied to.

        .PARAMETER CopyJob
            The name to use for the SQL Server Agent job being created to copy transaction log backups to the secondary server.

        .PARAMETER CopyJobID
            The UID associated with the copy job on the secondary server.

        .PARAMETER FileRetentionPeriod
            The length of time, in minutes, that a backup file is retained on the secondary server in the path specified by the BackupDestinationDirectory parameter before being deleted.
            The default is 14420.

        .PARAMETER MonitorServer
            Is the name of the monitor server. The default is the secondary server.

        .PARAMETER MonitorServerLogin
            Is the username of the account used to access the monitor server.

        .PARAMETER MonitorServerPassword
            Is the password of the account used to access the monitor server.

        .PARAMETER MonitorServerSecurityMode
            The security mode used to connect to the monitor server. Allowed values are 0, "sqlserver", 1, "windows"
            The default is 1 or Windows.

        .PARAMETER PrimaryServer
            The name of the primary instance of the Microsoft SQL Server Database Engine in the log shipping configuration.

        .PARAMETER PrimaryDatabase
            Is the name of the database on the primary server.

        .PARAMETER RestoreJob
            Is the name of the SQL Server Agent job on the secondary server that restores the backups to the secondary database.

        .PARAMETER RestoreJobID
            The UID associated with the restore job on the secondary server.

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

        .LINK
            https://dbatools.io/New-DbaLogShippingPrimarySecondary

        .EXAMPLE
            New-DbaLogShippingSecondaryPrimary -SqlInstance sql2 -BackupSourceDirectory "\\sql1\logshipping\DB1" -BackupDestinationDirectory D:\Data\logshippingdestination\DB1_DR -CopyJob LSCopy_sql2_DB1_DR -FileRetentionPeriod 4320 -MonitorServer sql2 -MonitorServerSecurityMode 'Windows' -PrimaryServer sql1 -PrimaryDatabase DB1 -RestoreJob LSRestore_sql2_DB1_DR
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [parameter(Mandatory)]
        [object]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$BackupSourceDirectory,
        [string]$BackupDestinationDirectory,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$CopyJob,
        [int]$FileRetentionPeriod = 14420,
        [string]$MonitorServer,
        [PSCredential]$MonitorCredential,
        [Parameter(Mandatory)]
        [ValidateSet(0, "sqlserver", 1, "windows")]
        [object]$MonitorServerSecurityMode = 1,
        [object]$PrimaryServer,
        [PSCredential]$PrimarySqlCredential,
        [object]$PrimaryDatabase,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RestoreJob,
        [switch]$EnableException,
        [switch]$Force
    )

    # Try connecting to the instance
    try {
        $ServerSecondary = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
    } catch {
        Stop-Function -Message "Error occurred while establishing connection to $SqlInstance" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance -Continue
    }

    # Try connecting to the instance
    try {
        $ServerPrimary = Connect-SqlInstance -SqlInstance $PrimaryServer -SqlCredential $PrimarySqlCredential
    } catch {
        Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $PrimaryServer -Continue
    }

    # Check if the backup UNC path is correct and reachable
    if ([bool]([uri]$BackupDestinationDirectory).IsUnc -and $BackupDestinationDirectory -notmatch '^\\(?:\\[^<>:`"/\\|?*]+)+$') {
        Stop-Function -Message "The backup destination path should be formatted in the form \\server\share." -Target $SqlInstance
        return
    } else {
        if (-not ((Test-Path $BackupDestinationDirectory -PathType Container -IsValid) -and ((Get-Item $BackupDestinationDirectory).PSProvider.Name -eq 'FileSystem'))) {
            Stop-Function -Message "The backup destination path is not valid or can't be reached." -Target $SqlInstance
            return
        }
    }

    # Check the MonitorServer
    if (-not $MonitorServer -and $Force) {
        $MonitorServer = $SqlInstance
        Write-Message -Message "Setting monitor server to $MonitorServer." -Level Verbose
    }

    # Check of the MonitorServerSecurityMode value is of type string and set the integer value
    if ($MonitorServerSecurityMode -notin 0, 1) {
        $MonitorServerSecurityMode = switch ($MonitorServerSecurityMode) { "WINDOWS" { 1 } "SQLSERVER" { 0 } }
        Write-Message -Message "Setting monitor server security mode to $MonitorServerSecurityMode." -Level Verbose
    }

    # Check the MonitorServerSecurityMode if it's SQL Server authentication
    if ($MonitorServerSecurityMode -eq 0 -and -not $MonitorCredential) {
        Stop-Function -Message "The MonitorServerCredential cannot be empty when using SQL Server authentication." -Target $SqlInstance -Continue
        return
    } elseif ($MonitorServerSecurityMode -eq 0 -and $MonitorCredential) {
        # Get the username and password from the credential
        $MonitorLogin = $MonitorCredential.UserName
        $MonitorPassword = $MonitorCredential.GetNetworkCredential().Password

        # Check if the user is in the database
        if ($ServerSecondary.Databases['master'].Users.Name -notcontains $MonitorLogin) {
            Stop-Function -Message "User $MonitorLogin for monitor login must be in the master database." -Target $SqlInstance -Continue
            return
        }
    }

    # Check if the database is present on the primary sql server
    if ($ServerPrimary.Databases.Name -notcontains $PrimaryDatabase) {
        Stop-Function -Message "Database $PrimaryDatabase is not available on instance $PrimaryServer" -Target $PrimaryServer -Continue
        return
    }

    # Set up the query
    $Query = "
        DECLARE @LS_Secondary__CopyJobId AS uniqueidentifier
        DECLARE @LS_Secondary__RestoreJobId	AS uniqueidentifier
        DECLARE @LS_Secondary__SecondaryId AS uniqueidentifier
        EXEC master.sys.sp_add_log_shipping_secondary_primary
                @primary_server = N'$PrimaryServer'
                ,@primary_database = N'$PrimaryDatabase'
                ,@backup_source_directory = N'$BackupSourceDirectory'
                ,@backup_destination_directory = N'$BackupDestinationDirectory'
                ,@copy_job_name = N'$CopyJob'
                ,@restore_job_name = N'$RestoreJob'
                ,@file_retention_period = $FileRetentionPeriod
                ,@copy_job_id = @LS_Secondary__CopyJobId OUTPUT
                ,@restore_job_id = @LS_Secondary__RestoreJobId OUTPUT
                ,@secondary_id = @LS_Secondary__SecondaryId OUTPUT "

    if ($MonitorServer) {
        $Query += ",@monitor_server = N'$MonitorServer'
                ,@monitor_server_security_mode = $($MonitorServerSecurityMode) "
    }


    # Check the MonitorServerSecurityMode if it's SQL Server authentication
    if ($MonitorServerSecurityMode -eq 0 -and $MonitorServer) {
        $Query += ",@monitor_server_login = N'$MonitorLogin'
            ,@monitor_server_password = N'$MonitorPassword' "
    }

    if ($ServerSecondary.Version.Major -gt 9) {
        $Query += ",@overwrite = 1;"
    } else {
        $Query += ";"
    }

    # Execute the query to add the log shipping primary
    if ($PSCmdlet.ShouldProcess($SqlServer, ("Configuring logshipping making settings for the primary database to secondary database on $SqlInstance"))) {
        try {
            Write-Message -Message "Configuring logshipping making settings for the primary database." -Level Verbose
            Write-Message -Message "Executing query:`n$Query" -Level Verbose
            $ServerSecondary.Query($Query)
        } catch {
            Write-Message -Message "$($_.Exception.InnerException.InnerException.InnerException.InnerException.Message)" -Level Warning
            Stop-Function -Message "Error executing the query.`n$($_.Exception.Message)"  -ErrorRecord $_ -Target $SqlInstance -Continue
        }
    }

    Write-Message -Message "Finished configuring of secondary database to primary database $PrimaryDatabase." -Level Verbose
}