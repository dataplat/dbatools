Function Test-DbaLastBackup
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
.PARAMETER Path
.PARAMETER BackupsDirectory
.PARAMETER DataDirectory
.PARAMETER LogDirectory
.PARAMETER VerifyOnly
.PARAMETER NoCheck
.PARAMETER NoDrop
.PARAMETER MaxMB
	
.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Test-DbaLastBackup

.EXAMPLE 
Test-DbaLastBackup -SqlServer Fade2Black -Databases RideTheLightning

blah


#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance", "Source")]
		[object]$SqlServer,
		[object]$SqlCredential,
		[object]$Destination,
		[string]$Path,
		[string]$BackupsDirectory,
		[string]$DataDirectory,
		[string]$LogDirectory,
		[switch]$VerifyOnly,
		[switch]$NoCheck,
		[switch]$NoDrop,
		[int]$MaxMB
		
	)
	
	DynamicParam { if ($sqlserver) { return Get-ParamSqlDatabases -SqlServer $sqlserver -SqlCredential $SqlCredential } }
	
	BEGIN
	{
		$databases = $psboundparameters.Databases
		$exclude = $psboundparameters.Exclude
		
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
			if (!(Test-SqlPath -SqlServer $destserver -Path $datadirectory))
			{
				$serviceaccount = $destserver.ServiceAccount
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
				$serviceaccount = $destserver.ServiceAccount
				Write-Warning "Can't access $logdirectory Please check if $serviceaccount has permissions"
				continue
			}
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
		$Path
		#>
		
		if ($databases -or $exclude)
		{
			$dblist = $databases
			
			if ($exclude)
			{
				$dblist = $dblist | Where-Object $_ -notin $exclude
			}
			
			foreach ($dbname in $dblist)
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
					$fileexists = $true
					$restorelist = Read-DbaBackupHeader -SqlServer $destserver -Path $lastbackup[0].Path
					$mb = $restorelist.BackupSizeMB
					
					if ($MaxMB -gt 0 -and $MaxMB -lt $mb)
					{
						$restoreresult = "The backup size for $dbname ($mb MB) exceeds the specified maximum size ($MaxMB MB)"
						$dbccresult = "Skipped"
					}
					else
					{
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
							$restoreresult = Restore-Database -SqlServer $destserver -DbName $dbname -backupfile $lastbackup.path -filestructure $temprestoreinfo -ReplaceDatabase -VerifyOnly
						}
						
						if (!$NoCheck -and !$VerifyOnly)
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
						
						if ($VerifyOnly) { $dbccresult = "Skipped" }
						
						if (!$NoDrop)
						{
							if ($Pscmdlet.ShouldProcess($dbname, "Dropping Database $dbname on $destination"))
							{
								## Drop the database
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
					}
				}
				
				if ($Pscmdlet.ShouldProcess("console", "Showing results"))
				{
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
		}
	}
	
	END
	{
		$sourceserver.ConnectionContext.Disconnect()
		$destserver.ConnectionContext.Disconnect()
	}
}