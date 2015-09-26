Function Copy-SqlDatabase {
<# 
.SYNOPSIS 
Migrates Sql Server databases, logins, Sql Agent objects, and global configuration settings from one Sql Server to another.

.DESCRIPTION 
This script provides the ability to migrate databases using detach/copy/attach or backup/restore. Sql Server logins, including passwords, SID and database/server roles can also be migrated. In addition, job server objects can be migrated and server configuration settings can be exported or migrated. This script works with named instances, clusters and Sql Express.

By default, databases will be migrated to the destination Sql Server's default data and log directories. You can override this by specifying -ReuseFolderStructure. Filestreams and filegroups are also migrated. Safety is emphasized.

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

.PARAMETER Source
Source Sql Server. You must have sysadmin access and server version must be > Sql Server 7.

.PARAMETER Destination
Destination Sql Server. You must have sysadmin access and server version must be > Sql Server 7.

.PARAMETER SourceSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, this pass $scred object to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.PARAMETER DestinationSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$dcred = Get-Credential, this pass this $dcred to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.PARAMETER All
Migrates user databases. Does not migrate system or support databases. A logfile named $SOURCE-$DESTINATION-$date-logins.csv will be written to the current directory. Requires -BackupRestore or -DetachAttach. Talk about database structure.

.PARAMETER IncludeSupportDbs
Migration of ReportServer, ReportServerTempDb, SSIDb, and distribution databases if they exist. A logfile named $SOURCE-$DESTINATION-$date-Sqls.csv will be written to the current directory. Requires -BackupRestore or -DetachAttach.

.PARAMETER BackupRestore
Use the a Copy-Only Backup and Restore Method. This parameter requires that you specify -NetworkShare in a valid UNC format (\\server\share)

.PARAMETER DetachAttach
Uses the detach/copy/attach method to perform database migrations. No files are deleted on the source. If the destination attachment fails, the source database will be reattached. File copies are performed over administrative shares (\\server\x$\mssql) using BITS. If a database is being mirrored, the mirror will be broken prior to migration. 

.PARAMETER Reattach
Reattaches all source databases after DetachAttach migration.

.PARAMETER ReuseFolderStructure
By default, databases will be migrated to the destination Sql Server's default data and log directories. You can override this by specifying -ReuseFolderStructure. The same structure will be kept exactly, so consider this if you're migrating between different versions and use part of Microsoft's default Sql structure (MSSql12.INSTANCE, etc)

.PARAMETER NetworkShare
Specifies the network location for the backup files. The Sql Service service accounts must read/write permission to access this location.

.PARAMETER Exclude
Excludes specified databases when performing -All migrations. This list is auto-populated for tab completion.

.PARAMETER Databases
Migrates ONLY specified databases. This list is auto-populated for tab completion.

.PARAMETER SetSourceReadOnly
Sets all migrated databases to ReadOnly prior to detach/attach & backup/restore. If -Reattach is used, db is set to read-only after reattach.


.PARAMETER Force
If migrating databases, deletes existing databases with matching names. 
If using -DetachAttach, -Force will break mirrors and drop dbs from Availability Groups.
MigrateJobServer not supported.

.NOTES 
Author  : Chrissy LeMaire
Requires: PowerShell Version 3.0, Sql Server SMO
DateUpdated: 2015-Aug-5
Version: 2.0
Limitations: 	Doesn't cover what it doesn't cover (replication, linked servers, certificates, etc)
		Sql Server 2000 login migrations have some limitations (server perms aren't migrated, etc)
		Sql Server 2000 databases cannot be directly migrated to Sql Server 2012 and above.
		Logins within Sql Server 2012 and above logins cannot be migrated to Sql Server 2008 R2 and below.				

.LINK 
https://gallery.technet.microsoft.com/scriptcenter/Use-PowerShell-to-Migrate-86c841df/

.EXAMPLE   
Copy-SqlDatabase -Source sqlserver\instance -Destination sqlcluster -DetachAttach -Everything

Description

All databases, logins, job objects and sp_configure options will be migrated from sqlserver\instance to sqlcluster. Databases will be migrated using the detach/copy files/attach method. Dbowner will be updated. User passwords, SIDs, database roles and server roles will be migrated along with the login.

.EXAMPLE   
Copy-SqlDatabase -Source sqlserver\instance -Destination sqlcluster -All -Exclude Northwind, pubs -IncludeSupportDbs -force -AllLogins -Exclude nwuser, pubsuser, "corp\domain admins"  -MigrateJobServer -ExportSPconfigure -SourceSqlCredential -DestinationSqlCredential

Description

Prompts for Sql login usernames and passwords on both the Source and Destination then connects to each using the Sql Login credentials. 

All logins except for nwuser, pubsuser and the corp\domain admins group will be migrated from sqlserver\instance to sqlcluster, along with their passwords, server roles and database roles. A logfile named SqlSERVER-SqlCLUSTER-$date-logins.csv will be written to the current directory. Existing Sql users will be dropped and recreated.

Migrates all user databases except for Northwind and pubs by performing the following: kick all users out of the database, detach all data/log files, move files across the network over an admin share (\\SqlSERVER\M$\MSSql...), attach file on destination server. If the database exists on the destination, it will be dropped prior to attach.

It also includes the support databases (ReportServer, ReportServerTempDb, SSIDb, distribution). 

If the database files (*.mdf, *.ndf, *.ldf) on SqlCLUSTER exist and aren't in use, they will be overwritten. A logfile named SqlSERVER-SqlCLUSTER-$date-Sqls.csv will be written to the current directory.

All job server objects will be migrated. A logfile named SqlSERVER-SqlCLUSTER-$date-jobs.csv will be written to the current directory.

A file named SqlSERVER-SqlCluster-$date-sp_configure.sql with global server configurations will be written to the current directory. This file can then be executed manually on SqlCLUSTER.
#> 
[CmdletBinding(DefaultParameterSetName="DbMigration", SupportsShouldProcess = $true)] 

Param(
	# Source Sql Server
	[parameter(Mandatory = $true)]
	[object]$Source,
	
	# Destination Sql Server
	[parameter(Mandatory = $true)]
	[object]$Destination,
	
	# Database Migration
	[Parameter(Mandatory = $true, ParameterSetName="DbAttachDetach")]
	[switch]$DetachAttach,
	[Parameter(Mandatory = $true,ParameterSetName="DbBackup")]
	[switch]$BackupRestore,
	
	[Parameter(ParameterSetName="DbBackup")]
	[Parameter(ParameterSetName="DbAttachDetach")]
	[switch]$ReuseFolderstructure,
	
	[Parameter(ParameterSetName="DbBackup")]
	[Parameter(ParameterSetName="DbAttachDetach")]
	[switch]$All,
	
	[Parameter(ParameterSetName="DbBackup")]
	[Parameter(ParameterSetName="DbAttachDetach")]
	[switch]$IncludeSupportDbs,
	
	[Parameter(ParameterSetName="DbAttachDetach")]
	[switch]$Reattach,
	
	[Parameter(Mandatory=$true, ParameterSetName="DbBackup",
		HelpMessage="Specify a valid network share in the format \\server\share that can be accessed by your account and both Sql Server service accounts.")]
	[string]$NetworkShare,
	
	[Parameter(ParameterSetName="DbBackup")]
	[Parameter(ParameterSetName="DbAttachDetach")]
	[switch]$SetSourceReadOnly,

	# The rest
	[switch]$NoRecovery = $false,
	[switch]$Force,
	[System.Management.Automation.PSCredential]$SourceSqlCredential,
	[System.Management.Automation.PSCredential]$DestinationSqlCredential
	
	)

	DynamicParam  { if ($source) { return Get-ParamSqlDatabases -SqlServer $source -SqlCredential $SourceSqlCredential } }

BEGIN {

# Global Database Function
Function Get-SqlFileStructures {
 <#
            .SYNOPSIS
             Custom object that contains file structures and remote paths (\\sqlserver\m$\mssql\etc\etc\file.mdf) for
			 source and destination servers.
			
            .EXAMPLE
            $filestructure = Get-SqlFileStructures $sourceserver $destserver $ReuseFolderstructure
			foreach	($file in $filestructure.databases[$dbname].destination.values) {
				Write-Output $file.physical
				Write-Output $file.logical
				Write-Output $file.remotepath
			}

            .OUTPUTS
             Custom object 
        #>
		[CmdletBinding()]
        param(
			[Parameter(Mandatory = $true,Position=0)]
			[ValidateNotNullOrEmpty()]
			[object]$sourceserver,
			
			[Parameter(Mandatory = $true,Position=1)]
			[ValidateNotNullOrEmpty()]
			[object]$destserver,
			
			[Parameter(Mandatory = $false,Position=2)]
			[bool]$ReuseFolderstructure
		)

	$sourcenetbios = Get-NetBIOSName $sourceserver
	$destnetbios = Get-NetBIOSName $destserver
	
	$dbcollection = @{}; 
	
		foreach ($db in $sourceserver.databases) {
			$dbstatus = $db.status.toString()
			if ($dbstatus.StartsWith("Normal") -eq $false) { continue }
			$destinationfiles = @{}; $sourcefiles = @{}
			
			# Data Files
			foreach ($filegroup in $db.filegroups) {
				foreach ($file in $filegroup.files) {
					# Destination File Structure
					$d = @{}
					if ($ReuseFolderstructure) {
						$d.physical = $file.filename
					} else {
						$directory = Get-SqlDefaultPaths $destserver data
						$filename = Split-Path $($file.filename) -leaf		
						$d.physical = "$directory\$filename"
					}
					$d.logical = $file.name
					$d.remotefilename = Join-AdminUNC $destnetbios $d.physical
					$destinationfiles.add($file.name,$d)
					
					# Source File Structure
					$s = @{}
					$s.logical = $file.name
					$s.physical = $file.filename
					$s.remotefilename = Join-AdminUNC $sourcenetbios $s.physical
					$sourcefiles.add($file.name,$s)
				}
			}
			
			# Add support for Full Text Catalogs in Sql Server 2005 and below
			if ($sourceserver.VersionMajor -lt 10) {
				foreach ($ftc in $db.FullTextCatalogs) {
					# Destination File Structure
					$d = @{}
					$pre = "sysft_"
					$name = $ftc.name
					$physical = $ftc.RootPath
					$logical = "$pre$name"
					if ($ReuseFolderstructure) {
						$d.physical = $physical
					} else {
						$directory = Get-SqlDefaultPaths $destserver data
						if ($destserver.VersionMajor -lt 10) { $directory = "$directory\FTDATA" }
						$filename = Split-Path($physical) -leaf	
						$d.physical = "$directory\$filename"
					}
					$d.logical = $logical
					$d.remotefilename = Join-AdminUNC $destnetbios $d.physical
					$destinationfiles.add($logical,$d)
					
					# Source File Structure
					$s = @{}
					$pre = "sysft_"
					$name = $ftc.name
					$physical = $ftc.RootPath
					$logical = "$pre$name"
					
					$s.logical = $logical
					$s.physical = $physical
					$s.remotefilename = Join-AdminUNC $sourcenetbios $s.physical
					$sourcefiles.add($logical,$s)
				}
			}

			# Log Files
			foreach ($file in $db.logfiles) {
				$d = @{}
				if ($ReuseFolderstructure) {
					$d.physical = $file.filename
				} else {
					$directory = Get-SqlDefaultPaths $destserver log
					$filename = Split-Path $($file.filename) -leaf		
					$d.physical = "$directory\$filename"
				}
				$d.logical = $file.name
				$d.remotefilename = Join-AdminUNC $destnetbios $d.physical
				$destinationfiles.add($file.name,$d)
				
				$s = @{}
				$s.logical = $file.name
				$s.physical = $file.filename
				$s.remotefilename = Join-AdminUNC $sourcenetbios $s.physical
				$sourcefiles.add($file.name,$s)
			}
			
		$location = @{}
		$location.add("Destination",$destinationfiles)
		$location.add("Source",$sourcefiles)	
		$dbcollection.Add($($db.name),$location)
		}
		
	$filestructure = [pscustomobject]@{"databases" = $dbcollection}
	return $filestructure
}

# Backup Restore
Function Backup-SqlDatabase {
        <#
            .SYNOPSIS
             Makes a full database backup of a database to a specified directory. $server is an SMO server object.

            .EXAMPLE
             Backup-SqlDatabase $smoserver $dbname \\fileserver\share\sql\database.bak

            .OUTPUTS
                $true if success
                $false if failure
        #>
		[CmdletBinding()]
        param(
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
	
	$percent = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] { 
		Write-Progress -id 1 -activity "Backing up database $dbname to $backupfile" -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent)) 
	}
	$backup.add_PercentComplete($percent)
	$backup.add_Complete($complete)
	 
	Write-Progress -id 1 -activity "Backing up database $dbname to $backupfile" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
	Write-Output "Backing up $dbname"

	try { 
		$backup.SqlBackup($server)
		Write-Progress -id 1 -activity "Backing up database $dbname to $backupfile" -status "Complete" -Completed
		Write-Output "Backup succeeded"
		return $true
		}
	catch {
		Write-Progress -id 1 -activity "Backup" -status "Failed" -completed
		return $false 
	}
}

Function Restore-SqlDatabase {
        <#
            .SYNOPSIS
             Restores .bak file to Sql database. Creates db if it doesn't exist. $filestructure is
			a custom object that contains logical and physical file locations.

            .EXAMPLE
			 $filestructure = Get-SqlFileStructures $sourceserver $destserver $ReuseFolderstructure
             Restore-SqlDatabase $destserver $dbname $backupfile $filestructure   

            .OUTPUTS
                $true if success
                $true if failure
        #>
		[CmdletBinding()]
        param(
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
	
	foreach	($file in $filestructure.databases[$dbname].destination.values) {
		$movefile = New-Object "Microsoft.SqlServer.Management.Smo.RelocateFile" 
		$movefile.LogicalFileName = $file.logical
		$movefile.PhysicalFileName = $file.physical
		$null = $restore.RelocateFiles.Add($movefile)
	}
	
	Write-Output "Restoring $dbname to $servername"
	
	try {
		
		$percent = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] { 
			Write-Progress -id 1 -activity "Restoring $dbname to $servername" -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent)) 
		}
		$restore.add_PercentComplete($percent)
		$restore.PercentCompleteNotification = 1
		$restore.add_Complete($complete)
		$restore.ReplaceDatabase = $true
		$restore.Database = $dbname
		$restore.Action = "Database"
		$restore.NoRecovery = $false
		$device = New-Object -TypeName Microsoft.SqlServer.Management.Smo.BackupDeviceItem
		$device.name = $backupfile
		$device.devicetype = "File"
		$restore.Devices.Add($device)
		
		Write-Progress -id 1 -activity "Restoring $dbname to $servername" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
		$restore.sqlrestore($server)
		Write-Progress -id 1 -activity "Restoring $dbname to $servername" -status "Complete" -Completed
		
		return $true
	} catch { 
		write-warning "Restore failed: $($_.Exception.InnerException.Message)"
		return $false	
	}
}

Function Start-SqlBackupRestore  {
 <#
            .SYNOPSIS
             Performs checks, then executes Backup-SqlDatabase to a fileshare and then a subsequential Restore-SqlDatabase.

            .EXAMPLE
              Start-SqlBackupRestore $sourceserver $destserver $dbname $networkshare $force  

            .OUTPUTS
                $true if successful
                error string if failure
			
        #>
		[CmdletBinding()]
        param(
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[object]$sourceserver,
			
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[object]$destserver,
			
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[string]$dbname,
			
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[ValidateScript({ Test-Path $_ })]
			[string]$networkshare,
			
			[Parameter()]
            [bool]$force	
		)
		
	$filestructure = Get-SqlFileStructures $sourceserver $destserver $ReuseFolderstructure
	$filename = "$dbname-$timenow.bak"
	$backupfile = Join-Path $networkshare $filename
	
	$backupresult = Backup-SqlDatabase $sourceserver $dbname $backupfile
	
	if ($backupresult) {
	$restoreresult = Restore-SqlDatabase $destserver $dbname $backupfile $filestructure
		
		if ($restoreresult) {
			# RESTORE was successful
			Write-Output "Successfully restored $dbname to $destination"
			return $true

		} else {
			# RESTORE was unsuccessful
			if ($ReuseFolderStructure) {
				Write-Error "Failed to restore $dbname to $destination. You specified -ReuseFolderStructure. Does the exact same destination directory structure exist?"
				return "Failed to restore $dbname to $destination using ReuseFolderStructure."
			}
			else {
				Write-Error "Failed to restore $dbname to $destination"
				return "Failed to restore $dbname to $destination."
			}
		}
		
	} else {
		# add to failed because BACKUP was unsuccessful
		Write-Error "Backup Failed. Does Sql Server account ($($sourceserver.ServiceAccount)) have access to $($NetworkShare)?"
		return "Backup Failed. Does Sql Server account ($($sourceserver.ServiceAccount)) have access to $NetworkShare` and does the fileshare have space?"	
	}
}

# Detach Attach 
Function Dismount-SqlDatabase {
 <#
            .SYNOPSIS
             Detaches a Sql Server database. $server is an SMO server object.   

            .EXAMPLE
             $detachresult = Dismount-SqlDatabase $server $dbname   

            .OUTPUTS
                $true if success
                $false if failure

        #>
		[CmdletBinding()]
        param(
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[object]$server,
			
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[string]$dbname
			
		)

	$database = $server.databases[$dbname]
	if ($database.IsMirroringEnabled) {
		try {
			Write-Warning "Breaking mirror for $dbname"
			$database.ChangeMirroringState([Microsoft.SqlServer.Management.Smo.MirroringOption]::Off)
			$database.Alter()
			$database.Refresh()		
			Write-Warning "Could not break mirror for $dbname. Skipping."
			
		} catch { return $false }
	}
	
	if ($database.AvailabilityGroupName.Length -gt 0 ) {
		$agname = $database.AvailabilityGroupName
		Write-Output "Attempting remove from Availability Group $agname" 
		try {
			$server.AvailabilityGroups[$database.AvailabilityGroupName].AvailabilityDatabases[$dbname].Drop()
			Write-Output "Successfully removed $dbname from  detach from $agname on $($server.name)" 
		} catch { Write-Error "Could not remove $dbname from $agname on $($server.name)"; return $false }
	}
	
	Write-Output "Attempting detach from $dbname from $source" 
	
	####### Using Sql to detach does not modify the $database collection #######
	$sql = "ALTER DATABASE [$dbname] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;EXEC master.dbo.sp_detach_db N'$dbname'"
	try { 
		$null = $server.ConnectionContext.ExecuteNonQuery($sql)
		Write-Output "Successfully detached $dbname from $source" 
		return $true
	} 
	catch { return $false }
}

Function Copy-SqlDatabase  {
 <#
            .SYNOPSIS
              Performs tons of checks then migrates the databases.

            .EXAMPLE
                Copy-SqlDatabase $sourceserver $destserver $All $Databases $Exclude $IncludeSupportDBs $force

            .OUTPUTS
              CSV files and informational messages.
			
        #>
		[cmdletbinding(SupportsShouldProcess = $true)] 
        param(
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[object]$sourceserver,
			
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [object]$destserver,

			[Parameter()]
            [bool]$All,
			
			[Parameter()]
            [string[]]$Databases,
			
			[Parameter()]
            [string[]]$Exclude,

			[Parameter()]
            [string]
			$IncludeSupportDBs,
			
			[Parameter()]
			[bool]$force
			
		) 

	<# ###############################################################
	
							Server Checks
		
	############################################################### #>

	$alldbelapsed = [System.Diagnostics.Stopwatch]::StartNew() 
	if ($sourceserver.Databases.count -le 4) { throw "No user databases to migrate. Quitting." }
	
	if ([version]$sourceserver.ResourceVersionString -gt [version]$destserver.ResourceVersionString) {
		throw "Source Sql Server version build must be <= destination Sql Server for database migration."
	}
	if ($fswarning) { Write-Warning "FILESTREAM enabled on $source but not $destination. Databases that use FILESTREAM will be skipped."  }

	Write-Output "Checking access to remote directories..."
	Write-Output "Resolving NetBIOS name for $source..."
	$sourcenetbios = Get-NetBIOSName $sourceserver
	Write-Output "Resolving NetBIOS name for $destination..."
	$destnetbios = Get-NetBIOSName $destserver
	$remotesourcepath = Join-AdminUNC $sourcenetbios (Get-SqlDefaultPaths $sourceserver data)
	
	If ((Test-Path $remotesourcepath) -ne $true) { 
		Write-Error "Can't access remote Sql directories on $source."
		Write-Error "You can manually try accessing $remotesourcepath to diagnose any issues."
		Write-Error "Halting database migration."
		return 
	}
	
	
	$remotedestpath = Join-AdminUNC $destnetbios (Get-SqlDefaultPaths $destserver data)
	If ((Test-Path $remotedestpath) -ne $true) {
		Write-Error "Can't access remote Sql directories on $destination."
		Write-Error "You can manually try accessing $remotedestpath to diagnose any issues."
		Write-Error "Halting database migration."
		return 
	}
	
	##################################################################
	
	$SupportDBs = "ReportServer","ReportServerTempDB", "distribution"
	$sa = $changedbowner
	
	$timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
	$csvfilename = "$($sourceserver.name.replace('\','$'))-to-$($destserver.name.replace('\','$'))-$timenow"
	
	$migrateddb = @{}; $skippedb = @{}
	$Exclude | Where-Object {!([string]::IsNullOrEmpty($_))} | ForEach-Object { $skippedb.Add($_,"Explicitly Skipped") }
	
	$filestructure = Get-SqlFileStructures $sourceserver $destserver $ReuseFolderstructure
	Set-Content -Path "$csvfilename-db.csv" "Database Name, Result, Start, Finish"
	
	foreach ($database in $sourceserver.databases) {
		$dbelapsed = [System.Diagnostics.Stopwatch]::StartNew() 
		$dbname = $database.name
		$dbowner = $database.Owner
		
		
		<# ###############################################################
		
							Database Checks
			
		############################################################### #>
		
		if ($database.id -le 4) { continue }
		if ($Databases -and $Databases -notcontains $dbname) { continue }
		if ($IncludeSupportDBs -eq $false -and $SupportDBs -contains $dbname) { continue }
		
		if ($IncludeSupportDBs -eq $true -and $SupportDBs -notcontains $dbname) {
			if ($All -eq $false -and $Databases.length -eq 0) { continue }
		}
		
		Write-Output "`n######### Database: $dbname #########"
		$dbstart = Get-Date
		
		if ($skippedb.ContainsKey($dbname) -and $Databases -eq $null) {
			Write-Output "`nSkipping $dbname"
			continue 
		}

		if ($database.IsAccessible -eq $false) { 
			Write-Warning "Skipping $dbname. Database is inaccessible."
			$skippedb.Add($dbname,"Skipped. Database is inaccessible.")
			continue
		}
		
		if ($fswarning -and ($database.FileGroups | Where { $_.isFilestream }) -ne $null) {
			Write-Warning "Skipping $dbname (contains FILESTREAM)"
			$skippedb.Add($dbname,"Skipped. Database contains FILESTREAM and FILESTREAM is disabled on $destination.")
			continue
		}
		
		if ($ReuseFolderstructure) {
			$remotepath = Split-Path ($database.FileGroups[0].Files.FileName)
			$remotepath = Join-AdminUNC $destnetbios $remotepath

			if (!(Test-Path $remotepath)) { throw "Cannot resolve $remotepath. `n`nYou have specified ReuseFolderstructure and exact folder structure does not exist. Halting script." }
		}
		
		if ($database.AvailabilityGroupName.Length -gt 0 -and !$force -and $DetachAttach) {
			$agname = $database.AvailabilityGroupName
			Write-Warning "Database is part of an Availability Group ($agname). Use -Force to drop from $agname and migrate. Alternatively, you can use the safer backup/restore method."
			$skippedb[$dbname] = "Database is part of an Availability Group ($agname) and -force was not specified. Skipped."
			continue 
		}
		
		if ($database.IsMirroringEnabled -and !$force -and $DetachAttach) {
			Write-Warning "Database is being mirrored. Use -Force to break mirror and migrate. Alternatively, you can use the safer backup/restore method."
			$skippedb[$dbname] = "Database is being mirrored and -force was not specified. Skipped."
			continue 
		}
		
		if ($destserver.Databases[$dbname] -ne $null -and !$force) {
				Write-Warning "Database exists at destination. Use -Force to drop and migrate."
				$skippedb[$dbname] = "Database exists at destination. Use -Force to drop and migrate."
				continue 
		} 
		elseif ($destserver.Databases[$dbname] -ne $null -and $force) {		
				If ($Pscmdlet.ShouldProcess($destination,"DROP DATABASE $dbname")) {
					Write-Output "$dbname already exists. -Force was specified. Dropping $dbname on $destination."
					$dropresult = Remove-SqlDatabase $destserver $dbname
					if (!$dropresult) { $skippedb[$dbname] = "Database exists and could not be dropped."; continue }
				}
		}
		
		
		If ($Pscmdlet.ShouldProcess("local host","Showing start time")) {
			Write-Output "Started: $dbstart"
		}
		
		if ($sourceserver.versionMajor -ge 9) {
			$sourcedbownerchaining = $sourceserver.databases[$dbname].DatabaseOwnershipChaining
			$sourcedbtrustworthy = $sourceserver.databases[$dbname].Trustworthy
			$sourcedbbrokerenabled = $sourceserver.databases[$dbname].BrokerEnabled
			
		}
		
		$sourcedbreadonly = $sourceserver.Databases[$dbname].ReadOnly
		
		if ($SetSourceReadOnly) { 
			If ($Pscmdlet.ShouldProcess($source,"Set $dbname to read-only")) {	
				$result = Update-SqldbReadOnly $sourceserver $dbname $true
			}
		}
				
		if ($BackupRestore) {
			If ($Pscmdlet.ShouldProcess($destination,"Backup $dbname from $source and restoring.")) {
				$result = (Start-SqlBackupRestore $sourceserver $destserver $dbname $networkshare $force)
				$dbfinish = Get-Date					
				if ($result -eq $true) {
					$migrateddb.Add($dbname,"Successfully migrated,$dbstart,$dbfinish")
					Add-Content -Path "$csvfilename-db.csv" "$dbname,Successfully migrated,$dbstart,$dbfinish"
					$result = Update-Sqldbowner $sourceserver $destserver -dbname $dbname
					If ($result) {
						Add-Content -Path "$csvfilename-dbowner.csv" "$dbname,$dbowner"
					}
				} else { 
					$skippedb[$dbname] = $result
					Add-Content -Path "$csvfilename-db.csv" "$dbname,Migration failed - $result,$dbstart,$dbfinish"
				}
			}
		} # End of backup
		
		elseif ($DetachAttach) { 
			$sourcefilestructure = New-Object System.Collections.Specialized.StringCollection
			foreach	($file in $filestructure.databases[$dbname].source.values) {$null = $sourcefilestructure.add($file.physical) }
			
			$dbowner = $sourceserver.databases[$dbname].owner; if ($dbowner -eq $null) { $dbowner = "sa" }
			
			If ($Pscmdlet.ShouldProcess($destination,"Detach $dbname from $source and attach, then update dbowner")) {
				$result = Start-SqlDetachAttach $sourceserver $destserver $filestructure $dbname $force
				$dbfinish = Get-Date
				if ($result -eq $true) {
					$migrateddb.Add($dbname,"Successfully migrated,$dbstart,$dbfinish")
					Add-Content -Path "$csvfilename-db.csv" "$dbname,Successfully migrated,$dbstart,$dbfinish"
					$result = Update-Sqldbowner $sourceserver $destserver -dbname $dbname
					
					If ($result) {
						Add-Content -Path "$csvfilename-dbowner.csv" "$dbname,$dbowner" 
					}
				} else { 
					$skippedb[$dbname] = $result
					Add-Content -Path "$csvfilename-db.csv" "$dbname,Migration failed - $result,$dbstart,$dbfinish"
				}
				
				if ($Reattach) {
					$null = ($sourceserver.databases).Refresh() 
					$result = Mount-SqlDatabase $sourceserver $dbname $sourcefilestructure $dbowner
					if ($result -eq $true) {
						$sourceserver.databases[$dbname].DatabaseOwnershipChaining = $sourcedbownerchaining 
						$sourceserver.databases[$dbname].Trustworthy = $sourcedbtrustworthy
						$sourceserver.databases[$dbname].BrokerEnabled = $sourcedbbrokerenabled
						$sourceserver.databases[$dbname].alter()
						if ($SetSourceReadOnly) { 
							$null = Update-SqldbReadOnly $sourceserver $dbname $true 
						} else { $null = Update-SqldbReadOnly $sourceserver $dbname $sourcedbreadonly }
						Write-Output "Successfully reattached $dbname to $source"
						
					} 
					else { Write-Warning "Could not reattach $dbname to $source." }
				}
			}
		} #end of if detach/backup
		
		# restore poentially lost settings
		
		if ($destserver.versionMajor -ge 9) {
		
			if ($sourcedbownerchaining -ne $destserver.databases[$dbname].DatabaseOwnershipChaining ) {
				If ($Pscmdlet.ShouldProcess($destination,"Updating DatabaseOwnershipChaining on $dbname")) {
					try {
						$destserver.databases[$dbname].DatabaseOwnershipChaining = $sourcedbownerchaining 
						$destserver.databases[$dbname].alter()
						Write-Output "Successfully updated DatabaseOwnershipChaining for $sourcedbownerchaining on $dbname on $destination"
					} catch { Write-Error "Failed to update DatabaseOwnershipChaining for $sourcedbownerchaining on $dbname on $destination" }
				}
			}
			
			if ($sourcedbtrustworthy -ne $destserver.databases[$dbname].Trustworthy ) {
				If ($Pscmdlet.ShouldProcess($destination,"Updating Trustworthy on $dbname")) {
					try {
						$destserver.databases[$dbname].Trustworthy = $sourcedbtrustworthy
						$destserver.databases[$dbname].alter()
						Write-Output "Successfully updated Trustworthy to $sourcedbtrustworthy for $dbname on $destination"
					} catch { Write-Error "Failed to update Trustworthy to $sourcedbtrustworthy for $dbname on $destination" }
				}
			}
			
			if ($sourcedbbrokerenabled -ne $destserver.databases[$dbname].BrokerEnabled ) {
				If ($Pscmdlet.ShouldProcess($destination,"Updating BrokerEnabled on $dbname")) {
					try {
						$destserver.databases[$dbname].BrokerEnabled = $sourcedbbrokerenabled
						$destserver.databases[$dbname].alter()
						Write-Output "Successfully updated BrokerEnabled to $sourcedbbrokerenabled for $dbname on $destination"
					} catch { Write-Error "Failed to update BrokerEnabled to $sourcedbbrokerenabled for $dbname on $destination" }
				}
			}
		}
		
		if ($sourcedbreadonly -ne $destserver.databases[$dbname].ReadOnly ) {
			If ($Pscmdlet.ShouldProcess($destination,"Updating ReadOnly status on $dbname")) {
				try {
					$result = Update-SqldbReadOnly $destserver $dbname $sourcedbreadonly
				} catch { Write-Error "Failed to update ReadOnly status on $dbname" }
			}
		}
	
	If ($Pscmdlet.ShouldProcess("local host","Showing elapsed time")) {
		$dbtotaltime=$dbfinish-$dbstart
		$dbtotaltime = ($dbtotaltime.toString().Split(".")[0])

		Write-Output "Finished: $dbfinish"
		Write-Output "Elapsed time: $dbtotaltime"
	}
	
	} # end db by db processing
	
	$alldbtotaltime = ($alldbelapsed.Elapsed.toString().Split(".")[0])
	Add-Content -Path "$csvfilename-db.csv" "`r`nElapsed time,$alldbtotaltime"
	if ($migrateddb.count -eq 0) { 
		If (Test-Path "$csvfilename-db.csv") { Remove-Item -Path "$csvfilename-db.csv" }
	}
	$migrateddb.GetEnumerator() | Sort-Object Value; $skippedb.GetEnumerator() | Sort-Object Value
	Write-Output "`nCompleted database migration"
}

Function Mount-SqlDatabase {
	 <#
		SYNOPSIS
		 Attaches a Sql Server database, and sets its owner. $server is an SMO server object.

		.EXAMPLE
		 Mount-SqlDatabase $destserver $dbname $destfilestructure $dbowner

		.OUTPUTS
			$true if success
			$false if failure	
				
	#>
		[CmdletBinding()]
        param(
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
	try {
		$null = $server.AttachDatabase($dbname, $filestructure, $dbowner, [Microsoft.SqlServer.Management.Smo.AttachOptions]::None)
		return $true
	} catch { return $false  }
}

Function Start-SqlFileTransfer  {
 <#
	SYNOPSIS
	Uses BITS to transfer detached files (.mdf, .ndf, .ldf, and filegroups) to 
	another server over admin UNC paths. Locations of data files are kept in the
	custom object generated by Get-SqlFileStructure

	.EXAMPLE
	 $result = Start-SqlFileTransfer $filestructure $dbname

	.OUTPUTS
		$true if success
		$false if failure	
			
#>	
        param(
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [object]$filestructure,
	
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [string]$dbname
		)

$copydb = $filestructure.databases[$dbname]
$dbsource = $copydb.source
$dbdestination = $copydb.destination

	foreach ($file in $dbsource.keys) 
	{
		$remotefilename = $dbdestination[$file].remotefilename
		$from = $dbsource[$file].remotefilename
		try {
			if (Test-Path $from -pathtype container) {
				$null = New-Item -ItemType Directory -Path $remotefilename -Force
				Start-BitsTransfer -Source "$from\*.*" -Destination $remotefilename
				
				$directories = (Get-ChildItem -recurse $from | where {$_.PsIsContainer}).FullName
				foreach ($directory in $directories) {
					$newdirectory = $directory.replace($from,$remotefilename)
					$null = New-Item -ItemType Directory -Path $newdirectory -Force
					Start-BitsTransfer -Source "$directory\*.*" -Destination $newdirectory
				}
			}
			else {
			Start-BitsTransfer -Source $from -Destination $remotefilename }
			$fn = Split-Path $($dbdestination[$file].physical) -leaf
			Write-Output "Copied $fn for $dbname"
		} catch { return $false }
	}
	return $true
}

Function Start-SqlDetachAttach   {
 <#
            .SYNOPSIS
             Performs checks, then executes Dismount-SqlDatabase on a database, copies its files to the new server, 
			 then performs Mount-SqlDatabase. $sourceserver and $destserver are SMO server objects.
			 $filestructure is a custom object generated by Get-SqlFileStructures

            .EXAMPLE
              result = Start-SqlDetachAttach $sourceserver $destserver $filestructure $dbname $force

            .OUTPUTS
                $true if successful
                error string if failure
			
        #>
		[CmdletBinding()]
        param(
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[object]$sourceserver,
			
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[object]$destserver,
			
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[object]$filestructure,
			
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[string]$dbname,
			
			[Parameter()]
            [bool]$force
		)

	$destfilestructure = New-Object System.Collections.Specialized.StringCollection
	$sourcefilestructure = New-Object System.Collections.Specialized.StringCollection
	$dbowner = $sourceserver.databases[$dbname].owner; if ($dbowner -eq $null) { $dbowner = 'sa' }
	
	foreach	($file in $filestructure.databases[$dbname].destination.values) {$null = $destfilestructure.add($file.physical) }
	foreach	($file in $filestructure.databases[$dbname].source.values) {$null = $sourcefilestructure.add($file.physical) }
	
	$detachresult =	Dismount-SqlDatabase $sourceserver $dbname
	
	if ($detachresult) {
	
		$transfer = Start-SqlFileTransfer $filestructure $dbname	
		if ($transfer -eq $false) { Write-Warning "Could not copy files."; return "Could not copy files." }	
		$attachresult = Mount-SqlDatabase $destserver $dbname $destfilestructure $dbowner

		if ($attachresult -eq $true) {
			# add to added dbs because ATTACH was successful
			Write-Output "Successfully attached $dbname to $destination"
			return $true
		} else {
			# add to failed because ATTACH was unsuccessful
			Write-Warning "Could not attach $dbname."
			return "Could not attach database."
		}
	}
	else {
		# add to failed because DETACH was unsuccessful
		Write-Warning "Could not detach $dbname."
		return "Could not detach database."
	}
}


}

PROCESS {
	$elapsed = [System.Diagnostics.Stopwatch]::StartNew() 
	$started = Get-Date
	
	Write-Output "Attempting to connect to Sql Servers.." 
	$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
	$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential

	$source = $sourceserver.name
	$destination = $destserver.name
	
	if ($source -eq $destination) { throw "Source and Destination Sql Servers are the same. Quitting." }

	# Convert from RuntimeDefinedParameter object to regular array
	$Databases = $psboundparameters.Databases
	$Exclude = $psboundparameters.Exclude
	
	if (($All -or $IncludeSupportDbs -or $Databases) -and !$DetachAttach -and !$BackupRestore) {
      throw "You must specify -DetachAttach or -BackupRestore when migrating databases."
    }

	if ($NetworkShare.Length -gt 0) {
		if (!($NetworkShare.StartsWith("\\"))) {
			throw "Network share must be a valid UNC path (\\server\share)." 
		}
		
		if (!(Test-Path $NetworkShare)) {
			throw "Specified network share does not exist or cannot be accessed." 
		}
	}
	
	if (!(Test-SqlSa -SqlServer $sourceserver -SqlCredential $SourceSqlCredential)) { throw "Not a sysadmin on $source. Quitting." }
	if (!(Test-SqlSa -SqlServer $destserver -SqlCredential $DestinationSqlCredential)) { throw "Not a sysadmin on $destination. Quitting." }

	if ($sourceserver.versionMajor -lt 8 -and $destserver.versionMajor -lt 8) {
		throw "This script can only be run on Sql Server 2000 and above. Quitting." 
	}
	
	if ($destserver.versionMajor -lt 9 -and $DetachAttach) {
		throw "Detach/Attach not supported when destination Sql Server is version 2000. Quitting." 
	}
	if ($sourceserver.versionMajor -lt 9 -and $destserver.versionMajor -gt 10) {
		throw "Sql Server 2000 databases cannot be migrated to Sql Server versions 2012 and above. Quitting." 
	}
	if ($sourceserver.versionMajor -lt 9 -and $Reattach) { 
		throw "-Reattach was specified, but is not supported in Sql Server 2000. Quitting."
	}
	if ($sourceserver.versionMajor -eq 9 -and $destserver.versionMajor -gt 9 -and !$BackupRestore -and !$Force -and $DetachAttach)  {
		throw "Backup and restore is the safest method for migrating from Sql Server 2005 to other Sql Server versions.
		Please use the -BackupRestore switch or override this requirement by specifying -Force." 
	}
		
	<# ----------------------------------------------------------
		Preps
	---------------------------------------------------------- #>

	if (($Databases -or $Exclude -or $IncludeSupportDbs) -and (!$DetachAttach -and !$BackupRestore)) {
		throw "You did not select a migration method. Please use -BackupRestore or -DetachAttach"
	}
	
	if ((!$Databases -and !$All -and !$IncludeSupportDbs) -and ($DetachAttach -or $BackupRestore)) {
		throw "You did not select any databases to migrate. Please use -All or -Databases or -IncludeSupportDbs"
	}
	
	# SMO's filestreamlevel is sometimes null
	$sql = "select coalesce(SERVERPROPERTY('FilestreamConfiguredLevel'),0) as fs"
	$sourcefilestream = $sourceserver.ConnectionContext.ExecuteScalar($sql)
	$destfilestream = $destserver.ConnectionContext.ExecuteScalar($sql)
	if ($sourcefilestream -gt 0 -and $destfilestream -eq 0)  { $fswarning = $true }
	
	<# ----------------------------------------------------------
		Run
	---------------------------------------------------------- #>

	if ($All -or $Exclude.length -gt 0 -or $IncludeSupportDbs -or $Databases.length -gt 0)
	{ 
		Copy-SqlDatabase  -sourceserver $sourceserver -destserver $destserver -All $All `
		 -Databases $Databases -Exclude $Exclude -IncludeSupportDbs $IncludeSupportDbs -Force $force
	}
	
}

END {
	$totaltime = ($elapsed.Elapsed.toString().Split(".")[0])
	$sourceserver.ConnectionContext.Disconnect()
	$destserver.ConnectionContext.Disconnect()
	Write-Output "Database migration finished"
	Write-Output "Migration started: $started" 
	Write-Output "Migration completed: $(Get-Date)" 
	Write-Output "Total Elapsed time: $totaltime"
	if ($networkshare.length -gt 0) { Write-Warning "This script does not delete backup files. Backups may still exist at $networkshare." }

}
}