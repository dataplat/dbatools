Function New-DbaLogShippingPrimaryDatabase
{
<#
.SYNOPSIS 
New-DbaLogShippingPrimaryDatabase sets up the log shipping for the primary database

.DESCRIPTION
To set up log shipping, several configurations need to be made on the primary instance.
This function takes care of configuring log shipping for a database.
The function does support values from pipeline so it's possible to enter multiple databases
at the same time for the same log ship settings.

.PARAMETER SqlServer
SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2005 or greater.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter. 

Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. 	
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER Database
Database that needs to set up for log shipping.

.PARAMETER BackupDirectory
Is the path to the backup folder on the primary server. 

.PARAMETER BackupShare
Is the network path to the backup directory on the primary server. 

.PARAMETER BackupJobNamePrefix
Is the name of the SQL Server Agent job on the primary server that copies the backup into the backup folder.
The name if the prefix, the function will add the name of the database.

.PARAMETER BackupRetentionMinutes
Is the length of time, in minutes, to retain the log backup file in the backup directory on the primary server. 

.PARAMETER BackupThresshold
Is the length of time, in minutes, after the last backup before a threshold_alert error is raised. The default is 60 minutes. 

.PARAMETER Compression
Specifies whether a log shipping configuration uses backup compression. This parameter is supported only in SQL Server 2008 Enterprise (or a later version). 
If the parameter is not set and the version of SQL Server is equal or higher than SQL Server 2008 the default of the server will be retrieved.

.PARAMETER AlertEnabled
Specifies whether an alert will be raised when backup_threshold is exceeded.

.PARAMETER ThressholdAlertMinutes
Is the alert to be raised when the backup threshold is exceeded. The default is 14,420. 

.PARAMETER HistoryRetentionMinutes
Is the length of time in minutes in which the history will be retained. The default is 14,420.

.PARAMETER UseDatabaseSuffix
Is used to change several parameter values to include the name of the databases. 
Parameters that will be changed with this parameter are BackupDirectory, BackupShare

.PARAMETER Force
When set the original settings will be overwriten.

.PARAMETER Silent
Whether the silent switch was set in the calling function.
If true, it will write errors, if any, but not write to the screen without explicit override using -Debug or -Verbose.
If false, it will print a warning if in wrning mode. It will also be willing to write a message to the screen, if the level is within the range configured for that.

.PARAMETER WhatIf
Shows what would happen if the command were executed 

.NOTES 
Original Author: Sander Stad (@sqlstad, sqlstad.nl)
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
.LINK
https://dbatools.io/New-DbaLogShippingPrimaryDatabase

.EXAMPLE   

.EXAMPLE   
#>

    [CmdletBinding(SupportsShouldProcess = $true)]

    param (
		[parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential,
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string[]]$Database,
        [parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]
        [string]$BackupDirectory,
        [parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]
        [string]$BackupShare,
        [string]$BackupJobNamePrefix = "LS_Backup_",
        [parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]
        [int]$BackupRetentionMinutes,
        [int]$BackupThresshold = 60,
        [switch]$Compression,
        [switch]$AlertEnabled,
        [switch]$ThressholdAlertMinutes = 14420,
        [int]$HistoryRetentionMinutes = 14420,
        [swich]$UseDatabaseSuffix,
        [switch]$Force,
        [switch]$Silent
    )

    BEGIN
    {
        # Connect to the database server
        $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
        
        # Check if the instance is the right version
        if ($server.VersionMajor -lt 9)
		{
			Stop-Function -Message "Log Shipping is only supported in SQL Server 2005 and above. Quitting." -Silent $Silent
            return
        }

        # Check the instance if it is a named instance
        $ServerName, $InstanceName = $SqlServer.Split("\")
        
        if ($null -eq $InstanceName)
        {
            $InstanceName = "MSSQLSERVER"
        }
        
        # Check if it's local or remote
        $IsLocal = $false
        if ($ServerName -in ".", "localhost", $env:ServerNamename, "127.0.0.1")
        {
            $IsLocal = $true
        }

        # Check the backup directory
        if(-not (Test-Path($BackupDirectory)))
        {
            Stop-Function -Message "Backup Directory doesn't exist, please enter a valid directory or check the permissions."
            return
        }

        # Check the backup backup retention
        if(-not $BackupRetentionMinutes)
        {
            Stop-Function -Message "Please enter the backup retention period."
        }

        # Check the backup compression setting
        $BackupCompression = 0
        if((-not $Compression) -and ($Server.VersionMajor -ge 10))
        {
            $DefaultBackupCompression = Get-DbaSpConfigure -SqlServer $SqlServer -Configs DefaultBackupCompression
            $BackupCompression = $DefaultBackupCompression.RunningValue
        }

        # Check if some things need to be forced
        $Overwrite = 0 
        if($Force)
        {
            $Overwrite = 1
        }

    }

    PROCESS
    {
        $NewBackupDirectory = $BackupDirectory

        # If the database name needs to be used as the suffix
        if($UseDatabaseSuffix)
        {
            # Set the backup directory
            if(-not $BackupDirectory.EndsWith("\"))
            {
                $NewBackupDirectory = "$($BackupDirectory)\"
            }
            $NewBackupDirectory += "$($Database)"
            
            # Set the backup share
            if(-not $BackupShare.EndsWith("\"))
            {
                $NewBackupShare += "$($BackupShare)\"
            }
            $NewBackupShare += "$($Database)"
            
            # Check the existence of the backup dirctory
            if(-not (Test-Path $NewBackupShare))
            {
                try 
                {
                    Write-Message -Message "Backup directory/share doesn't exist. Creating.." -Level 5 -Silent $Silent
                    if($IsLocal)
                    {
                        New-Item -Path $NewBackupDirectory -ItemType Directory
                    }
                    else 
                    {
                        New-Item -Path $NewBackupShare -ItemType Directory
                    }
                }
                catch 
                {
                    Stop-Function -Message "Couldn't create backup directory/share $($BackupDirectory). $($_.Exception.Message)" -Silent $Silent
                }
            }
        }

        # Set the name for the job
        if($BackupJobNamePrefix.EndsWith("_") -or $BackupJobNamePrefix.EndsWith("-"))
        {
            $BackupJobNamePrefix += "$($Database)"
        } 
        else 
        {
            $BackupJobNamePrefix += "_$($Database)"    
        }

        # Setup the query
        $SqlCmd = "EXEC master.dbo.sp_add_log_shipping_primary_database 
            @database = N'$($Database)' 
            ,@backup_directory = N'$($NewBackupDirectory)' 
            ,@backup_share = N'$($NewBackupShare)' 
            ,@backup_job_name = N'$($BackupJobNamePrefix)' 
            ,@backup_retention_period = $($BackupRetentionMinutes)
            ,@backup_compression = $($BackupCompression)
            ,@backup_threshold = $($BackupThresshold) 
            ,@history_retention_period = $($HistoryRetentionMinutes) 
            ,@backup_job_id = @LS_BackupJobId OUTPUT 
            ,@primary_id = @LS_PrimaryId OUTPUT 
            ,@overwrite = $($Overwrite) "

        if($AlertEnabled)
        {
            $SqlCmd += ",@threshold_alert_enabled = 1
            ,@threshold_alert = $($ThressholdAlertMinutes) "
        }

        # Execute the command
        if ($Pscmdlet.ShouldProcess($SqlServer, "Executing SQL Command on $($SqlServer)"))
		{
			try
			{
                $server.Databases['master'].ExecuteNonQuery($SqlCmd)
            }
            catch
            {
                Stop-Function -Message "Couldn't create log shipping primary. $($_.Exception.Message)"
                return
            }
        }

    }
    
    END
    {
        Write-Message -Message "Creation of primary log shipping database ended." -Level 2 -Silent $Silent
    }

}