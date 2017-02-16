Function Backup-DbaDatabase
{
<#
.SYNOPSIS
Backup one or more SQL Sever databases from a SQL Server SqlInstance

.DESCRIPTION
Performs a backup of a specified type of 1 or more databases on a SQL Server Instance.
These backups may be Full, Differential or Transaction log backups

.PARAMETER SqlInstance
The SQL Server instance hosting the databases to be backed up

.PARAMETER SqlCredential
Credentials to connect to the SQL Server instance if the calling user doesn't have permission

.PARAMETER Databases
Names of the databases to be backed up. This is auto-populated from the server.

.PARAMETER BackupFileName
name of the file to backup to. This is only accepted for single database backups
If no name is specified then the backup files will be named DatabaseName_yyyyMMddHHmm (ie; Database1_201714022131)
with the appropriate extension.

If the same name is used repeatedly, SQL Server will add backups to the same file at an incrementing position

Sql Server needs permissions to write to the location. Path names are based on the Sql Server (c:\ is the c drive on the SQL Server, not the machine running the script)

.PARAMETER BackupDirectory
Path to place the backup files. If not specified the backups will be placed in the default backup location for SQLInstance
If multiple paths are specified, the backups will be stiped across these locations. This will overwrite the FileCount option

If path does not exist Sql Server will attmept to create it. Folders are created by the Sql Instance, and checks will be made for write permissions

File Names with be suffixed with x-of-y to enable identifying striped sets, where y is the number of files in the set and x is from 1 to you

.PARAMETER NoCopyOnly
By default function performs a Copy Only backup. These backups do not intefere with the restore chain of the database, so are safe to take.
This switch indicates that you wish to take normal backups. Be aware that these WILL break your restore chains, so use at your own risk

For more details please refer to this MSDN article - https://msdn.microsoft.com/en-us/library/ms191495.aspx 

.PARAMETER Type
The type of SQL Server backup to perform.
Accepted values are Full, Log, Differential, Diff, Database

.PARAMETER FileCount
THis is the number of striped copies of the backups you wish to create
This value is overwritten if you specify multiple Backup Directories

.PARAMETER DatabaseCollection
Internal parameter

.NOTES
Tags: DisasterRecovery, Backup, Restore
Original Author: Stuart Moore (@napalmgram), stuart-moore.com

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.EXAMPLE 
Backup-DbaDatabase -SqlInstance Server1 -Databases HR, Finance

This will perform a full database backup on the databases HR and Finance on SQL Server Instance Server1 to Server1's 
default backup directory 
	
.EXAMPLE
Backup-DbaDatabase -SqlInstance sql2016 -BackupDirectory C:\temp -Databases AdventureWorks2014 -Type Full

Backs up AdventureWorks2014 to sql2016's C:\temp folder 
#>
	[CmdletBinding(DefaultParameterSetName = "Default")]
	param (
		[parameter(ParameterSetName = "NoPipe", Mandatory = $true)]
		[object[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[string[]]$BackupDirectory,
		[string]$BackupFileName,
		[switch]$NoCopyOnly,
		[ValidateSet('Full', 'Log', 'Differential', 'Diff', 'Database')]
		[string]$Type = "Database",
		[parameter(ParameterSetName = "Pipe", Mandatory = $true, ValueFromPipeline = $true)]
		[object[]]$DatabaseCollection,
		[switch]$CreateFolder,
		[int]$FileCount=0

		
	)
	DynamicParam { if ($SqlInstance) { return Get-ParamSqlDatabases -SqlServer $SqlInstance[0] -SqlCredential $SqlCredential } }
	
	BEGIN
	{
		$FunctionName = $FunctionName = (Get-PSCallstack)[0].Command
				
		if ($SqlInstance.length -ne 0)
		{
			$databases = $psboundparameters.Databases
			Write-Verbose "Connecting to $SqlInstance"
			try
			{
				$Server = Connect-SqlServer -SqlServer $SqlInstance -SqlCredential $SqlCredential
			}
			catch
			{
				Write-Warning "$FunctionName - Cannot connect to $SqlInstance"
				continue
			}
			
			$DatabaseCollection = $server.Databases | Where-Object { $_.Name -in $databases }
			
			if ($BackupDirectory.count -gt 1)
			{
				Write-Verbose "$FunctionName - Multiple Backup Directories, striping"
				$Filecount = $BackupDirectory.count
			}
			
			if ($DatabaseCollection.count -gt 1 -and $BackupFileName -ne '')
			{
				Write-Warning "$FunctionName - 1 BackupFile specified, but more than 1 database." -WarningAction stop
				break
			}
		}
	}
	
	PROCESS
	{		
		if (!$SqlInstance -and !$DatabaseCollection)
		{
			Write-Warning "You must specify a server and database or pipe some databases"
			continue
		}
		
		Write-Verbose "$FunctionName - $($DatabaseCollection.count) database to backup"
		
		ForEach ($Database in $databasecollection)
		{
			if ($server -eq $null) { $server = $Database.Parent }
			
			$FailReasons = @()
			
			Write-Verbose "$FunctionName - Backup up database $database"
			
			if ($Database.RecoveryModel -eq $null)
			{
				$Database.RecoveryModel = $server.databases[$Database.Name].RecoveryModel
				Write-Verbose "$($DataBase.Name) is in $($Database.RecoveryModel) recovery model"
			}
			
			if ($Database.RecoveryModel -eq 'Simple' -and $Type -eq 'Log')
			{
				$FailReason = "$($Database.Name) is in simple recovery mode, cannot take log backup"
				$FailReasons += $FailReason
				Write-Warning "$FunctionName - $FailReason"
				
			}
			
			$lastfull = $database.LastBackupDate.Year
		
			if ($Type -ne "Full" -and $lastfull -eq 1)
			{
				$FailReason = "$($Database.Name) does not have an existing full backup, cannot take log or differentialbackup"
				$FailReasons += $FailReason
				Write-Warning "$FunctionName - $FailReason"
			}
			
			$val = 0
			$copyonly = !$NoCopyOnly
			
			$server.ConnectionContext.StatementTimeout = 0
			$backup = New-Object Microsoft.SqlServer.Management.Smo.Backup
			$backup.Database = $Database.Name
			$Suffix = "bak"
			
			if ($type -in 'diff', 'differential')
			{
				Write-Verbose "Creating differential backup"
				$type = "Database"
				$backup.Incremental = $true
			}
			
			if ($Type -eq "Log")
			{
				Write-Verbose "$FunctionName - Creating log backup"
				$Suffix = "trn"
			}
			
			if ($type -eq 'Full')
			{
				$type = "Database"
			}
			
			$backup.CopyOnly = $copyonly
			$backup.Action = $type
			
			Write-Verbose "$FunctionName - Sorting Paths"
			
			#If a backupfilename has made it this far, use it
			$FinalBackupPath = @()
			
			if ($BackupFileName -ne '')
			{
				if ($BackupFileName -notlike "*:*")
				{
					if (!$BackupDirectory)
					{
						$BackupDirectory = $server.BackupDirectory
					}
					$BackupFileName = "$BackupDirectory\$BackupFileName.$Suffix"
				}
				
				Write-Verbose "$FunctionName - Single db and filename"
				if (Test-SqlPath -SqlServer $server -Path (Split-Path $BackupFileName))
				{
					$FinalBackupPath += $BackupFileName
				}
				else
				{
					$FailReason = "Sql Server cannot write to the location $(Split-Path $BackupFileName)"
					$FailReasons += $FailReason
					Write-Warning "$FunctionName - $FailReason"
				}
			}
			else
			{
				if (!$BackupDirectory)
				{
					$BackupDirectory += $server.BackupDirectory
				}

				if ($BackupFileName -eq '')	
				{			
					$TimeStamp = (Get-date -Format yyyyMMddHHmm)
					$BackupFileName = "$($Database.Name)_$TimeStamp"
				}
				Foreach ($path in $BackupDirectory)
				{
					if ($CreateFolder)
					{
						$Path = $path + "\" + $Database.name
						Write-Verbose "$FunctionName - Creating Folder $Path"	
						if ((New-DbaSqlDirectory -SqlServer:$SqlInstance -SqlCredential:$SqlCredential -Path $path).created -eq $false)
						{
							$FailReason = "Cannot create or write to folder $path"
							$FailReasons += $FailReason
							Write-Warning "$FunctionName - $FailReason"
						}
						else {
							$FinaLBackupPath += "$path\$BackupFileName.$suffix"
						}
					}
					else
					{
						if ((New-DbaSqlDirectory -SqlServer:$SqlInstance -SqlCredential:$SqlCredential -Path $path).created -eq $false)
						{
							$FailReason = "Cannot create or write to folder $path"
							$FailReasons += $FailReason
							Write-Warning "$FunctionName - $FailReason"
						}
						$FinalBackupPath += "$path\$BackupFileName.$suffix"
					}
				}
			}
			
			if ($FileCount -gt 1 -and $FinalBackupPath.count -eq 1)
			{
				Write-Verbose "$FunctionName - Striping for Filecount of $filecount"
				$stripes = $filecount
				for ($i= 2; $i -lt $stripes+1; $i++)
				{
					$FinalBackupPath += $FinalBackupPath[0].Replace(".$suffix", "-$i-of-$stripes.$suffix")
				}
				$FinalBackupPath[0] = $FinalBackupPath[0].Replace(".$suffix", "-1-of-$stripes.$suffix")
			
			}
			elseif ($FinalBackupPath.count -gt 1)
			{
				Write-Verbose "$FunctionName - String for Backup path count of $($FinalBackupPath.count)"
				$stripes = $FinalbackupPath.count
				for ($i= 1; $i -lt $stripes+1; $i++)
				{
					$FinalBackupPath[($i-1)] = $FinalBackupPath[($i-1)].Replace(".$suffix", "-$i-of-$stripes.$suffix")
				}
			}
			Write-Verbose "before failreasons"
			$script = ''
			$backupComplete = $false
			if ($FailReasons.count -eq 0)
			{
				$filecount = $FinalBackupPath.count
				foreach ($backupfile in $FinalBackupPath)
				{
					$device = New-Object Microsoft.SqlServer.Management.Smo.BackupDeviceItem
					$device.DeviceType = "File"
					$device.Name = $backupfile
					$backup.Devices.Add($device)
				}

				
				Write-Verbose "$FunctionName - Devices added"
				$percent = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] {
					Write-Progress -id 1 -activity "Backing up database $($Database.Name)  to $backupfile" -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent))
				}
				$backup.add_PercentComplete($percent)
				$backup.PercentCompleteNotification = 1
				$backup.add_Complete($complete)
				
				Write-Progress -id 1 -activity "Backing up database $($Database.Name)  to $backupfile" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
				
				try
				{
					$backup.SqlBackup($server)
					$script = $backup.Script($server)
					Write-Progress -id 1 -activity "Backing up database $($Database.Name)  to $backupfile" -status "Complete" -Completed
					$BackupComplete = $true
				}
				catch
				{
					Write-Progress -id 1 -activity "Backup" -status "Failed" -completed
					Write-Exception $_
					$BackupComplete = $false
				}
			}
			[PSCustomObject]@{
					SqlInstance = $server.name
					DatabaseName = $($Database.Name)
					BackupComplete = $BackupComplete
					BackupFilesCount = $FinalBackupPath.count	
					BackupFile = (split-path $FinalBackupPath -leaf)
					BackupFolder = (split-path $FinalBackupPath | Sort-Object -Unique)
					BackupPath = ($FinalBackupPath | Sort-Object -Unique)
					Script = $script
					Notes = $FailReasons -join (',')	
				}
				$failreasones =@()
			
			
		}
	}
}
