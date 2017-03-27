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

.PARAMETER DataFileGrowthMB
Growth size for the data file(s) in megabytes. The default is 512 MB.

.PARAMETER LogFileGrowthMB
Growth size for the log file in megabytes. The default is 512 MB.

.PARAMETER DataPath 
File path to create tempdb data files in. If not specified, current tempdb location will be used.

.PARAMETER LogPath
File path to create tempdb log file in. If not specified, current tempdb location will be used.

.PARAMETER Script
Switch to generate script for tempdb configuration.

.PARAMETER OutFile
Path to file to save the generated script for tempdb configuration

.PARAMETER DisableGrowth
Switch to disable the tempdb files to grow. 
Overrules the parameters DataFileGrowthMB and LogFileGrowthMB.

.PARAMETER WhatIf
Switch to generate configuration object.

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 

.PARAMETER Silent
Whether the silent switch was set in the calling function.
If true, it will write errors, if any, but not write to the screen without explicit override using -Debug or -Verbose.
If false, it will print a warning if in wrning mode. It will also be willing to write a message to the screen, if the level is within the range configured for that.

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
Set-SqltempdbConfiguration -SqlServer localhost -DataFileSizeMB 1000 -DisableGrowth

Disables the growth for the data and log files

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
		[int]$DataFileSizeMB,
		[int]$LogFileSizeMB,
		[int]$DataFileGrowthMB = 512,
		[int]$LogFileGrowthMB = 512,
		[string]$DataPath,
		[string]$LogPath,
		[string]$OutFile,
		[switch]$Script,
		[switch]$DisableGrowth,
		[switch]$Silent
	)
	BEGIN
	{
		$Sql = @()
		Write-Message -Message "Connecting to $($SqlServer)" -Level 5 -Silent $Silent
		$server = Connect-SqlServer $SqlServer -SqlCredential $SqlCredential
		
		if ($server.VersionMajor -lt 9)
		{
			Stop-Function -Message "SQL Server 2000 is not supported" -Silent $Silent 
		}
	}
	
	PROCESS
	{
		$cores = $server.Processors
		if ($cores -gt 8) { $cores = 8 }
		
		#Set DataFileCount if not specified. If specified, check against best practices. 
		if (-not $DataFileCount)
		{
			$DataFileCount = $cores
			Write-Message -Message "Data file count set to number of cores: $($DataFileCount)"  -Level 5 -Silent $Silent
		}
		else
		{
			if ($DataFileCount -gt $cores)
			{
				Write-Message -Message "Data File Count of $($DataFileCount) exceeds the Logical Core Count of $($cores). This is outside of best practices." -Warning -Silent $Silent 
			}
			Write-Message -Message "Data file count set explicitly: $($DataFileCount)"  -Level 5 -Silent $Silent
		}
		
		$DataFilesizeSingleMB = $([Math]::Floor($DataFileSizeMB/$DataFileCount))
		Write-Message -Message "Single data file size (MB): $($DataFilesizeSingleMB)"  -Level 5 -Silent $Silent
		
		if ($DataPath)
		{
			if ((Test-SqlPath -SqlServer $server -Path $DataPath) -eq $false)
			{
				Stop-Function -Message "$($DataPath) is an invalid path." -Silent $Silent 
			}
		}
		else
		{
			$Filepath = $server.Databases['tempdb'].ExecuteWithResults('SELECT physical_name as FileName FROM sys.database_files WHERE file_id = 1').Tables[0].FileName
			$DataPath = Split-Path $Filepath
		}
		
		Write-Message -Message "Using data path: $($DataPath)"  -Level 5 -Silent $Silent
		
		if ($LogPath)
		{
			if ((Test-SqlPath -SqlServer $server -Path $LogPath) -eq $false)
			{
				Stop-Function -Message "$($LogPath) is an invalid path." -Silent $Silent 
			}
		}
		else
		{
			$Filepath = $server.Databases['tempdb'].ExecuteWithResults('SELECT physical_name as FileName FROM sys.database_files WHERE file_id = 2').Tables[0].FileName
			$LogPath = Split-Path $Filepath
		}
		Write-Message -Message "Using log path: $($LogPath)"  -Level 5 -Silent $Silent
		
		# Check if the file growth needs to be disabled
		if($DisableGrowth)
		{
			$DataFileGrowthMB = 0
			$LogFileGrowthMB = 0
		}

		$LogSizeMBActual = if (-not $LogFileSizeMB) { $([Math]::Floor($DataFileSizeMB/4)) }
		
		$config = [PSCustomObject]@{
			SqlServer = $server.Name
			DataFileCount = $DataFileCount
			DataFileSizeMB = $DataFileSizeMB
			SingleDataFileSizeMB = $DataFilesizeSingleMB
			LogSizeMB = $LogSizeMBActual
			DataPath = $DataPath
			LogPath = $LogPath
			DataFileGrowthMB = $DataFileGrowthMB
			LogFileGrowthMB = $LogFileGrowthMB
		}
		
		# Check current tempdb. Throw an error if current tempdb is 'larger' than config.
		$CurrentFileCount = $server.Databases['tempdb'].ExecuteWithResults('SELECT count(1) as FileCount FROM sys.database_files WHERE type=0').Tables[0].FileCount
		$TooBigCount = $server.Databases['tempdb'].ExecuteWithResults("SELECT count(1) as FileCount FROM sys.database_files WHERE size/128 > $($DataFilesizeSingleMB) AND type = 0").Tables[0].FileCount
		
		if ($CurrentFileCount -gt $DataFileCount)
		{
			Stop-Function -Message "Current tempdb not suitable to be reconfigured. The current tempdb has a greater number of files than the calculated configuration." -Silent $Silent
		}
		
		if ($TooBigCount -gt 0)
		{
			Stop-Function -Message "Current tempdb not suitable to be reconfigured. The current tempdb is larger than the calculated configuration." -Silent $Silent
		}
		
		$EqualCount = $server.Databases['tempdb'].ExecuteWithResults("SELECT count(1) as FileCount FROM sys.database_files WHERE size/128 = $($DataFilesizeSingleMB) AND type = 0").Tables[0].FileCount
		
		if ($EqualCount -gt 0)
		{
			Stop-Function -Message "Current tempdb not suitable to be reconfigured. The current tempdb is the same size as the specified DataFileSizeMB." -Silent $Silent
		}
		
		Write-Message -Message "tempdb configuration validated."  -Level 5 -Silent $Silent
		
		$DataFiles = $server.Databases['tempdb'].ExecuteWithResults("select f.Name, f.physical_name as FileName from sys.filegroups fg join sys.database_files f on fg.data_space_id = fg.data_space_id where fg.name = 'PRIMARY' and f.type_desc = 'ROWS'").Tables[0]
		
		#Checks passed, process reconfiguration
		for ($i = 0; $i -lt $DataFileCount; $i++)
		{
			$File = $DataFiles.Rows[$i]
			if ($File)
			{
				$Filename = Split-Path $File.FileName -Leaf
				$LogicalName = $File.Name
				$NewPath = "$($DataPath)\$($Filename)"
				$Sql += "ALTER DATABASE tempdb MODIFY FILE(name=$($LogicalName),filename='$($NewPath)',size=$($DataFilesizeSingleMB) MB,filegrowth=$($DataFileGrowthMB));"
			}
			else
			{
				$NewName = "tempdev$($i).ndf"
				$NewPath = "$($DataPath)\$($NewName)"
				$Sql += "ALTER DATABASE tempdb ADD FILE(name=tempdev$($i),filename='$($NewPath)',size=$($DataFilesizeSingleMB) MB,filegrowth=$($DataFileGrowthMB));"
			}
		}
		
		if (-not $LogFileSizeMB)
		{
			$LogFileSizeMB = [Math]::Floor($DataFileSizeMB/4)
		}
		
		$logfile = $server.Databases['tempdb'].ExecuteWithResults("SELECT name, physical_name as FileName FROM sys.database_files WHERE file_id = 2").Tables[0]
		$Filename = Split-Path $logfile.FileName -Leaf
		$LogicalName = $logfile.Name
		$NewPath = "$LogPath\$Filename"
		$Sql += "ALTER DATABASE tempdb MODIFY FILE(name=$($LogicalName),filename='$($NewPath)',size=$($LogFileSizeMB) MB,filegrowth=$($LogFileGrowthMB));"
		
		Write-Message -Message "SQL Statement to resize tempdb" -Level 5 -Silent $Silent
		Write-Message -Message ($Sql -join "`n`n") -Level 5 -Silent $Silent
		
		if ($Script)
		{
			return $Sql
		}
		elseif ($OutFile)
		{
			$Sql | Set-Content -Path $OutFile
		}
		else
		{
			If ($Pscmdlet.ShouldProcess($SqlServer, "Executing $($Sql) and informing that a restart is required."))
			{
				try
				{
					$server.Databases['master'].ExecuteNonQuery($Sql)
					Write-Message -Message "tempdb successfully reconfigured"  -Level 5 -Silent $Silent
					Write-Message -Message "tempdb reconfigured. You must restart the SQL Service for settings to take effect." -Warning -Silent $Silent 
				}
				catch
				{
					# write-exception writes the full exception to file
					Stop-Function -Message "Unable to reconfigure tempdb. $($_)" -Silent $Silent
				}
			}
		}
	}
	
	END
	{
		$server.ConnectionContext.Disconnect()
	}
}
