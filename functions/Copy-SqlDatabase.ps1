Function Copy-SqlDatabase
{
<# 
.SYNOPSIS 
Migrates Sql Server databases from one Sql Server to another.

.DESCRIPTION 
This script provides the ability to migrate databases using detach/copy/attach or backup/restore. This script works with named instances, clusters and Sql Express.

By default, databases will be migrated to the destination Sql Server's default data and log directories. You can override this by specifying -ReuseFolderStructure. Filestreams and filegroups are also migrated. Safety is emphasized.

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

.PARAMETER Source
Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER Destination
Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SourceSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, this pass $scred object to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.PARAMETER DestinationSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$dcred = Get-Credential, this pass this $dcred to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.PARAMETER All
This is a parameter that was included for safety, so you don't accidentally detach/attach all databases without specifying. Migrates user databases. Does not migrate system or support databases. Requires -BackupRestore or -DetachAttach. 

.PARAMETER IncludeSupportDbs
Migration of ReportServer, ReportServerTempDb, SSIDb, and distribution databases if they exist. A logfile named $SOURCE-$DESTINATION-$date-Sqls.csv will be written to the current directory. Requires -BackupRestore or -DetachAttach.

.PARAMETER BackupRestore
Use the a Copy-Only Backup and Restore Method. This parameter requires that you specify -NetworkShare in a valid UNC format (\\server\share)

.PARAMETER DetachAttach
Uses the detach/copy/attach method to perform database migrations. No files are deleted on the source. If the destination attachment fails, the source database will be reattached. File copies are performed over administrative shares (\\server\x$\mssql) using BITS. If a database is being mirrored, the mirror will be broken prior to migration. 

.PARAMETER Reattach
Reattaches all source databases after DetachAttach migration.

.PARAMETER ReuseFolderStructure
By default, databases will be migrated to the destination Sql Server's default data and log directories. 
You can override this by specifying -ReuseFolderStructure. 
The same structure on the SOURCE will be kept exactly, so consider this if you're migrating between 
different versions and use part of Microsoft's default Sql structure (MSSql12.INSTANCE, etc)

* note, to reuse destination folder structure, specify -WithReplace

.PARAMETER NetworkShare
Specifies the network location for the backup files. The Sql Service service accounts must read/write permission to access this location.

.PARAMETER Exclude
Excludes specified databases when performing -All migrations. This list is auto-populated for tab completion.

.PARAMETER Database
Migrates ONLY specified databases. This list is auto-populated for tab completion. Multiple databases are allowed.

.PARAMETER SetSourceReadOnly
Sets all migrated databases to ReadOnly prior to detach/attach & backup/restore. If -Reattach is used, db is set to read-only after reattach.

.PARAMETER NoRecovery
Sets restore to NoRecovery. Ideal for staging. 
	
.PARAMETER WithReplace
It's exactly WITH REPLACE. This is useful if you want to stage some complex file paths.

.PARAMETER Force
Drops existing databases with matching names. If using -DetachAttach, -Force will break mirrors and drop dbs from Availability Groups.

.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers
Limitations: Doesn't cover what it doesn't cover (replication, certificates, etc)
			 Sql Server 2000 databases cannot be directly migrated to Sql Server 2012 and above.
			 Logins within Sql Server 2012 and above logins cannot be migrated to Sql Server 2008 R2 and below.				

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.


.LINK
https://dbatools.io/Copy-SqlDatabase

.EXAMPLE   
Copy-SqlDatabase -Source sqlserver2014a -Destination sqlcluster -DetachAttach -Reattach

Description

Databases will be migrated from sqlserver2014a to sqlcluster using the detach/copy files/attach method.The following will be perfomed: kick all users out of the database, detach all data/log files, move files across the network over an admin share (\\SqlSERVER\M$\MSSql...), attach file on destination server, reattach at source. If the database files (*.mdf, *.ndf, *.ldf) on *destination* exist and aren't in use, they will be overwritten.


.EXAMPLE   
Copy-SqlDatabase -Source sqlserver2014a -Destination sqlcluster -Exclude Northwind, pubs -IncludeSupportDbs -Force -BackupRestore \\fileshare\sql\migration

Description

Migrates all user databases except for Northwind and pubs by using backup/restore (copy-only). Backup files are stored in \\fileshare\sql\migration. If the database exists on the destination, it will be dropped prior to attach.

It also includes the support databases (ReportServer, ReportServerTempDb, distribution). 

#>	
	[CmdletBinding(DefaultParameterSetName = "DbMigration", SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $True)]
		[object]$Source,
		[parameter(Mandatory = $true)]
		[object]$Destination,
		[Parameter(Mandatory = $true, ParameterSetName = "DbAttachDetach")]
		[switch]$DetachAttach,
		[Parameter(Mandatory = $true, ParameterSetName = "DbBackup")]
		[switch]$BackupRestore,
		[Parameter(ParameterSetName = "DbBackup")]
		[Parameter(ParameterSetName = "DbAttachDetach")]
		[switch]$ReuseFolderstructure,
		[Parameter(ParameterSetName = "DbBackup")]
		[Parameter(ParameterSetName = "DbAttachDetach")]
		[switch]$All,
		[Parameter(ParameterSetName = "DbBackup")]
		[Parameter(ParameterSetName = "DbAttachDetach")]
		[switch]$IncludeSupportDbs,
		[Parameter(ParameterSetName = "DbAttachDetach")]
		[switch]$Reattach,
		[Parameter(Mandatory = $true, ParameterSetName = "DbBackup",
				   HelpMessage = "Specify a valid network share in the format \\server\share that can be accessed by your account and both Sql Server service accounts.")]
		[string]$NetworkShare,
		[Parameter(ParameterSetName = "DbBackup")]
		[Parameter(ParameterSetName = "DbAttachDetach")]
		[switch]$SetSourceReadOnly,
		[Parameter(ParameterSetName = "DbBackup")]
		[switch]$NoRecovery,
		[Parameter(ParameterSetName = "DbBackup")]
		[switch]$WithReplace,
		[switch]$Force,
		[System.Management.Automation.PSCredential]$SourceSqlCredential,
		[System.Management.Automation.PSCredential]$DestinationSqlCredential,
		[parameter(ValueFromPipeline = $true, DontShow)]
		[object]$pipedatabase
	)
	
	DynamicParam { if ($source) { return Get-ParamSqlDatabases -SqlServer $source -SqlCredential $SourceSqlCredential } }
	
	BEGIN
	{	
		Function Get-SqlFileStructure
		{
			$dbcollection = @{ };
			
			foreach ($db in $sourceserver.databases)
			{
				$dbstatus = $db.status.toString()
				
				if ($dbstatus.StartsWith("Normal") -eq $false)
				{
					continue
				}
				
				$destinationfiles = @{ }; $sourcefiles = @{ }
				
				# Data Files
				foreach ($filegroup in $db.filegroups)
				{
					foreach ($file in $filegroup.files)
					{
						# Destination File Structure
						$d = @{ }
						if ($ReuseFolderstructure)
						{
							$d.physical = $file.filename
						}
						else
						{
							$directory = Get-SqlDefaultPaths $destserver data
							$filename = Split-Path $($file.filename) -leaf
							$d.physical = "$directory\$filename"
						}
						$d.logical = $file.name
						$d.remotefilename = Join-AdminUNC $destnetbios $d.physical
						$destinationfiles.add($file.name, $d)
						
						# Source File Structure
						$s = @{ }
						$s.logical = $file.name
						$s.physical = $file.filename
						$s.remotefilename = Join-AdminUNC $sourcenetbios $s.physical
						$sourcefiles.add($file.name, $s)
					}
				}
				
				# Add support for Full Text Catalogs in Sql Server 2005 and below
				if ($sourceserver.VersionMajor -lt 10)
				{
					foreach ($ftc in $db.FullTextCatalogs)
					{
						# Destination File Structure
						$d = @{ }
						$pre = "sysft_"
						$name = $ftc.name
						$physical = $ftc.RootPath
						$logical = "$pre$name"
						if ($ReuseFolderstructure)
						{
							$d.physical = $physical
						}
						else
						{
							$directory = Get-SqlDefaultPaths $destserver data
							if ($destserver.VersionMajor -lt 10) { $directory = "$directory\FTDATA" }
							$filename = Split-Path($physical) -leaf
							$d.physical = "$directory\$filename"
						}
						
						$d.logical = $logical
						$d.remotefilename = Join-AdminUNC $destnetbios $d.physical
						$destinationfiles.add($logical, $d)
						
						# Source File Structure
						$s = @{ }
						$pre = "sysft_"
						$name = $ftc.name
						$physical = $ftc.RootPath
						$logical = "$pre$name"
						
						$s.logical = $logical
						$s.physical = $physical
						$s.remotefilename = Join-AdminUNC $sourcenetbios $s.physical
						$sourcefiles.add($logical, $s)
					}
				}
				
				# Log Files
				foreach ($file in $db.logfiles)
				{
					$d = @{ }
					if ($ReuseFolderstructure)
					{
						$d.physical = $file.filename
					}
					else
					{
						$directory = Get-SqlDefaultPaths $destserver log
						$filename = Split-Path $($file.filename) -leaf
						$d.physical = "$directory\$filename"
					}
					$d.logical = $file.name
					$d.remotefilename = Join-AdminUNC $destnetbios $d.physical
					$destinationfiles.add($file.name, $d)
					
					$s = @{ }
					$s.logical = $file.name
					$s.physical = $file.filename
					$s.remotefilename = Join-AdminUNC $sourcenetbios $s.physical
					$sourcefiles.add($file.name, $s)
				}
				
				$location = @{ }
				$location.add("Destination", $destinationfiles)
				$location.add("Source", $sourcefiles)
				$dbcollection.Add($($db.name), $location)
			}
			
			$filestructure = [pscustomobject]@{ "databases" = $dbcollection }
			return $filestructure
		}
		
		# Backup Restore
		Function Backup-SqlDatabase
		{
			[CmdletBinding()]
			param (
				[Parameter(Mandatory = $true)]
				[ValidateNotNullOrEmpty()]
				[object]$server,
				[Parameter(Mandatory = $true)]
				[ValidateNotNullOrEmpty()]
				[string]$dbname,
				[Parameter(Mandatory = $true)]
				[ValidateNotNullOrEmpty()]
				[string]$backupfile
			)
			
			$server.ConnectionContext.StatementTimeout = 0
			$backup = New-Object "Microsoft.SqlServer.Management.Smo.Backup"
			$backup.Action = "Database"
			$backup.CopyOnly = $true
			$device = New-Object "Microsoft.SqlServer.Management.Smo.BackupDeviceItem"
			$device.DeviceType = "File"
			$device.Name = $backupfile
			$backup.Devices.Add($device)
			$backup.Database = $dbname
			
			$percent = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler]
			{
				Write-Progress -id 1 -activity "Backing up database $dbname to $backupfile" -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent))
			}
			$backup.add_PercentComplete($percent)
			$backup.add_Complete($complete)
			
			Write-Progress -id 1 -activity "Backing up database $dbname to $backupfile" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
			Write-Output "Backing up $dbname"
			
			try
			{
				$backup.SqlBackup($server)
				Write-Progress -id 1 -activity "Backing up database $dbname to $backupfile" -status "Complete" -Completed
				Write-Output "Backup succeeded"
				return $true
			}
			catch
			{
				Write-Progress -id 1 -activity "Backup" -status "Failed" -completed
				Write-Exception $_
				return $false
			}
		}
		
		Function Restore-SqlDatabase
		{
			[CmdletBinding()]
			param (
				[Parameter(Mandatory = $true)]
				[ValidateNotNullOrEmpty()]
				[object]$server,
				[Parameter(Mandatory = $true)]
				[ValidateNotNullOrEmpty()]
				[string]$dbname,
				[Parameter(Mandatory = $true)]
				[ValidateNotNullOrEmpty()]
				[string]$backupfile,
				[Parameter(Mandatory = $true)]
				[ValidateNotNullOrEmpty()]
				[object]$filestructure
				
			)
			
			$servername = $server.name
			$server.ConnectionContext.StatementTimeout = 0
			$restore = New-Object "Microsoft.SqlServer.Management.Smo.Restore"
			
			if ($WithReplace -eq $false -or $server.databases[$dbname] -eq $null)
			{
				foreach ($file in $filestructure.databases[$dbname].destination.values)
				{
					$movefile = New-Object "Microsoft.SqlServer.Management.Smo.RelocateFile"
					$movefile.LogicalFileName = $file.logical
					$movefile.PhysicalFileName = $file.physical
					$null = $restore.RelocateFiles.Add($movefile)
				}
			}
			
			Write-Output "Restoring $dbname to $servername"
			
			try
			{
				
				$percent = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler]
				{
					Write-Progress -id 1 -activity "Restoring $dbname to $servername" -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent))
				}
				
				$restore.add_PercentComplete($percent)
				$restore.PercentCompleteNotification = 1
				$restore.add_Complete($complete)
				$restore.ReplaceDatabase = $true
				$restore.Database = $dbname
				$restore.Action = "Database"
				$restore.NoRecovery = $NoRecovery
				$device = New-Object -TypeName Microsoft.SqlServer.Management.Smo.BackupDeviceItem
				$device.name = $backupfile
				$device.devicetype = "File"
				$restore.Devices.Add($device)
				
				Write-Progress -id 1 -activity "Restoring $dbname to $servername" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
				$restore.sqlrestore($server)
				Write-Progress -id 1 -activity "Restoring $dbname to $servername" -status "Complete" -Completed
				
				return $true
			}
			catch
			{
				write-warning "Restore failed: $($_.Exception.InnerException.Message)"
				Write-Exception $_
				return $false
			}
		}
		
		Function Start-SqlBackupRestore
		{
			
			$filestructure = Get-SqlFileStructure $sourceserver $destserver $ReuseFolderstructure
			$filename = "$dbname-$timenow.bak"
			$backupfile = Join-Path $networkshare $filename
			
			$backupresult = Backup-SqlDatabase $sourceserver $dbname $backupfile
			
			if ($backupresult)
			{
				$restoreresult = Restore-SqlDatabase $destserver $dbname $backupfile $filestructure
				
				if ($restoreresult)
				{
					# RESTORE was successful
					Write-Output "Successfully restored $dbname to $destination"
					return $true
					
				}
				else
				{
					# RESTORE was unsuccessful
					if ($ReuseFolderStructure)
					{
						Write-Error "Failed to restore $dbname to $destination. You specified -ReuseFolderStructure. Does the exact same destination directory structure exist?"
						return "Failed to restore $dbname to $destination using ReuseFolderStructure."
					}
					else
					{
						Write-Error "Failed to restore $dbname to $destination"
						return "Failed to restore $dbname to $destination."
					}
				}
				
			}
			else
			{
				# add to failed because BACKUP was unsuccessful
				Write-Error "Backup Failed. Does Sql Server account ($($sourceserver.ServiceAccount)) have access to $($NetworkShare)?"
				return "Backup Failed. Does Sql Server account ($($sourceserver.ServiceAccount)) have access to $NetworkShare` and does the fileshare have space?"
			}
		}
		
		# Detach Attach 
		Function Dismount-SqlDatabase
		{
			[CmdletBinding()]
			param (
				[Parameter(Mandatory = $true)]
				[ValidateNotNullOrEmpty()]
				[object]$server,
				[Parameter(Mandatory = $true)]
				[ValidateNotNullOrEmpty()]
				[string]$dbname
				
			)
			
			$database = $server.databases[$dbname]
			
			if ($database.IsMirroringEnabled)
			{
				try
				{
					Write-Warning "Breaking mirror for $dbname"
					$database.ChangeMirroringState([Microsoft.SqlServer.Management.Smo.MirroringOption]::Off)
					$database.Alter()
					$database.Refresh()
					Write-Warning "Could not break mirror for $dbname. Skipping."
				}
				catch
				{
					Write-Exception $_
					return $false
				}
			}
			
			if ($database.AvailabilityGroupName.Length -gt 0)
			{
				$agname = $database.AvailabilityGroupName
				Write-Output "Attempting remove from Availability Group $agname"
				try
				{
					$server.AvailabilityGroups[$database.AvailabilityGroupName].AvailabilityDatabases[$dbname].Drop()
					Write-Output "Successfully removed $dbname from  detach from $agname on $($server.name)"
				}
				catch
				{
					Write-Error "Could not remove $dbname from $agname on $($server.name)"; Write-Exception $_
					return $false
				}
			}
			
			Write-Output "Attempting detach from $dbname from $source"
			
			####### Using Sql to detach does not modify the $database collection #######
			
			
			try
			{
				$sql = "ALTER DATABASE [$dbname] SET SINGLE_USER WITH ROLLBACK IMMEDIATE"
				$null = $server.ConnectionContext.ExecuteNonQuery($sql)
				Write-Output "Successfully set $dbname to single-user from $source"
			}
			catch
			{
				Write-Exception $_
			}
			
			try
			{
				$sql = "EXEC master.dbo.sp_detach_db N'$dbname'"
				$null = $server.ConnectionContext.ExecuteNonQuery($sql)
				Write-Output "Successfully detached $dbname from $source"
			}
			catch
			{
				Write-Exception $_
			}
			
		}
		
		Function Copy-SqlDatabase
		{
			
		<# ###############################################################
		
								Server Checks
			
		############################################################### #>
			
			if ($sourceserver.Databases.count -le 4)
			{
				throw "No user databases to migrate. Quitting."
			}
			
			if ([version]$sourceserver.ResourceVersionString -gt [version]$destserver.ResourceVersionString)
			{
				throw "Source Sql Server version build must be <= destination Sql Server for database migration."
			}
			if ($fswarning)
			{
				Write-Warning "FILESTREAM enabled on $source but not $destination. Databases that use FILESTREAM will be skipped."
			}
			
			Write-Output "Checking access to remote directories..."
			Write-Output "Resolving NetBIOS name for $source..."
			$sourcenetbios = Get-NetBIOSName $sourceserver
			Write-Output "Resolving NetBIOS name for $destination..."
			$destnetbios = Get-NetBIOSName $destserver
			$remotesourcepath = Join-AdminUNC $sourcenetbios (Get-SqlDefaultPaths $sourceserver data)
			
			If ((Test-Path $remotesourcepath) -ne $true -and $DetachAttach)
			{
				Write-Error "Can't access remote Sql directories on $source which is required to perform detach/copy/attach."
				Write-Error "You can manually try accessing $remotesourcepath to diagnose any issues."
				Write-Error "Halting database migration."
				return
			}
			
			$remotedestpath = Join-AdminUNC $destnetbios (Get-SqlDefaultPaths $destserver data)
			If ((Test-Path $remotedestpath) -ne $true -and $DetachAttach)
			{
				Write-Error "Can't access remote Sql directories on $destination which is required to perform detach/copy/attach."
				Write-Error "You can manually try accessing $remotedestpath to diagnose any issues."
				Write-Error "Halting database migration."
				return
			}
			
			##################################################################
			
			$SupportDBs = "ReportServer", "ReportServerTempDB", "distribution"
			$sa = $changedbowner
			
			$filestructure = Get-SqlFileStructure $sourceserver $destserver $ReuseFolderstructure
			
			foreach ($database in $sourceserver.databases)
			{
				$dbelapsed = [System.Diagnostics.Stopwatch]::StartNew()
				$dbname = $database.name
				$dbowner = $database.Owner
				
				<# ###############################################################
				
									Database Checks
					
				############################################################### #>
				
				if ($database.id -le 4) { continue }
				
				if ($Databases -and $Databases -notcontains $dbname) { continue }
				if ($IncludeSupportDBs -eq $false -and $SupportDBs -contains $dbname) { continue }
				if ($IncludeSupportDBs -eq $true -and $SupportDBs -notcontains $dbname)
				{
					if ($All -eq $false -and $Databases.length -eq 0) { continue }
				}
				
				Write-Output "`n######### Database: $dbname #########"
				$dbstart = Get-Date
				
				if ($skippedb.ContainsKey($dbname) -and $Databases -eq $null)
				{
					Write-Output "`nSkipping $dbname"
					continue
				}
				
				if ($database.IsAccessible -eq $false)
				{
					Write-Warning "Skipping $dbname. Database is inaccessible."
					$skippedb.Add($dbname, "Skipped. Database is inaccessible.")
					continue
				}
				
				if ($fswarning -and ($database.FileGroups | Where { $_.isFilestream }) -ne $null)
				{
					Write-Warning "Skipping $dbname (contains FILESTREAM)"
					$skippedb.Add($dbname, "Skipped. Database contains FILESTREAM and FILESTREAM is disabled on $destination.")
					continue
				}
				
				if ($ReuseFolderstructure)
				{
					$remotepath = Split-Path ($database.FileGroups[0].Files.FileName)
					$remotepath = Join-AdminUNC $destnetbios $remotepath
					
					if (!(Test-Path $remotepath))
					{
						throw "Cannot resolve $remotepath. `n`nYou have specified ReuseFolderstructure and exact folder structure does not exist. Halting script."
					}
				}
				
				if ($database.AvailabilityGroupName.Length -gt 0 -and !$force -and $DetachAttach)
				{
					$agname = $database.AvailabilityGroupName
					Write-Warning "Database is part of an Availability Group ($agname). Use -Force to drop from $agname and migrate. Alternatively, you can use the safer backup/restore method."
					continue
				}
				
				$dbstatus = $database.status.toString()
				
				if ($dbstatus.StartsWith("Normal") -eq $false)
				{
					Write-Warning "$dbname is not in a Normal state. Skipping."
					continue
				}
				
				if ($database.ReplicationOptions -ne "None" -and $DetachAttach -eq $true)
				{
					Write-Warning "$dbname is part of replication. Skipping."
					continue
				}
				
				
				if ($database.IsMirroringEnabled -and !$force -and $DetachAttach)
				{
					Write-Warning "Database is being mirrored. Use -Force to break mirror and migrate. Alternatively, you can use the safer backup/restore method."
					continue
				}
				
				if (($destserver.Databases[$dbname] -ne $null) -and !$force -and !$WithReplace)
				{
					Write-Warning "Database exists at destination. Use -Force to drop and migrate."
					continue
				}
				elseif ($destserver.Databases[$dbname] -ne $null -and $force)
				{
					If ($Pscmdlet.ShouldProcess($destination, "DROP DATABASE $dbname"))
					{
						Write-Output "$dbname already exists. -Force was specified. Dropping $dbname on $destination."
						$dropresult = Remove-SqlDatabase $destserver $dbname
						if ($dropresult -eq $false)
						{
							continue
						}
					}
				}
				
				
				If ($Pscmdlet.ShouldProcess("console", "Showing start time"))
				{
					Write-Output "Started: $dbstart"
				}
				
				if ($sourceserver.versionMajor -ge 9)
				{
					$sourcedbownerchaining = $sourceserver.databases[$dbname].DatabaseOwnershipChaining
					$sourcedbtrustworthy = $sourceserver.databases[$dbname].Trustworthy
					$sourcedbbrokerenabled = $sourceserver.databases[$dbname].BrokerEnabled
					
				}
				
				$sourcedbreadonly = $sourceserver.Databases[$dbname].ReadOnly
				
				if ($SetSourceReadOnly)
				{
					If ($Pscmdlet.ShouldProcess($source, "Set $dbname to read-only"))
					{
						$result = Update-SqldbReadOnly $sourceserver $dbname $true
					}
				}
				
				if ($BackupRestore)
				{
					If ($Pscmdlet.ShouldProcess($destination, "Backup $dbname from $source and restoring."))
					{
						$result = (Start-SqlBackupRestore $sourceserver $destserver $dbname $networkshare $force)
						$dbfinish = Get-Date
						
						if ($result -eq $true)
						{
							Write-Output "Successfully restored $dbname"
							$migrateddb.Add($dbname, "Successfully migrated,$dbstart,$dbfinish")
							if (!$norecovery)
							{
								$result = Update-Sqldbowner $sourceserver $destserver -dbname $dbname
							}
						}
						else
						{
							Write-Output "Failed to restore $dbname"
							$skippedb[$dbname] = $result
						}
					}
				} # End of backup
				
				elseif ($DetachAttach)
				{
					$sourcefilestructure = New-Object System.Collections.Specialized.StringCollection
					
					foreach ($file in $filestructure.databases[$dbname].source.values)
					{
						$null = $sourcefilestructure.add($file.physical)
					}
					
					$dbowner = $sourceserver.databases[$dbname].owner
					
					if ($dbowner -eq $null)
					{
						$dbowner = "sa"
					}
					
					If ($Pscmdlet.ShouldProcess($destination, "Detach $dbname from $source and attach, then update dbowner"))
					{
						$result = Start-SqlDetachAttach $sourceserver $destserver $filestructure $dbname $force
						$dbfinish = Get-Date
						
						if ($result -eq $true)
						{
							$migrateddb.Add($dbname, "Successfully migrated,$dbstart,$dbfinish")
							if (!$norecovery)
							{
								$result = Update-Sqldbowner $sourceserver $destserver -dbname $dbname
							}
						}
						else
						{
							Write-Output "Failed to attach $dbname"
						}
						
						if ($Reattach)
						{
							$null = ($sourceserver.databases).Refresh()
							$result = Mount-SqlDatabase $sourceserver $dbname $sourcefilestructure $dbowner
							if ($result -eq $true)
							{
								$sourceserver.databases[$dbname].DatabaseOwnershipChaining = $sourcedbownerchaining
								$sourceserver.databases[$dbname].Trustworthy = $sourcedbtrustworthy
								$sourceserver.databases[$dbname].BrokerEnabled = $sourcedbbrokerenabled
								$sourceserver.databases[$dbname].alter()
								
								if ($SetSourceReadOnly)
								{
									$null = Update-SqldbReadOnly $sourceserver $dbname $true
								}
								
								else
								{
									$null = Update-SqldbReadOnly $sourceserver $dbname $sourcedbreadonly
								}
								
								Write-Output "Successfully reattached $dbname to $source"
								
							}
							else
							{
								Write-Warning "Could not reattach $dbname to $source."
							}
						}
					}
				} #end of if detach/backup
				
				# restore poentially lost settings
				# NEED TO SET A FLAG HERE
				
				if ($destserver.versionMajor -ge 9 -and $norecovery -eq $false)
				{
					
					if ($sourcedbownerchaining -ne $destserver.databases[$dbname].DatabaseOwnershipChaining)
					{
						If ($Pscmdlet.ShouldProcess($destination, "Updating DatabaseOwnershipChaining on $dbname"))
						{
							try
							{
								$destserver.databases[$dbname].DatabaseOwnershipChaining = $sourcedbownerchaining
								$destserver.databases[$dbname].alter()
								Write-Output "Successfully updated DatabaseOwnershipChaining for $sourcedbownerchaining on $dbname on $destination"
							}
							catch
							{
								Write-Error "Failed to update DatabaseOwnershipChaining for $sourcedbownerchaining on $dbname on $destination"
								Write-Exception $_
							}
						}
					}
					
					if ($sourcedbtrustworthy -ne $destserver.databases[$dbname].Trustworthy)
					{
						If ($Pscmdlet.ShouldProcess($destination, "Updating Trustworthy on $dbname"))
						{
							try
							{
								$destserver.databases[$dbname].Trustworthy = $sourcedbtrustworthy
								$destserver.databases[$dbname].alter()
								Write-Output "Successfully updated Trustworthy to $sourcedbtrustworthy for $dbname on $destination"
							}
							catch
							{
								Write-Error "Failed to update Trustworthy to $sourcedbtrustworthy for $dbname on $destination"
								Write-Exception $_
							}
						}
					}
					
					if ($sourcedbbrokerenabled -ne $destserver.databases[$dbname].BrokerEnabled)
					{
						If ($Pscmdlet.ShouldProcess($destination, "Updating BrokerEnabled on $dbname"))
						{
							try
							{
								$destserver.databases[$dbname].BrokerEnabled = $sourcedbbrokerenabled
								$destserver.databases[$dbname].alter()
								Write-Output "Successfully updated BrokerEnabled to $sourcedbbrokerenabled for $dbname on $destination"
							}
							catch { Write-Error "Failed to update BrokerEnabled to $sourcedbbrokerenabled for $dbname on $destination"; Write-Exception $_ }
						}
					}
				}
				
				if ($sourcedbreadonly -ne $destserver.databases[$dbname].ReadOnly -and $norecovery -eq $false)
				{
					If ($Pscmdlet.ShouldProcess($destination, "Updating ReadOnly status on $dbname"))
					{
						try
						{
							$result = Update-SqldbReadOnly $destserver $dbname $sourcedbreadonly
							
							if ($sourcedbreadonly -eq $true)
							{
								Write-Output "Successfully updated Read-Only to $sourcedbreadonly for $dbname on $destination"
							}
						}
						catch
						{
							Write-Error "Failed to update ReadOnly status on $dbname"
							Write-Exception $_
						}
					}
				}
				
				
				If ($Pscmdlet.ShouldProcess("console", "Showing elapsed time"))
				{
					$dbtotaltime = $dbfinish - $dbstart
					$dbtotaltime = ($dbtotaltime.toString().Split(".")[0])
					
					Write-Output "Finished: $dbfinish"
					Write-Output "Elapsed time: $dbtotaltime"
				}
				
			} # end db by db processing
		}
		
		Function Mount-SqlDatabase
		{
			[CmdletBinding()]
			param (
				[Parameter(Mandatory = $true)]
				[ValidateNotNullOrEmpty()]
				[object]$server,
				[Parameter(Mandatory = $true)]
				[ValidateNotNullOrEmpty()]
				[string]$dbname,
				[Parameter(Mandatory = $true)]
				[ValidateNotNullOrEmpty()]
				[object]$filestructure,
				[Parameter(Mandatory = $true)]
				[ValidateNotNullOrEmpty()]
				[string]$dbowner
			)
			
			if ($server.Logins.Item($dbowner) -eq $null) { $dbowner = 'sa' }
			try
			{
				$null = $server.AttachDatabase($dbname, $filestructure, $dbowner, [Microsoft.SqlServer.Management.Smo.AttachOptions]::None)
				return $true
			}
			catch
			{
				Write-Exception $_
				return $false
			}
		}
		
		Function Start-SqlFileTransfer
		{
			<#

			SYNOPSIS
			Internal function. Uses BITS to transfer detached files (.mdf, .ndf, .ldf, and filegroups) to 
			another server over admin UNC paths. Locations of data files are kept in the
			custom object generated by Get-SqlFileStructure

			#>			
			
			$copydb = $filestructure.databases[$dbname]
			$dbsource = $copydb.source
			$dbdestination = $copydb.destination
			
			foreach ($file in $dbsource.keys)
			{
				$remotefilename = $dbdestination[$file].remotefilename
				$from = $dbsource[$file].remotefilename
				try
				{
					if (Test-Path $from -pathtype container)
					{
						$null = New-Item -ItemType Directory -Path $remotefilename -Force
						Start-BitsTransfer -Source "$from\*.*" -Destination $remotefilename
						
						$directories = (Get-ChildItem -recurse $from | where { $_.PsIsContainer }).FullName
						foreach ($directory in $directories)
						{
							$newdirectory = $directory.replace($from, $remotefilename)
							$null = New-Item -ItemType Directory -Path $newdirectory -Force
							Start-BitsTransfer -Source "$directory\*.*" -Destination $newdirectory
						}
					}
					else
					{
						Write-Host "Copying $fn for $dbname"
						Start-BitsTransfer -Source $from -Destination $remotefilename
					}
					$fn = Split-Path $($dbdestination[$file].physical) -leaf
				}
				catch
				{
					try
					{
						# Sometimes BITS trips out temporarily on cloned drives.
						Start-BitsTransfer -Source $from -Destination $remotefilename
					}
					catch
					{
						throw "$_ `n This sometimes happens with cloned VMs. You can try again or use Backup and Restore"
					}
				}
			}
			return $true
		}
		
		Function Start-SqlDetachAttach
		{
			
			$destfilestructure = New-Object System.Collections.Specialized.StringCollection
			$sourcefilestructure = New-Object System.Collections.Specialized.StringCollection
			$dbowner = $sourceserver.databases[$dbname].owner
			
			if ($dbowner -eq $null)
			{
				$dbowner = 'sa'
			}
			
			foreach ($file in $filestructure.databases[$dbname].destination.values)
			{
				$null = $destfilestructure.add($file.physical)
			}
			
			foreach ($file in $filestructure.databases[$dbname].source.values)
			{
				$null = $sourcefilestructure.add($file.physical)
			}
			
			$detachresult = Dismount-SqlDatabase $sourceserver $dbname
			
			if ($detachresult)
			{
				
				$transfer = Start-SqlFileTransfer $filestructure $dbname
				if ($transfer -eq $false)
				{
					Write-Warning "Could not copy files."; return "Could not copy files."
				}
				
				$attachresult = Mount-SqlDatabase $destserver $dbname $destfilestructure $dbowner
				
				if ($attachresult -eq $true)
				{
					# add to added dbs because ATTACH was successful
					Write-Output "Successfully attached $dbname to $destination"
					return $true
				}
				else
				{
					# add to failed because ATTACH was unsuccessful
					Write-Warning "Could not attach $dbname."
					return "Could not attach database."
				}
			}
			else
			{
				# add to failed because DETACH was unsuccessful
				Write-Warning "Could not detach $dbname."
				return "Could not detach database."
			}
		}
		
		$elapsed = [System.Diagnostics.Stopwatch]::StartNew()
		$started = Get-Date
		$script:timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
		
		# Convert from RuntimeDefinedParameter object to regular array
		$databases = $psboundparameters.Databases
		$exclude = $psboundparameters.Exclude
		
		if ($pipedatabase.Length -gt 0)
		{
			$Source = $pipedatabase[0].parent.name
			$databases = $pipedatabase.name
		}
		
		if ($databases -contains "master" -or $databases -contains "msdb" -or $databases -contains "tempdb")
		{
			throw "Migrating system databases is not currently supported."
		}
		
		Write-Output "Attempting to connect to Sql Servers.."
		$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
		
		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName
		
		if ($NetworkShare.Length -gt 0)
		{
			if ($(Test-SqlPath -SqlServer $Source -Path $NetworkShare) -eq $false)
			{
				throw "$Source cannot access $NetworkShare"
			}
			
			if ($(Test-SqlPath -SqlServer $Destination -Path $NetworkShare) -eq $false)
			{
				throw "$Destination cannot access $NetworkShare"
			}
		}
		
		Invoke-SmoCheck -SqlServer $sourceserver
		Invoke-SmoCheck -SqlServer $destserver
		
		if ($source -eq $destination)
		{
			throw "Source and Destination Sql Servers are the same. Quitting."
		}
		
		if (($All -or $IncludeSupportDbs -or $Databases) -and !$DetachAttach -and !$BackupRestore)
		{
			throw "You must specify -DetachAttach or -BackupRestore when migrating databases."
		}
		
		if ($NetworkShare.Length -gt 0)
		{
			if (!($NetworkShare.StartsWith("\\")))
			{
				throw "Network share must be a valid UNC path (\\server\share)."
			}
			
			if (!(Test-Path $NetworkShare))
			{
				Write-Warning "$networkshare share cannot be accessed. Still trying anyway, in case the SQL Server service accounts have access."
			}
		}
		
		if ($sourceserver.versionMajor -lt 8 -and $destserver.versionMajor -lt 8)
		{
			throw "This script can only be run on Sql Server 2000 and above. Quitting."
		}
		
		if ($destserver.versionMajor -lt 9 -and $DetachAttach)
		{
			throw "Detach/Attach not supported when destination Sql Server is version 2000. Quitting."
		}
		
		if ($sourceserver.versionMajor -lt 9 -and $destserver.versionMajor -gt 10)
		{
			throw "Sql Server 2000 databases cannot be migrated to Sql Server versions 2012 and above. Quitting."
		}
		
		if ($sourceserver.versionMajor -lt 9 -and $Reattach)
		{
			throw "-Reattach was specified, but is not supported in Sql Server 2000. Quitting."
		}
		
		if ($sourceserver.versionMajor -eq 9 -and $destserver.versionMajor -gt 9 -and !$BackupRestore -and !$Force -and $DetachAttach)
		{
			throw "Backup and restore is the safest method for migrating from Sql Server 2005 to other Sql Server versions.
				Please use the -BackupRestore switch or override this requirement by specifying -Force."
		}
		
		if ($sourceserver.collation -ne $destserver.collation)
		{
			Write-Warning "Collation on $Source, $($sourceserver.collation) differs from the $Destination, $($destserver.collation)."
		}
		
	}
	
	PROCESS
	{
		
		<# ----------------------------------------------------------
			Preps
		---------------------------------------------------------- #>
		
		if (($Databases -or $Exclude -or $IncludeSupportDbs) -and (!$DetachAttach -and !$BackupRestore))
		{
			throw "You did not select a migration method. Please use -BackupRestore or -DetachAttach"
		}
		
		if ((!$Databases -and !$All -and !$IncludeSupportDbs) -and ($DetachAttach -or $BackupRestore))
		{
			throw "You did not select any databases to migrate. Please use -All or -Databases or -IncludeSupportDbs"
		}
		
		# SMO's filestreamlevel is sometimes null
		$sql = "select coalesce(SERVERPROPERTY('FilestreamConfiguredLevel'),0) as fs"
		$sourcefilestream = $sourceserver.ConnectionContext.ExecuteScalar($sql)
		$destfilestream = $destserver.ConnectionContext.ExecuteScalar($sql)
		
		if ($sourcefilestream -gt 0 -and $destfilestream -eq 0)
		{
			$fswarning = $true
		}
		
	<# ----------------------------------------------------------
		Run
	---------------------------------------------------------- #>
		$alldbelapsed = [System.Diagnostics.Stopwatch]::StartNew()

		if ($All -or $Exclude.length -gt 0 -or $IncludeSupportDbs -or $Databases.length -gt 0)
		{
			$params = @{
				Sourceserver = $sourceserver
				Destserver = $destserver
				All = $All
				Databases = $Databases
				Exclude = $Exclude
				IncludeSupportDbs = $IncludeSupportDbs
				Force = $force
			}
			
			Copy-SqlDatabase $params
		}
	}
	
	END
	{
		If ($Pscmdlet.ShouldProcess("console", "Showing migration time elapsed"))
		{
			$totaltime = ($elapsed.Elapsed.toString().Split(".")[0])
			$sourceserver.ConnectionContext.Disconnect()
			$destserver.ConnectionContext.Disconnect()
			Write-Output "`nDatabase migration finished"
			Write-Output "Migration started: $started"
			Write-Output "Migration completed: $(Get-Date)"
			Write-Output "Total Elapsed time: $totaltime"
			
			if ($networkshare.length -gt 0 -and $migrateddb.count -gt 0)
			{
				Write-Warning "This script does not delete backup files. Backups still exist at $networkshare."
			}
		}
	}
}