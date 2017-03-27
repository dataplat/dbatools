Function New-DbaLogShippingPrimaryDatabase
{
<#
.SYNOPSIS 
New-DbaLogShippingPrimaryDatabase creates a new log shipping database 

.DESCRIPTION


.PARAMETER Source

.PARAMETER Destination

.PARAMETER SqlCredential

.PARAMETER DestinationSqlCredential

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
		[parameter(Mandatory = $true)]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential,
        [string[]]$Database,
        [string]$BackupDirectory,
        [string]$BackupShare,
        [string]$BackupJobName = "LS_Backup_",
        [int]$BackupRetentionMinutes,
        [switch]$Compression,
        [int]$BackupThresshold = 60,
        [switch]$AlertEnabled,
        [switch]$ThressholdAlertMinutes = 14420,
        [int]$HistoryRetentionMinutes = 14420,
        [swich]$UseDatabaseSuffix,
        [switch]$Force,
        [switch]$Silent
    )

    DynamicParam { if ($source) { return (Get-ParamSqlServerDatabases -SqlServer $Source -SqlCredential $SqlCredential) }

    BEGIN
    {
        # Connect to the database server
        $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
        
        # Check if the instance is the right version
        if ($server.versionMajor -lt 9)
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
        if($BackupDirectory.StartsWith("\\"))
        {
            if(-not (Test-Path($BackupDirectory)))
            {
                Stop-Function -Message "Backup Directory doesn't exist, please enter a valid directory or check the permissions."
            }
        }

        # Check the backup backup retention
        if(-not $BackupRetentionMinutes)
        {
            Stop-Function -Message "Please enter the backup retention period."
        }

        # Check the backup compression setting
        if(-not $Compression)
        {
            $DefaultBackupCompression = Get-DbaSpConfigure -SqlServer $SqlServer -Configs DefaultBackupCompression
            $Compression = $DefaultBackupCompression.RunningValue
        }

        # Check if alerting needs to be enabled
        if($AlertEnabled)
        {
            [bool]$ThressholdAlert = 1
        }

        # Check if some things need to be forced
        if($Force)
        {
            [bool]$Overwrite = 1
        }
        else 
        {
            [bool]$Overwrite = 0    
        }
    }

    PROCESS
    {
        # If the database name needs to be used as the suffix
        if($UseDatabaseSuffix)
        {
            # Set the backup directory
            if($BackupDirectory.EndsWith("\"))
            {
                $NewBackupDirectory = "$($BackupDirectory)$($Database)"
            }
            else 
            {
                $NewBackupDirectory += "$($BackupDirectory)\$($Database)"
            }

            # Set the backup share
            if($BackupShare.EndsWith("\"))
            {
                $NewBackupShare += "$($BackupShare)$($Database)"
            }
            else 
            {
                $NewBackupShare += "$($BackupShare)\$($Database)"
            }

            # Check the existence of the backup dirctory
            if(-not (Test-Path $BackupShare))
            {
                try 
                {
                    Write-Message -Message "Backup directory/share doesn't exist. Creating.." -Level 5 -Silent $Silent
                    if($IsLocal)
                    {
                        New-Item -Path $BackupDirectory -ItemType Directory
                    }
                    else 
                    {
                        New-Item -Path $BackupShare -ItemType Directory
                    }
                }
                catch 
                {
                    Stop-Function -Message "Couldn't create backup directory/share $($BackupDirectory). Stopping.." -Silent $Silent
                }
            }
        }

        # Set the name for the job
        if($BackupJobName.EndsWith("_") -or $BackupJobName.EndsWith("-"))
        {
            $BackupDirectory += "$($Database)"
        } 
        else 
        {
            $BackupDirectory += "_$($Database)"    
        }

        # Setup the query
        $Sql = "EXEC master.dbo.sp_add_log_shipping_primary_database 
		@database = N'$($Database)' 
		,@backup_directory = N'$($NewBackupDirectory)' 
		,@backup_share = N'$($NewBackupShare)' 
		,@backup_job_name = N'$($BackupJobName)' 
		,@backup_retention_period = $($BackupRetentionMinutes)
		,@backup_compression = $($Compression)
		,@backup_threshold = $($BackupThresshold) "

        if($AlertEnabled)
        {
            $Sql += ",@threshold_alert_enabled = 1"
        }

        $SQL += ",@history_retention_period = $($HistoryRetentionMinutes) 
		,@backup_job_id = @LS_BackupJobId OUTPUT 
		,@primary_id = @LS_PrimaryId OUTPUT 
		,@overwrite = $($Overwrite) "

        # Execute the command
        if ($Pscmdlet.ShouldProcess($SqlServer, "Executing $sql and informing that a restart is required."))
		{
			try
			{
                $server.Databases['master'].ExecuteNonQuery($Sql)
            }
            catch
            {
                Stop-Function -Message "Couldn't create log shipping primary. $($_)"
                return
            }
        }

    }
    
    END
    {
        Write-Message -Message "Creation of primary log shipping database ended."
    }

}