Function Test-DbaLastBackup
{
<#
.SYNOPSIS
Tests a SQL Server backup to see if it is valid

.DESCRIPTION
Need to finish docs

.PARAMETER SqlServer
What
	
.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted.

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 

Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

.PARAMETER Databases
.PARAMETER Exclude
.PARAMETER Destination
.PARAMETER DataDirectory
.PARAMETER LogDirectory
.PARAMETER VerifyOnly
.PARAMETER NoCheck
.PARAMETER NoDrop
.PARAMETER MaxMB
	
.NOTES 
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Test-DbaLastBackup

.EXAMPLE 
Test-DbaLastBackup -SqlServer sql2016

Determines the last full backup for ALL databases, attempts to restore all databases (with a different name and file structure), then performs a DBCC CHECKTABLE

Once the test is complete, the test restore will be dropped

.EXAMPLE 
Test-DbaLastBackup -SqlServer sql2016 -Databases master

Determines the last full backup for master, attempts to restore it, then performs a DBCC CHECKTABLE

.EXAMPLE 
Test-DbaLastBackup -SqlServer sql2016 -Databases model, master -VerifyOnly

.EXAMPLE 
Test-DbaLastBackup -SqlServer sql2016 -NoCheck -NoDrop

Skips the DBCC CHECKTABLE check. This can help speed up the tests but makes it less tested. NoDrop means that the test restores will remain on the server.

.EXAMPLE 
Test-DbaLastBackup -SqlServer sql2016 -DataDirectory E:\bigdrive -LogDirectory L:\bigdrive -MaxMB 10240

Restores data and log files to alternative locations and only restores databases that are smaller than 10 GB
	
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance", "Source")]
		[object]$SqlServer,
		[object]$SqlCredential,
		[object]$Destination = $SqlServer,
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
		$destserver = Connect-SqlServer -SqlServer $destination -SqlCredential $sqlCredential
		
		if ($destserver.VersionMajor -lt $sourceserver.VersionMajor)
		{
			Write-Warning "$Destination is a lower version than $Sqlserver. Backups would be incompatible."
			continue
		}
		
		if ($destserver.VersionMajor -eq $sourceserver.VersionMajor -and $destserver.VersionMinor -lt $sourceserver.VersionMinor)
		{
			Write-Warning "$Destination is a lower version than $Sqlserver. Backups would be incompatible."
			continue
		}
		
		if ($SqlServer -ne $destination)
		{
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
				Write-Warning "$Destination can't access its local directory $logdirectory. Please check if $serviceaccount has permissions"
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
						
						$destdb = $destserver.databases[$dbname]
						
						if ($destdb)
						{
							Write-Warning "$dbname already exists on $destination - skipping"
							continue
						}
						
						if ($Pscmdlet.ShouldProcess($destination, "Restoring $ogdbname as $dbname"))
						{
							$restoreresult = Restore-Database -SqlServer $destserver -DbName $dbname -backupfile $lastbackup.path -filestructure $temprestoreinfo -VerifyOnly:$VerifyOnly
						}
						
						if (!$NoCheck -and !$VerifyOnly)
						{
							# shouldprocess is taken care of in Start-DbccCheck
							if ($ogdbname -eq "master")
							{
								$dbccresult = "DBCC CHECKTABLE skipped for restored master ($dbname) database"
							}
							else
							{
								$dbccresult = Start-DbccCheck -Server $destserver -DbName $dbname -Table 3>$null
							}
						}
						
						if ($VerifyOnly) { $dbccresult = "Skipped" }
						
						if (!$NoDrop -and $restoreresult -eq "Success")
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
						
						if ($destserver.Databases[$dbname] -ne $null -and !$NoDrop)
						{
							Write-Warning "$dbname was not dropped"
						}
					}
				}
				
				if ($Pscmdlet.ShouldProcess("console", "Showing results"))
				{
					[pscustomobject]@{
						SourceServer = $source
						TestServer = $destination
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