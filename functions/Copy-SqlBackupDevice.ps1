Function Copy-SqlBackupDevice
{
<#
.SYNOPSIS
Copies backup devices one by one. Copies both SQL code and the backup file itself.

.DESCRIPTION
Backups are migrated using Admin shares.  If destination directory does not exist, SQL Server's default backup directory will be used.

If backup device with same name exists on destination, it will not be dropped and recreated unless -Force is used.

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

.PARAMETER Source
Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER Destination
Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SourceSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter. 

Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. 	
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER DestinationSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter. 

Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. 	
To connect as a different Windows user, run PowerShell as that user.

.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Copy-SqlBackupDevice

.EXAMPLE   
Copy-SqlBackupDevice -Source sqlserver2014a -Destination sqlcluster

Copies all server backup devices from sqlserver2014a to sqlcluster, using Windows credentials. If backup devices with the same name exist on sqlcluster, they will be skipped.

.EXAMPLE   
Copy-SqlBackupDevice -Source sqlserver2014a -Destination sqlcluster -BackupDevices backup01 -SourceSqlCredential $cred -Force

Copies a single backup device, backup01, from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a
and Windows credentials for sqlcluster. If a backup device with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

.EXAMPLE   
Copy-SqlBackupDevice -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

Shows what would happen if the command were executed using force.
#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true)]
		[object]$Source,
		[parameter(Mandatory = $true)]
		[object]$Destination,
		[System.Management.Automation.PSCredential]$SourceSqlCredential,
		[System.Management.Automation.PSCredential]$DestinationSqlCredential,
		[switch]$Force
	)
	DynamicParam { if ($source) { return (Get-ParamSqlBackupDevices -SqlServer $Source -SqlCredential $SourceSqlCredential) } }
	
	BEGIN
	{
		$backupdevices = $psboundparameters.BackupDevices
		
		$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
		
		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName
		
		$serverbackupdevices = $sourceserver.BackupDevices
		$destbackupdevices = $destserver.BackupDevices
		
		Write-Output "Resolving NetBios name"
		$destnetbios = Resolve-NetBiosName $destserver
		$sourcenetbios = Resolve-NetBiosName $sourceserver
		
	}
	PROCESS
	{
		
		foreach ($backupdevice in $serverbackupdevices)
		{
			$devicename = $backupdevice.name
			
			if ($BackupDevices.length -gt 0 -and $BackupDevices -notcontains $devicename) { continue }
			
			if ($destbackupdevices.name -contains $devicename)
			{
				if ($force -eq $false)
				{
					Write-Warning "backup device $devicename exists at destination. Use -Force to drop and migrate."
					continue
				}
				else
				{
					If ($Pscmdlet.ShouldProcess($destination, "Dropping backup device $devicename"))
					{
						try
						{
							Write-Verbose "Dropping backup device $devicename"
							$destserver.BackupDevices[$devicename].Drop()
						}
						catch { Write-Exception $_; continue }
					}
				}
			}
			
			If ($Pscmdlet.ShouldProcess($destination, "Generating SQL code for $devicename"))
			{
				Write-Output "Scripting out SQL for $devicename"
				try
				{
					$sql = $backupdevice.Script() | Out-String
					$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
				}
				catch { 
					Write-Exception $_
					continue 
				}
			}
			
			If ($Pscmdlet.ShouldProcess("console", "Stating that the actual file copy is about to occur"))
			{
				Write-Output "Preparing to copy actual backup file"
			}
			
			$path = Split-Path $sourceserver.BackupDevices[$devicename].PhysicalLocation
			$filename = Split-Path -Leaf $sourceserver.BackupDevices[$devicename].PhysicalLocation
			
			$destpath = Join-AdminUnc $destnetbios $path
			$sourcepath = Join-AdminUnc $sourcenetbios $sourceserver.BackupDevices[$devicename].PhysicalLocation
			
			Write-Output "Checking if directory $destpath exists"
			
			if ($(Test-SqlPath -SqlServer $Destination -Path $path) -eq $false)
			{
				$backupdirectory = $destserver.BackupDirectory
				$destpath = Join-AdminUnc $destnetbios $backupdirectory
				
				# if ($force -eq $false) { Write-Warning "Destination directory does not exist. Use -Force to use the default backup directory at $backupdirectory "; continue }
				If ($Pscmdlet.ShouldProcess($destination, "Updating create code to use new path"))
				{
					Write-Warning "$path doesn't exist on $destination"
					Write-Warning "Using default backup directory $backupdirectory"
					
					try
					{
						Write-Output "Updating $devicename to use $backupdirectory"
						$sql = $sql -replace $path, $backupdirectory
						$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
					}
					catch { 
						Write-Exception $_
						continue 
					}
				}
			}
			
			If ($Pscmdlet.ShouldProcess($destination, "Adding backup device $devicename"))
			{
				Write-Output "Adding backup device $devicename on $destination"
				try
				{
					$destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
					$destserver.BackupDevices.Refresh()
				}
				catch { 
					Write-Exception $_
					continue 
				}
			}
			
			If ($Pscmdlet.ShouldProcess($destination, "Copying $sourcepath to $destpath using BITSTransfer"))
			{
				try
				{
					Start-BitsTransfer -Source $sourcepath -Destination $destpath
					Write-Output "Backup device $devicename successfully copied"
				}
				catch { Write-Exception $_ }
			}
		}
	}
	
	END
	{
		$sourceserver.ConnectionContext.Disconnect()
		$destserver.ConnectionContext.Disconnect()
		If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "backup device migration finished" }
	}
}