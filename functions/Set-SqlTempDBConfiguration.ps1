function Set-SqlTempDbConfiguration
{
<#
.SYNOPSIS
Sets tempdb data and log files according to best practices.

.DESCRIPTION
Function to calculate tempdb size and file configurations based on passed parameters, calculated values, and Microsoft
best practices. User must declare SQL Server to be configured and total data file size as mandatory values. Function will
then calculate number of data files based on logical cores on the target host and create evenly sized data files based
on the total data size declared by the user, with a log file 25% of the total data file size. Other parameters can adjust 
the settings as the user desires (such as different file paths, number of data files, and log file size). The function will
not perform any functions that would shrink or delete data files. If a user desires this, they will need to reduce tempdb
so that it is "smaller" than what the function will size it to before runnint the function.

.NOTES 
Original Author: Michael Fal (@Mike_Fal), http://mikefal.net

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

.PARAMETER SqlServer
SQLServer name or SMO object representing the SQL Server to connect to

.PARAMETER SqlCredential
PSCredential object to connect under. If not specified, currend Windows login will be used.

.PARAMETER DataFileCount
Integer of number of datafiles to create. If not specified, function will use logical cores of host.

.PARAMETER DataFileSizeMB
Total data file size in megabytes

.PARAMETER LogFileSizeMB
Log file size in megabyes. If not specified, function will use 25% of total data file size.

.PARAMETER DataPath 
File path to create tempdb data files in. If not specified, current tempdb location will be used.

.PARAMETER LogPath
File path to create tempdb log file in. If not specified, current tempdb location will be used.

.PARAMETER Script
Switch to generate script for tempdb configuration.

.PARAMETER WhatIf
Switch to generate configuration object.
.LINK
https://dbatools.io/Set-SqltempdbConfiguration

.EXAMPLE
Set-SqltempdbConfiguration -SqlServer localhost -DataFileSizeMB 1000

Creates tempdb with a number of datafiles equal to the logical cores where
each one is equal to 1000MB divided by number of logical cores and a log file
of 250MB

.EXAMPLE
Set-SqltempdbConfiguration -SqlServer localhost -DataFileSizeMB 1000 -DataFileCount 8

Creates tempdb with a number of datafiles equal to the logical cores where
each one is equal to 125MB and a log file of 250MB

.EXAMPLE
Set-SqltempdbConfiguration -SqlServer localhost -DataFileSizeMB 1000 -Script

Provides a SQL script output to configure tempdb according to the passed parameters

.EXAMPLE
Set-SqltempdbConfiguration -SqlServer localhost -DataFileSizeMB 1000 -Script

Returns PSObject representing tempdb configuration.
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[int]$DataFileCount,
		[Parameter(Mandatory = $true)]
		[int]$datafilesizemb,
		[int]$LogFileSizeMB,
		[string]$DataPath,
		[string]$LogPath,
		[string]$OutFile,
		[switch]$Script
	)
	BEGIN
	{
		$sql = @()
		Write-Verbose "Connecting to $SqlServer"
		$server = Connect-SqlServer $SqlServer -SqlCredential $SqlCredential
		
		if ($server.VersionMajor -lt 9)
		{
			throw "SQL Server 2000 is not supported"
		}
	}
	
	PROCESS
	{
		$cores = $server.Processors
		if ($cores -gt 8) { $cores = 8 }
		
		#Set DataFileCount if not specified. If specified, check against best practices. 
		if (-not $datafilecount)
		{
			$datafilecount = $cores
			Write-Verbose "Data file count set to number of cores: $datafilecount"
		}
		else
		{
			if ($datafilecount -gt $cores)
			{
				Write-Warning "Data File Count of $datafilecount exceeds the Logical Core Count of $cores. This is outside of best practices."
			}
			Write-Verbose "Data file count set explicitly: $datafilecount"
		}
		
		$dataFilesizeSingleMB = $([Math]::Floor($datafilesizemb/$datafilecount))
		Write-Verbose "Single data file size (MB): $dataFilesizeSingleMB"
		
		if ($datapath)
		{
			if ((Test-SqlPath -SqlServer $server -Path $datapath) -eq $false)
			{
				throw "$datapath is an invalid path."
			}
		}
		else
		{
			$filepath = $server.Databases['tempdb'].ExecuteWithResults('SELECT physical_name as FileName FROM sys.database_files WHERE file_id = 1').Tables[0].FileName
			$datapath = Split-Path $filepath
		}
		
		Write-Verbose "Using data path: $datapath"
		
		if ($logpath)
		{
			if ((Test-SqlPath -SqlServer $server -Path $logpath) -eq $false)
			{
				throw "$logpath is an invalid path."
			}
		}
		else
		{
			$filepath = $server.Databases['tempdb'].ExecuteWithResults('SELECT physical_name as FileName FROM sys.database_files WHERE file_id = 2').Tables[0].FileName
			$logpath = Split-Path $filepath
		}
		Write-Verbose "Using log path: $logpath"
		
		$LogSizeMBActual = if (-not $LogFileSizeMB) { $([Math]::Floor($datafilesizemb/4)) }
		
		$config = [PSCustomObject]@{
			SqlServer = $server.Name
			DataFileCount = $datafilecount
			DataFileSizeMB = $datafilesizemb
			SingleDataFileSizeMB = $dataFilesizeSingleMB
			LogSizeMB = $LogSizeMBActual
			DataPath = $datapath
			LogPath = $logpath
		}
		
		# Check current tempdb. Throw an error if current tempdb is 'larger' than config.
		$currentfilecount = $server.Databases['tempdb'].ExecuteWithResults('SELECT count(1) as FileCount FROM sys.database_files WHERE type=0').Tables[0].FileCount
		$toobigcount = $server.Databases['tempdb'].ExecuteWithResults("SELECT count(1) as FileCount FROM sys.database_files WHERE size/128 > $dataFilesizeSingleMB AND type = 0").Tables[0].FileCount
		
		if ($currentfilecount -gt $datafilecount)
		{
			throw "Current tempdb not suitable to be reconfigured. The current tempdb has a greater number of files than the calculated configuration."
		}
		
		if ($toobigcount -gt 0)
		{
			throw "Current tempdb not suitable to be reconfigured. The current tempdb is larger than the calculated configuration."
		}
		
		$equalcount = $server.Databases['tempdb'].ExecuteWithResults("SELECT count(1) as FileCount FROM sys.database_files WHERE size/128 = $dataFilesizeSingleMB AND type = 0").Tables[0].FileCount
		
		if ($equalcount -gt 0)
		{
			throw "Current tempdb not suitable to be reconfigured. The current tempdb is the same size as the specified DataFileSizeMB."
		}
		
		Write-Verbose "tempdb configuration validated."
		
		$datafiles = $server.Databases['tempdb'].ExecuteWithResults("select f.Name, f.physical_name as FileName from sys.filegroups fg join sys.database_files f on fg.data_space_id = fg.data_space_id where fg.name = 'PRIMARY' and f.type_desc = 'ROWS'").Tables[0]
		
		#Checks passed, process reconfiguration
		for ($i = 0; $i -lt $datafilecount; $i++)
		{
			$file = $datafiles.Rows[$i]
			if ($file)
			{
				$filename = Split-Path $file.FileName -Leaf
				$logicalname = $file.Name
				$newpath = "$datapath\$filename"
				$sql += "ALTER DATABASE tempdb MODIFY FILE(name=$logicalname,filename='$newpath',size=$dataFilesizeSingleMB MB,filegrowth=512MB);"
			}
			else
			{
				$newname = "tempdev$i.ndf"
				$newpath = "$datapath\$newname"
				$sql += "ALTER DATABASE tempdb ADD FILE(name=tempdev$i,filename='$newpath',size=$dataFilesizeSingleMB MB,filegrowth=512MB);"
			}
		}
		
		if (-not $LogFileSizeMB)
		{
			$LogFileSizeMB = [Math]::Floor($datafilesizemb/4)
		}
		
		$logfile = $server.Databases['tempdb'].ExecuteWithResults("SELECT name, physical_name as FileName FROM sys.database_files WHERE file_id = 2").Tables[0]
		$filename = Split-Path $logfile.FileName -Leaf
		$logicalname = $logfile.Name
		$newpath = "$logpath\$filename"
		$sql += "ALTER DATABASE tempdb MODIFY FILE(name=$logicalname,filename='$newpath',size=$LogFileSizeMB MB,filegrowth=512MB);"
		
		Write-Verbose "SQL Statement to resize tempdb"
		Write-Verbose ($sql -join "`n`n")
		
		if ($Script)
		{
			return $sql
		}
		elseif ($OutFile)
		{
			$sql | Set-Content -Path $OutFile
		}
		else
		{
			If ($Pscmdlet.ShouldProcess($SqlServer, "Executing $sql and informing that a restart is required."))
			{
				try
				{
					$server.Databases['master'].ExecuteNonQuery($sql)
					Write-Verbose "tempdb successfully reconfigured"
					Write-Warning "tempdb reconfigured. You must restart the SQL Service for settings to take effect."
				}
				catch
				{
					# write-exception writes the full exception to file
					Write-Exception $_
					throw "Unable to reconfigure tempdb"
				}
			}
		}
	}
	
	END
	{
		$server.ConnectionContext.Disconnect()
	}
}