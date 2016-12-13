Function Test-DbaBackup
{
<#
.SYNOPSIS
Safely removes a SQL Database and creates an Agent Job to restore it

.DESCRIPTION
Performs a DBCC CHECKDB on the database, backs up the database with Checksum and verify only to a Final Backup location, creates an Agent Job to restore from that backup, Drops the database, runs the agent job to restore the database,
performs a DBCC CHECKDB and drops the database

By default the initial DBCC CHECKDB is performed
By default the jobs and databases are created on the same server. Use -Destination to use a seperate server

It will start the SQL Agent Service on the Destination Server if it is not running

.PARAMETER SqlServer
The SQL Server instance holding the databases to be removed.You must have sysadmin access and server version must be SQL Server version 2000 or higher.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted.

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 

Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

.PARAMETER Destination
Hello

.PARAMETER Path
Hello

.PARAMETER BackupsDirectory
Hello

.PARAMETER DataDirectory
Hello

.PARAMETER LogDirectory
Hello

.PARAMETER VerifyOnly
Hello

.PARAMETER NoDbccCheck
Hello

.PARAMETER NoSuspectPageCheck
Hello

.PARAMETER NoDrop
Hello

.PARAMETER MaxMB
Hello
	
.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Test-DbaBackup

.EXAMPLE 
Test-DbaBackup -SqlServer 'Fade2Black' -Databases RideTheLightning -BackupFolder 'C:\MSSQL\Backup\Rationalised - DO NOT DELETE'

For the database RideTheLightning on the server Fade2Black Will perform a DBCC CHECKDB and if there are no errors 
backup the database to the folder C:\MSSQL\Backup\Rationalised - DO NOT DELETE. It will then create an Agent Job to restore the database 
from that backup. It will drop the database, run the agent job to restore it, perform a DBCC ChECK DB and then drop the database.

Any DBCC errors will be written to your documents folder


#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance", "Source")]
		[object]$SqlServer,
		[object]$SqlCredential,
		[object]$Destination = $SqlServer,
		[string]$Path,
		[string]$BackupsDirectory,
		[string]$DataDirectory,
		[string]$LogDirectory,
		[switch]$VerifyOnly,
		[switch]$NoDbccCheck,
		[switch]$NoSuspectPageCheck,
		[switch]$NoDrop,
		[int]$MaxMB
		
	)
	
	DynamicParam { if ($sqlserver) { return Get-ParamSqlDatabases -SqlServer $sqlserver -SqlCredential $SqlCredential } }
	
	BEGIN
	{
		#ReadSuspectPageTable(Server)
		
		Function Set-SqlServer
		{
			if ($SqlServer -ne $Destination)
			{
				$destserver = Connect-SqlServer -SqlServer $destination -SqlCredential $sqlCredential
				
				$sourcerealname = $sourceserver.DomainInstanceName
				$destrealname = $sourceserver.DomainInstanceName
				
				if ($BackupFolder)
				{
					if ($BackupFolder.StartsWith("\\") -eq $false -and $sourcerealname -ne $destrealname)
					{
						throw "Backup folder must be a network share if the source and destination servers are not the same."
					}
				}
			}
			else
			{
				$destserver = $sourceserver
			}
			
		}
		
		Function Set-Directory
		{
			if ($datadirectory)
			{
				if (!(Test-SqlPath -SqlServer $destserver -Path $datadirectory))
				{
					Write-Warning "Can't access $datadirectory Please check if $serviceaccount has permissions"
					continue
				}
			}
			else
			{
				$datadirectory = Get-SqlDefaultPaths -SqlServer $destserver -FileType mdf
			}
			
			if ($logdirectory)
			{
				if (!(Test-SqlPath -SqlServer $destserver -Path $logdirectory))
				{
					Write-Warning "Can't access $logdirectory Please check if $serviceaccount has permissions"
					continue
				}
			}
			else
			{
				$logdirectory = Get-SqlDefaultPaths -SqlServer $destserver -FileType ldf
			}
		}
		
		Function Build-FileList
		{
			$filelist = $restorelist.Filelist
			$dbname = $ogdbname = $restorelist.DatabaseName
			$temprestoreinfo = @()
			
			foreach ($file in $filelist)
			{
				if ($file.Type -eq 'L')
				{
					$dir = $logdirectory
				}
				else
				{
					$dir = $datadirectory
				}
				
				$fn = Split-Path $file.PhysicalName -Leaf
				$temprestoreinfo += [pscustomobject]@{
					Logical = $file.LogicalName
					Physical = "$dir\dbatools-testrestore-$fn"
				}
			}
		}
		
		Function Drop-Database
		{
			if ($Pscmdlet.ShouldProcess($dbname, "Dropping Database $dbname on $destination"))
			{
				try
				{
					$removeresult = Remove-SqlDatabase -SqlServer $destserver -DbName $dbname
					Write-Verbose "Dropped $dbname Database on $destination"
				}
				catch
				{
					Write-Warning "Failed to Drop database $dbname on $destination"
					Write-Exception $_
					continue
				}
			}
		}
		
		Function Check-Database
		{
			if ($Pscmdlet.ShouldProcess($dbname, "Running Dbcc CHECKDB on $dbname on $destination"))
			{
				if ($ogdbname -eq "master")
				{
					$dbccresult = "DBCC CHECKTABLE skipped for restored master ($dbname) database"
				}
				else
				{
					$dbccresult = Start-DbccCheck -Server $destserver -DbName $dbname -Table 3>$null
				}
			}
		}
		
		Function Start-Testing
		{
			param (
				[string]$Path,
				[string]$DbName
			)
			
			if ($Path -eq $null)
			{
				$Path = Get-DbaBackupHistory -SqlServer $sourceserver -Databases $dbname -LastFull
			}
			
			if ($Path -eq $null)
			{
				$Path = "Not found"
				$fileexists = $false
				$restoreresult = "Skipped"
				$dbccresult = "Skipped"
			}
			elseif ($source -ne $destination -and $Path.StartsWith('\\') -eq $false)
			{
				$fileexists = "Skipped"
				$restoreresult = "Restore not located on shared location"
				$dbccresult = "Skipped"
			}
			elseif ((Test-SqlPath -SqlServer $destserver -Path $path) -eq $false)
			{
				$fileexists = $false
				$restoreresult = "Skipped"
				$dbccresult = "Skipped"
			}
			else
			{
				$fileexists = $true
				$restorelist = Read-DbaBackupHeader -SqlServer $destserver -Path $Path
				$mb = $restorelist.BackupSizeMB
				
				if ($MaxMB -gt 0 -and $MaxMB -lt $mb)
				{
					$restoreresult = "The backup size for $dbname ($mb MB) exceeds the specified maximum size ($MaxMB MB)"
					$dbccresult = "Skipped"
				}
				else
				{
					$filestructure = Build-FileList
					$dbname = "dbatools-testrestore-$dbname"
					
					if ($Pscmdlet.ShouldProcess($destination, "Restoring $ogdbname as $dbname"))
					{
						$restoreresult = Restore-Database -SqlServer $destserver -DbName $dbname -backupfile $path -filestructure $filestructure -ReplaceDatabase -VerifyOnly
					}
					# Testing for suspect pages
					
					if (!$NoDbccCheck -and !$VerifyOnly) { Check-Database }
					if ($VerifyOnly) { $dbccresult = "Skipped" }
					if (!$NoDrop) { Drop-Database }
				}
			}
			
			if ($Pscmdlet.ShouldProcess("console", "Showing results"))
			{
				# $lastbackup = Get-DbaBackupHistory -SqlServer $sourceserver -Databases $dbname -LastFull
				[pscustomobject]@{
					Server = $source
					Database = $db.name
					FileExists = $fileexists
					RestoreResult = $restoreresult
					DbccResult = $dbccresult
					SizeMB = $lastbackup.TotalSizeMB
					BackupTaken = $lastbackup.Start
					BackupFiles = $lastbackup.Path
				}
			}
		}
		
		$databases = $psboundparameters.Databases
		$exclude = $psboundparameters.Exclude
		
		$sourceserver = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $sqlCredential
		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName
		$serviceaccount = $destserver.ServiceAccount
		
		if (!$databases -and !$Path)
		{
			$databases = $sourceserver.databases.Name
		}
		
		if ($databases -or $exclude)
		{
			$dblist = $databases
			if ($exclude)
			{
				$dblist = $dblist | Where-Object $_ -notin $exclude
			}
		}
	}
	
	PROCESS
	{
		foreach ($dbname in $dblist)
		{
			$db = $sourceserver.databases[$dbname]
			
			# The db check is needed when the number of databases exceeds 255, then it's no longer autopopulated
			if (!$db)
			{
				Write-Warning "$dbname does not exist on $source."
				continue
			}
		}
	}
	
	END
	{
		$sourceserver.ConnectionContext.Disconnect()
		$destserver.ConnectionContext.Disconnect()
	}
}