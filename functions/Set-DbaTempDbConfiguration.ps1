function Set-DbaTempDbConfiguration {
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
so that it is "smaller" than what the function will size it to before running the function.

.NOTES 
Original Author: Michael Fal (@Mike_Fal), http://mikefal.net

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

.PARAMETER SqlInstance
SQLServer name or SMO object representing the SQL Server to connect to

.PARAMETER SqlCredential
PSCredential object to connect under. If not specified, current Windows login will be used.

.PARAMETER DataFileCount
Integer of number of datafiles to create. If not specified, function will use logical cores of host.

.PARAMETER DataFileSizeMB
Total data file size in megabytes

.PARAMETER LogFileSizeMB
Log file size in megabytes. If not specified, function will use 25% of total data file size.

.PARAMETER DataFileGrowthMB
Growth size for the data file(s) in megabytes. The default is 512 MB.

.PARAMETER LogFileGrowthMB
Growth size for the log file in megabytes. The default is 512 MB.

.PARAMETER DataPath 
File path to create tempdb data files in. If not specified, current tempdb location will be used.

.PARAMETER LogPath
File path to create tempdb log file in. If not specified, current tempdb location will be used.

.PARAMETER OutputScriptOnly
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
If false, it will print a warning if in warning mode. It will also be willing to write a message to the screen, if the level is within the range configured for that.

.LINK
https://dbatools.io/Set-DbaTempDbConfiguration

.EXAMPLE
Set-DbaTempDbConfiguration -SqlInstance localhost -DataFileSizeMB 1000

Creates tempdb with a number of datafiles equal to the logical cores where
each one is equal to 1000MB divided by number of logical cores and a log file
of 250MB

.EXAMPLE
Set-DbaTempDbConfiguration -SqlInstance localhost -DataFileSizeMB 1000 -DataFileCount 8

Creates tempdb with a number of datafiles equal to the logical cores where
each one is equal to 125MB and a log file of 250MB

.EXAMPLE
Set-DbaTempDbConfiguration -SqlInstance localhost -DataFileSizeMB 1000 -OutputScriptOnly

Provides a SQL script output to configure tempdb according to the passed parameters

.EXAMPLE
Set-DbaTempDbConfiguration -SqlInstance localhost -DataFileSizeMB 1000 -DisableGrowth

Disables the growth for the data and log files

.EXAMPLE
Set-DbaTempDbConfiguration -SqlInstance localhost -DataFileSizeMB 1000 -OutputScriptOnly

Returns PSObject representing tempdb configuration.
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter]$SqlInstance,
		[PSCredential]$SqlCredential,
		[int]$DataFileCount,
		[Parameter(Mandatory = $true)]
		[int]$DataFileSizeMB,
		[int]$LogFileSizeMB,
		[int]$DataFileGrowthMB = 512,
		[int]$LogFileGrowthMB = 512,
		[string]$DataPath,
		[string]$LogPath,
		[string]$OutFile,
		[switch]$OutputScriptOnly,
		[switch]$DisableGrowth,
		[switch]$Silent
	)
	begin {
		$sql = @()
		Write-Message -Level Verbose -Message "Connecting to $SqlInstance"
		$server = Connect-SqlInstance $sqlinstance -SqlCredential $SqlCredential
		
		if ($server.VersionMajor -lt 9) {
			Stop-Function -Message "SQL Server 2000 is not supported"
			return
		}
	}
	
	process {
		
		if (Test-FunctionInterrupt) { return }
		
		$cores = $server.Processors
		if ($cores -gt 8) { $cores = 8 }
		
		#Set DataFileCount if not specified. If specified, check against best practices. 
		if (-not $DataFileCount) {
			$DataFileCount = $cores
			Write-Message -Message "Data file count set to number of cores: $DataFileCount" -Level Verbose
		}
		else {
			if ($DataFileCount -gt $cores) {
				Write-Message -Message "Data File Count of $DataFileCount exceeds the Logical Core Count of $cores. This is outside of best practices." -Level Warning
			}
			Write-Message -Message "Data file count set explicitly: $DataFileCount" -Level Verbose
		}
		
		$DataFilesizeSingleMB = $([Math]::Floor($DataFileSizeMB/$DataFileCount))
		Write-Message -Message "Single data file size (MB): $DataFilesizeSingleMB" -Level Verbose
		
		if ($DataPath) {
			if ((Test-DbaSqlPath -SqlInstance $server -Path $DataPath) -eq $false) {
				Stop-Function -Message "$datapath is an invalid path."
				return
			}
		}
		else {
			$Filepath = $server.Databases['tempdb'].ExecuteWithResults('SELECT physical_name as FileName FROM sys.database_files WHERE file_id = 1').Tables[0].Rows[0].FileName
			$DataPath = Split-Path $Filepath
		}
		
		Write-Message -Message "Using data path: $datapath" -Level Verbose
		
		if ($LogPath) {
			if ((Test-DbaSqlPath -SqlInstance $server -Path $LogPath) -eq $false) {
				Stop-Function -Message "$LogPath is an invalid path."
				return
			}
		}
		else {
			$Filepath = $server.Databases['tempdb'].ExecuteWithResults('SELECT physical_name as FileName FROM sys.database_files WHERE file_id = 2').Tables[0].Rows[0].FileName
			$LogPath = Split-Path $Filepath
		}
		Write-Message -Message "Using log path: $LogPath" -Level Verbose
		
		# Check if the file growth needs to be disabled
		if ($DisableGrowth) {
			$DataFileGrowthMB = 0
			$LogFileGrowthMB = 0
		}
		
		$LogSizeMBActual = if (-not $LogFileSizeMB) { $([Math]::Floor($DataFileSizeMB/4)) }

		# Check current tempdb. Throw an error if current tempdb is larger than config.
		$CurrentFileCount = $server.Databases['tempdb'].ExecuteWithResults('SELECT count(1) as FileCount FROM sys.database_files WHERE type=0').Tables[0].Rows[0].FileCount
		$TooBigCount = $server.Databases['tempdb'].ExecuteWithResults("SELECT TOP 1 (size/128) as Size FROM sys.database_files WHERE size/128 > $DataFilesizeSingleMB AND type = 0").Tables[0].Rows[0].Size
		
		if ($CurrentFileCount -gt $DataFileCount) {
			Stop-Function -Message "Current tempdb not suitable to be reconfigured. The current tempdb has a greater number of files ($CurrentFileCount) than the calculated configuration ($DataFileCount)."
			return
		}
		
		if ($TooBigCount) {
			Stop-Function -Message "Current tempdb not suitable to be reconfigured. The current tempdb ($TooBigCount MB) is larger than the calculated individual file configuration ($DataFilesizeSingleMB MB)."
			return
		}
		
		$EqualCount = $server.Databases['tempdb'].ExecuteWithResults("SELECT count(1) as FileCount FROM sys.database_files WHERE size/128 = $DataFilesizeSingleMB AND type = 0").Tables[0].Rows[0].FileCount
		
		if ($EqualCount -gt 0) {
			Stop-Function -Message "Current tempdb not suitable to be reconfigured. The current tempdb is the same size as the specified DataFileSizeMB."
			return
		}
		
		Write-Message -Message "tempdb configuration validated." -Level Verbose
		
		$DataFiles = $server.Databases['tempdb'].ExecuteWithResults("select f.name as Name, f.physical_name as FileName from sys.filegroups fg join sys.database_files f on fg.data_space_id = f.data_space_id where fg.name = 'PRIMARY' and f.type_desc = 'ROWS'").Tables[0];
		
		#Checks passed, process reconfiguration
		for ($i = 0; $i -lt $DataFileCount; $i++) {
			$File = $DataFiles.Rows[$i]
			if ($File) {
				$Filename = Split-Path $File.FileName -Leaf
				$LogicalName = $File.Name
				$NewPath = "$datapath\$Filename"
				$sql += "ALTER DATABASE tempdb MODIFY FILE(name=$LogicalName,filename='$NewPath',size=$DataFilesizeSingleMB MB,filegrowth=$DataFileGrowthMB);"
			}
			else {
				$NewName = "tempdev$i.ndf"
				$NewPath = "$datapath\$NewName"
				$sql += "ALTER DATABASE tempdb ADD FILE(name=tempdev$i,filename='$NewPath',size=$DataFilesizeSingleMB MB,filegrowth=$DataFileGrowthMB);"
			}
		}
		
		if (-not $LogFileSizeMB) {
			$LogFileSizeMB = [Math]::Floor($DataFileSizeMB/4)
		}
		
		$logfile = $server.Databases['tempdb'].ExecuteWithResults("SELECT name, physical_name as FileName FROM sys.database_files WHERE file_id = 2").Tables[0].Rows[0];
		$Filename = Split-Path $logfile.FileName -Leaf
		$LogicalName = $logfile.Name
		$NewPath = "$LogPath\$Filename"
		$sql += "ALTER DATABASE tempdb MODIFY FILE(name=$LogicalName,filename='$NewPath',size=$LogFileSizeMB MB,filegrowth=$LogFileGrowthMB);"
		
		Write-Message -Message "SQL Statement to resize tempdb" -Level Verbose
		Write-Message -Message ($sql -join "`n`n") -Level Verbose
		
		if ($OutputScriptOnly) {
			return $sql
		}
		elseif ($OutFile) {
			$sql | Set-Content -Path $OutFile
		}
		else {
			If ($Pscmdlet.ShouldProcess($SqlInstance, "Executing query and informing that a restart is required.")) {
				try {
					$server.Databases['master'].ExecuteNonQuery($sql)
					Write-Message -Level Verbose -Message "tempdb successfully reconfigured"
					
					[PSCustomObject]@{
						ComputerName = $server.NetName
						InstanceName = $server.ServiceName
						SqlInstance = $server.DomainInstanceName
						DataFileCount = $DataFileCount
						DataFileSizeMB = $DataFileSizeMB
						SingleDataFileSizeMB = $DataFilesizeSingleMB
						LogSizeMB = $LogSizeMBActual
						DataPath = $DataPath
						LogPath = $LogPath
						DataFileGrowthMB = $DataFileGrowthMB
						LogFileGrowthMB = $LogFileGrowthMB
					}
					
					Write-Message -Level Output -Message "tempdb reconfigured. You must restart the SQL Service for settings to take effect"
				}
				catch {
					# write-exception writes the full exception to file
					Stop-Function -Message "Unable to reconfigure tempdb. Exception: $_" -Target $sql -InnerErrorRecord $_
					return
				}
			}
		}
	}
	end { 
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Set-SqlTempDbConfiguration
	}
	}
