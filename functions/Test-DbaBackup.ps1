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

.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

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
		[switch]$NoCheck,
		[switch]$NoDrop
		
	)
	
	DynamicParam { if ($sqlserver) { return Get-ParamSqlDatabases -SqlServer $sqlserver -SqlCredential $SqlCredential } }
	
	BEGIN
	{
		$databases = $psboundparameters.Databases
		$sourceserver = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $sqlCredential
		
		if ($SqlServer -ne $destination)
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
		
		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName
		
		if ($datadirectory)
		{
			# Test location
		}
		else
		{
			$datadirectory = Get-SqlDefaultPaths -SqlServer $destserver -FileType mdf
		}
		
		if ($logdirectory)
		{
			# test location
		}
		else
		{
			$logdirectory = Get-SqlDefaultPaths -SqlServer $destserver -FileType ldf
		}
		
		if ($databases.count -eq 0)
		{
			$databases = $sourceserver.databases.Name
		}
	}
	
	PROCESS
	{
		<#
			$restorelist = Get-RestoreFileList -server $server -filepath C:\temp\whatever.bak
			$filelist = $restorelist.Filelist
			$dbname = $restorelist.DatabaseName
		#>
		
		<#
		if (!(Test-SqlPath -SqlServer $destserver -Path $backupFolder))
		{
			$serviceaccount = $destserver.ServiceAccount
			throw "Can't access $backupFolder Please check if $serviceaccount has permissions"
		}
		#>
		
		if ($databases)
		{
			foreach ($dbname in $databases)
			{
				
				$db = $sourceserver.databases[$dbname]
				
				# The db check is needed when the number of databases exceeds 255, then it's no longer autopopulated
				if (!$db)
				{
					Write-Warning "$dbname does not exist on $source."
					continue
				}
				
				$lastbackup = Get-DbaBackupHistory -SqlServer $sourceserver -Databases $dbname -LastFull
				
				if ($lastbackup -eq $null)
				{
					$lastbackup = @{ Path = "Not found" }
					$fileexists = $false
					$restoreresult = "Skipped"
					$dbccresult = "Skipped"
				}
				elseif ($source -ne $destination -and $lastbackup[0].Path.StartsWith('\\') -eq $false)
				{
					$fileexists = "Skipped"
					$restoreresult = "Restore not located on shared location"
					$dbccresult = "Skipped"
				}
				elseif ((Test-SqlPath -SqlServer $destserver -Path $lastbackup[0].Path) -eq $false)
				{
					$fileexists = $false
					$restoreresult = "Skipped"
					$dbccresult = "Skipped"
				}
				else
				{
					$restorelist = Get-RestoreFileList -server $destserver -filepath $lastbackup[0].Path
					$fileexists = $true
					
					$filelist = $restorelist.Filelist
					$dbname = $restorelist.DatabaseName
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
					
					$ogdbname = $dbname
					$dbname = "dbatools-testrestore-$dbname"
					
					## Run a Dbcc No choice here
					if ($Pscmdlet.ShouldProcess($destination, "Restoring $ogdbname as $dbname"))
					{
						$restoreresult = Restore-Database -SqlServer $destserver -DbName $dbname -backupfile $lastbackup.path -filestructure $temprestoreinfo
					}
					
					if (!$NoCheck)
					{
						if ($Pscmdlet.ShouldProcess($dbname, "Running Dbcc CHECKDB on $dbname on $destination"))
						{
							if ($ogdbname -eq "master")
							{
								$dbccresult = "DBCC CHECKDB skipped for restored master ($dbname) database"
							}
							else
							{
								$dbccresult = Start-DbccCheck -Server $destserver -DbName $dbname 3>$null
							}
						}
					}
					
					if (!$NoDrop)
					{
						if ($Pscmdlet.ShouldProcess($dbname, "Dropping Database $dbname on $destination"))
						{
							## Drop the database
							try
							{
								$null = Remove-SqlDatabase -SqlServer $destserver -DbName $dbname
								Write-Verbose "Dropped $dbname Database on $destination"
							}
							catch
							{
								Write-Warning "FAILED : To Drop database $dbname on $destination - Aborting"
								Write-Exception $_
								continue
							}
						}
					}
				}
				
				if ($Pscmdlet.ShouldProcess("console", "Showing results"))
				{
					[pscustomobject]@{
						Server = $source
						Database = $db.name
						File = $lastbackup.Path
						FileExists = $fileexists
						RestoreResult = $restoreresult
						DbccResult = $dbccresult
					}
				}
			}
		}
	}
	
	END
	{
		$sourceserver.ConnectionContext.Disconnect()
		$destserver.ConnectionContext.Disconnect()
	}
}