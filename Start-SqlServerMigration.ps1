<# 
 .SYNOPSIS 
    Migrates SQL Server databases, logins, SQL Agent objects, and global configuration settings from one SQL Server to another.
	
 .DESCRIPTION 
    This script provides the ability to migrate databases using detach/copy/attach or backup/restore. SQL Server logins, including passwords, SID and database/server roles can also be migrated. In addition, job server objects can be migrated and server configuration settings can be exported or migrated. This script works with named instances, clusters and SQL Express.
	
	By default, databases will be migrated to the destination SQL Server's default data and log directories. You can override this by specifying -ReuseFolderStructure. Filestreams and filegroups are also migrated. Safety is emphasized.
	
	THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.
	
 .PARAMETER Source
	Source SQL Server. You must have sysadmin access and server version must be > SQL Server 7.
 
 .PARAMETER Destination
	Destination SQL Server. You must have sysadmin access and server version must be > SQL Server 7.
 
 .PARAMETER UseSqlLoginSource
	Uses SQL Login credentials to connect to Source server. Note this is a switch. You will be prompted to enter your SQL login credentials. 
	
	Windows Authentication will be used if UseSqlLoginSource is not specified.
	
	NOTE: Auto-populating parameters (ExcludeDBs, ExcludeLogins, IncludeDBs, IncludeLogins) are populated by the account running the PowerShell script.

 .PARAMETER UseSqlLoginDestination
	Uses SQL Login credentials to connect to Destination server. Note this is a switch. You will be prompted to enter your SQL login credentials. 
	
	Windows Authentication will be used if UseSqlLoginDestination is not specified. To connect as a different Windows user, run PowerShell as that user.
	
 .PARAMETER AllUserDBs
	Migrates user databases. Does not migrate system or support databases. A logfile named $SOURCE-$DESTINATION-$date-logins.csv will be written to the current directory. Requires -BackupRestore or -DetachAttach. Talk about database structure.
 
 .PARAMETER IncludeSupportDBs
	Migration of ReportServer, ReportServerTempDB, SSIDB, and distribution databases if they exist. A logfile named $SOURCE-$DESTINATION-$date-SQLs.csv will be written to the current directory. Requires -BackupRestore or -DetachAttach.

 .PARAMETER BackupRestore
	Use the a Copy-Only Backup and Restore Method. This parameter requires that you specify -NetworkShare in a valid UNC format (\\server\share)
	
 .PARAMETER DetachAttach
	Uses the detach/copy/attach method to perform database migrations. No files are deleted on the source. If the destination attachment fails, the source database will be reattached. File copies are performed over administrative shares (\\server\x$\mssql) using BITS. If a database is being mirrored, the mirror will be broken prior to migration. 
 
 .PARAMETER ReattachAtSource
	Reattaches all source databases after DetachAttach migration.
	
 .PARAMETER ReuseFolderStructure
	By default, databases will be migrated to the destination SQL Server's default data and log directories. You can override this by specifying -ReuseFolderStructure. The same structure will be kept exactly, so consider this if you're migrating between different versions and use part of Microsoft's default SQL structure (MSSQL12.INSTANCE, etc)
	
 .PARAMETER NetworkShare
	Specifies the network location for the backup files. The SQL Service service accounts must read/write permission to access this location.

 .PARAMETER AllLogins
	Migrates all logins, along with their passwords, sids, databasae roles and server roles. Use ExcludeLogins to exclude specific users. Use -force to drop and recreate any existing users on destination. Otherwise, they will be skipped. The 'sa' user and users starting with ## will be skipped. Also updates database owners on destination.

 .PARAMETER ExcludeDBs
	Excludes specified databases when performing -AllUserDBs migrations. This list is auto-populated for tab completion.

 .PARAMETER IncludeDBs
  Migrates ONLY specified databases. This list is auto-populated for tab completion.

 .PARAMETER ExcludeLogins
	Excludes specified logins when performing -AllUserDBs migrations. This list is auto-populated for tab completion.
	
 .PARAMETER IncludeLogins
	Migrates ONLY specified logins. This list is auto-populated for tab completion.
 
 .PARAMETER  ExportSPconfigure
	Exports all server configurations from sp_configure to SQL file named $SOURCE-$DESTINATION-$date-sp_configure.sql in the current directory.
	Not compatible with SQL Server 2000.
 
 .PARAMETER  RunSPconfigure
	Exports all global configuration options from source server and executes it on the destination server. Running ExportSPconfigure then evaluating the export and running it on the destination is recommended instead.
	Not compatible with SQL Server 2000.

 .PARAMETER MigrateJobServer
	Migrates all job server objects, including proxy accounts, job schedules, shared schedules, alert system, job categories, operator categories, alert categories, alerts, target server groups, target servers, operators, and jobs. Existing objects will not be deleted, and no -force option is available.

 .PARAMETER MigrateUserObjectsinSysDBs
	This switch migrates user-created objects in the systems databases to the new server. This is useful for DBA's who create environment specific stored procedures, tables, etc in the master, model or msdb databases.

 .PARAMETER SetSourceReadOnly
	Sets all migrated databases to ReadOnly prior to detach/attach & backup/restore. If -ReAttachAtSource is used, db is set to read-only after reattach.
 
 .PARAMETER Everything
	Migrates all logins, databases, agent objects, except those listed by ExcludeDBs and ExcludeLogins. 
	Also exports sp_configure settings and user created objects within system databases.
	
.PARAMETER Force
	If migrating users, forces drop and recreate of SQL and Windows logins. 
	If migrating databases, deletes existing databases with matching names. 
	If using -DetachAttach, -Force will break mirrors and drop dbs from Availability Groups.
	MigrateJobServer not supported.
	
 .NOTES 
    Author  : Chrissy LeMaire
    Requires: PowerShell Version 3.0, SQL Server SMO
	DateUpdated: 2015-May-11
	Version: 1.3.3
	Limitations: 	Doesn't cover what it doesn't cover (replication, linked servers, certificates, etc)
					SQL Server 2000 login migrations have some limitations (server perms aren't migrated, etc)
					SQL Server 2000 databases cannot be directly migrated to SQL Server 2012 and above.
					Logins within SQL Server 2012 and above logins cannot be migrated to SQL Server 2008 R2 and below.				

 .LINK 
  	https://gallery.technet.microsoft.com/scriptcenter/Use-PowerShell-to-Migrate-86c841df/

 .EXAMPLE   
.\Start-SqlServerMigration.ps1 -Source sqlserver\instance -Destination sqlcluster -DetachAttach -Everything

Description

All databases, logins, job objects and sp_configure options will be migrated from sqlserver\instance to sqlcluster. Databases will be migrated using the detach/copy files/attach method. DBowner will be updated. User passwords, SIDs, database roles and server roles will be migrated along with the login.

 .EXAMPLE   
.\Start-SqlServerMigration.ps1 -Source sqlserver\instance -Destination sqlcluster -AllUserDBs -ExcludeDBs Northwind, pubs -IncludeSupportDBs -force -AllLogins -ExcludeLogins nwuser, pubsuser, "corp\domain admins"  -MigrateJobServer -ExportSPconfigure -UseSqlLoginSource -UseSqlLoginDestination

Description

Prompts for SQL login usernames and passwords on both the Source and Destination then connects to each using the SQL Login credentials. 

All logins except for nwuser, pubsuser and the corp\domain admins group will be migrated from sqlserver\instance to sqlcluster, along with their passwords, server roles and database roles. A logfile named SQLSERVER-SQLCLUSTER-$date-logins.csv will be written to the current directory. Existing SQL users will be dropped and recreated.

Migrates all user databases except for Northwind and pubs by performing the following: kick all users out of the database, detach all data/log files, move files across the network over an admin share (\\SQLSERVER\M$\MSSQL...), attach file on destination server. If the database exists on the destination, it will be dropped prior to attach.

It also includes the support databases (ReportServer, ReportServerTempDB, SSIDB, distribution). 

If the database files (*.mdf, *.ndf, *.ldf) on SQLCLUSTER exist and aren't in use, they will be overwritten. A logfile named SQLSERVER-SQLCLUSTER-$date-SQLs.csv will be written to the current directory.

All job server objects will be migrated. A logfile named SQLSERVER-SQLCLUSTER-$date-jobs.csv will be written to the current directory.

A file named SQLSERVER-SQLCluster-$date-sp_configure.sql with global server configurations will be written to the current directory. This file can then be executed manually on SQLCLUSTER.
#> 
#Requires -Version 3.0
[CmdletBinding(DefaultParameterSetName="DBMigration", SupportsShouldProcess = $true)] 

Param(
	# Source SQL Server
	[parameter(Mandatory = $true)]
	[string]$Source,
	
	# Destination SQL Server
	[parameter(Mandatory = $true)]
	[string]$Destination,
	
	#Other Migrations
	[switch]$AllLogins,
	[switch]$MigrateJobServer,
	[switch]$ExportSPconfigure,
	[switch]$RunSPConfigure,
	[switch]$MigrateUserObjectsinSysDBs,
	
	# Database Migration
	[Parameter(Mandatory = $true, ParameterSetName="DBAttachDetach")]
	[switch]$DetachAttach,
	[Parameter(Mandatory = $true,ParameterSetName="DBBackup")]
	[switch]$BackupRestore,
	
	[Parameter(ParameterSetName="DBBackup")]
	[Parameter(ParameterSetName="DBAttachDetach")]
	[switch]$ReuseFolderstructure,
	
	[Parameter(ParameterSetName="DBBackup")]
	[Parameter(ParameterSetName="DBAttachDetach")]
	[switch]$AllUserDBs,
	
	[Parameter(ParameterSetName="DBBackup")]
	[Parameter(ParameterSetName="DBAttachDetach")]
	[switch]$IncludeSupportDBs,
	
	[Parameter(ParameterSetName="DBAttachDetach")]
	[switch]$ReattachAtSource,
	
	[Parameter(Mandatory=$true, ParameterSetName="DBBackup",
		HelpMessage="Specify a valid network share in the format \\server\share that can be accessed by your account and both SQL Server service accounts.")]
	[string]$NetworkShare,
	
	[Parameter(ParameterSetName="DBBackup")]
	[Parameter(ParameterSetName="DBAttachDetach")]
	[switch]$Everything,
	
	[Parameter(ParameterSetName="DBBackup")]
	[Parameter(ParameterSetName="DBAttachDetach")]
	[switch]$SetSourceReadOnly,
	
	# The rest
	[switch]$UseSqlLoginSource,
	[switch]$UseSqlLoginDestination,
	[switch]$Force
	)

DynamicParam  {
	if ($Source) {
		# Check for SMO and SQL Server access
		if ([Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMO") -eq $null) {return}
		
		$server = New-Object Microsoft.SqlServer.Management.Smo.Server $source
		$server.ConnectionContext.ConnectTimeout = 2
		try { $server.ConnectionContext.Connect() } catch { return }
		
		$SupportDBs = "ReportServer","ReportServerTempDB", "SSISDB", "distribution"
		
		# Populate arrays
		$databaselist = @(); $loginlist = @()
		foreach ($database in $server.databases) {
			if ((!$database.IsSystemObject) -and $SupportDBs -notcontains $database.name) {
					$databaselist += $database.name}
			}
		foreach ($login in $server.logins) { 
			if (!$login.name.StartsWith("##") -and $login.name -ne 'sa') {
			$loginlist += $login.name}
			}
				
		# Reusable parameter setup
		$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
		$attributes = New-Object System.Management.Automation.ParameterAttribute
		
		$attributes.ParameterSetName = "__AllParameterSets"
		$attributes.Mandatory = $false
		
		# Database list parameter setup
		if ($databaselist) { $dbvalidationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $databaselist }
		$dbattributes = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
		$dbattributes.Add($attributes)
		if ($databaselist) { $dbattributes.Add($dbvalidationset) }
		$IncludeDBs = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("IncludeDBs", [String[]], $dbattributes)
		$ExcludeDBs = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("ExcludeDBs", [String[]], $dbattributes)
		
		# Login list parameter setup
		if ($loginlist) { $loginvalidationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $loginlist }
		$loginattributes = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
		$loginattributes.Add($attributes)
		if ($loginlist) { $loginattributes.Add($loginvalidationset) }
		$IncludeLogins = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("IncludeLogins", [String[]], $loginattributes)
		$ExcludeLogins = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("ExcludeLogins", [String[]], $loginattributes)
		
		$newparams.Add("IncludeDBs", $IncludeDBs)
		$newparams.Add("ExcludeDBs", $ExcludeDBs)
		$newparams.Add("IncludeLogins", $IncludeLogins)
		$newparams.Add("ExcludeLogins", $ExcludeLogins)
		
		$server.ConnectionContext.Disconnect()
	
	return $newparams
	}
}

BEGIN {

# Essential Database Functions

Function Backup-SQLDatabase {
        <#
            .SYNOPSIS
             Makes a full database backup of a database to a specified directory. $server is an SMO server object.

            .EXAMPLE
             Backup-SQLDatabase $smoserver $dbname \\fileserver\share\sql\database.bak

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
	Write-Host "Backing up $dbname" -ForegroundColor Yellow

	try { 
		$backup.SqlBackup($server)
		Write-Progress -id 1 -activity "Backing up database $dbname to $backupfile" -status "Complete" -Completed
		Write-Host "Backup succeeded" -ForegroundColor Green
		return $true
		}
	catch {
		Write-Progress -id 1 -activity "Backup" -status "Failed" -completed
		return $false 
	}
}

Function Restore-SQLDatabase {
        <#
            .SYNOPSIS
             Restores .bak file to SQL database. Creates db if it doesn't exist. $filestructure is
			a custom object that contains logical and physical file locations.

            .EXAMPLE
			 $filestructure = Get-SQLFileStructures $sourceserver $destserver $ReuseFolderstructure
             Restore-SQLDatabase $destserver $dbname $backupfile $filestructure   

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
	
	Write-Host "Restoring $dbname to $servername" -ForegroundColor Yellow
	
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

Function Get-SQLFileStructures {
 <#
            .SYNOPSIS
             Custom object that contains file structures and remote paths (\\sqlserver\m$\mssql\etc\etc\file.mdf) for
			 source and destination servers.
			
            .EXAMPLE
            $filestructure = Get-SQLFileStructures $sourceserver $destserver $ReuseFolderstructure
			foreach	($file in $filestructure.databases[$dbname].destination.values) {
				Write-Host $file.physical
				Write-Host $file.logical
				Write-Host $file.remotepath
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
						$directory = Get-SQLDefaultPaths $destserver data
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
			
			# Add support for Full Text Catalogs in SQL Server 2005 and below
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
						$directory = Get-SQLDefaultPaths $destserver data
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
					$directory = Get-SQLDefaultPaths $destserver log
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

Function Dismount-SQLDatabase {
 <#
            .SYNOPSIS
             Detaches a SQL Server database. $server is an SMO server object.   

            .EXAMPLE
             $detachresult = Dismount-SQLDatabase $server $dbname   

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
		Write-Host "Attempting remove from Availability Group $agname" -ForegroundColor Yellow 
		try {
			$server.AvailabilityGroups[$database.AvailabilityGroupName].AvailabilityDatabases[$dbname].Drop()
			Write-Host "Successfully removed $dbname from  detach from $agname on $($server.name)" -ForegroundColor Green 
		} catch { Write-Host "Could not remove $dbname from $agname on $($server.name)" -ForegroundColor Red; return $false }
	}
	
	Write-Host "Attempting detach from $dbname from $source" -ForegroundColor Yellow 
	
	####### Using SQL to detach does not modify the $database collection #######
	$sql = "ALTER DATABASE [$dbname] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;EXEC master.dbo.sp_detach_db N'$dbname'"
	try { 
		$null = $server.ConnectionContext.ExecuteNonQuery($sql)
		Write-Host "Successfully detached $dbname from $source" -ForegroundColor Green 
		return $true
	} 
	catch { return $false }
}

Function Mount-SQLDatabase {
	 <#
		SYNOPSIS
		 Attaches a SQL Server database, and sets its owner. $server is an SMO server object.

		.EXAMPLE
		 Mount-SQLDatabase $destserver $dbname $destfilestructure $dbowner

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

Function Start-SQLBackupRestore  {
 <#
            .SYNOPSIS
             Performs checks, then executes Backup-SQLDatabase to a fileshare and then a subsequential Restore-SQLDatabase.

            .EXAMPLE
              Start-SQLBackupRestore $sourceserver $destserver $dbname $networkshare $force  

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
		
	$filestructure = Get-SQLFileStructures $sourceserver $destserver $ReuseFolderstructure
	$filename = "$dbname-$timenow.bak"
	$backupfile = Join-Path $networkshare $filename
	
	$backupresult = Backup-SQLDatabase $sourceserver $dbname $backupfile
	
	if ($backupresult) {
	$restoreresult = Restore-SQLDatabase $destserver $dbname $backupfile $filestructure
		
		if ($restoreresult) {
			# RESTORE was successful
			Write-Host "Successfully restored $dbname to $destination" -ForegroundColor Green
			return $true

		} else {
			# RESTORE was unsuccessful
			if ($ReuseFolderStructure) {
				Write-Host "Failed to restore $dbname to $destination. You specified -ReuseFolderStructure. Does the exact same destination directory structure exist?" -ForegroundColor Red
				return "Failed to restore $dbname to $destination using ReuseFolderStructure."
			}
			else {
				Write-Host "Failed to restore $dbname to $destination" -ForegroundColor Red
				return "Failed to restore $dbname to $destination."
			}
		}
		
	} else {
		# add to failed because BACKUP was unsuccessful
		Write-Host "Backup Failed. Does SQL Server account ($($sourceserver.ServiceAccount)) have access to $($NetworkShare)?"	-ForegroundColor Red
		return "Backup Failed. Does SQL Server account ($($sourceserver.ServiceAccount)) have access to $NetworkShare?"	
	}
}

Function Start-SQLDetachAttach   {
 <#
            .SYNOPSIS
             Performs checks, then executes Dismount-SQLDatabase on a database, copies its files to the new server, 
			 then performs Mount-SQLDatabase. $sourceserver and $destserver are SMO server objects.
			 $filestructure is a custom object generated by Get-SQLFileStructures

            .EXAMPLE
              result = Start-SQLDetachAttach $sourceserver $destserver $filestructure $dbname $force

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
	
	$detachresult =	Dismount-SQLDatabase $sourceserver $dbname
	
	if ($detachresult) {
	
		$transfer = Start-SQLFileTransfer $filestructure $dbname	
		if ($transfer -eq $false) { Write-Warning "Could not copy files."; return "Could not copy files." }	
		$attachresult = Mount-SQLDatabase $destserver $dbname $destfilestructure $dbowner

		if ($attachresult -eq $true) {
			# add to added dbs because ATTACH was successful
			Write-Host "Successfully attached $dbname to $destination" -ForegroundColor Green
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

Function Copy-SqlDatabases  {
 <#
            .SYNOPSIS
              Performs tons of checks then migrates the databases.

            .EXAMPLE
                Copy-SqlDatabases $sourceserver $destserver $AllUserDBs $IncludeDBs $ExcludeDBs $IncludeSupportDBs $force

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
            [bool]$AllUserDBs,
			
			[Parameter()]
            [string[]]$IncludeDBs,
			
			[Parameter()]
            [string[]]$ExcludeDBs,

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
		throw "Source SQL Server version build must be <= destination SQL Server for database migration."
	}
	if ($fswarning) { Write-Warning "FILESTREAM enabled on $source but not $destination. Databases that use FILESTREAM will be skipped."  }

	Write-Host "Checking access to remote directories..." -ForegroundColor Yellow
	
	$sourcenetbios = Get-NetBIOSName $sourceserver
	$destnetbios = Get-NetBIOSName $destserver
	
	If (!(Test-Path (Join-AdminUNC $sourcenetbios (Get-SQLDefaultPaths $sourceserver data)))) { 
		Write-Host "Can't access remote SQL directories on $source. Halting database migration." -ForegroundColor Red
		return 
	}
	
	If (!(Test-Path (Join-AdminUNC $destnetbios (Get-SQLDefaultPaths $destserver data)))) { 
		Write-Host "Can't access remote SQL directories on $destination. Halting database migration." -ForegroundColor Red
		return 
	}
	
	##################################################################
	
	$SupportDBs = "ReportServer","ReportServerTempDB", "SSISDB", "distribution"
	$sa = $changedbowner
	
	$timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
	$csvfilename = "$($sourceserver.name.replace('\','$'))-to-$($destserver.name.replace('\','$'))-$timenow"
	
	$migrateddb = @{}; $skippedb = @{}
	$ExcludeDBs | Where-Object {!([string]::IsNullOrEmpty($_))} | ForEach-Object { $skippedb.Add($_,"Explicitly Skipped") }
	
	$filestructure = Get-SQLFileStructures $sourceserver $destserver $ReuseFolderstructure
	Set-Content -Path "$csvfilename-db.csv" "Database Name, Result, Start, Finish"
	
	foreach ($database in $sourceserver.databases) {
		$dbelapsed = [System.Diagnostics.Stopwatch]::StartNew() 
		$dbname = $database.name
		$dbowner = $database.Owner
		
		
		<# ###############################################################
		
							Database Checks
			
		############################################################### #>
		
		if ($database.id -le 4) { continue }
		if ($IncludeDBs -and $IncludeDBs -notcontains $dbname) { continue }
		if ($IncludeSupportDBs -eq $false -and $SupportDBs -contains $dbname) { continue }
		
		Write-Host "`n######### Database: $dbname #########" -ForegroundColor White
		$dbstart = Get-Date
		
		if ($skippedb.ContainsKey($dbname) -and $IncludeDBs -eq $null) {
			Write-Host "`nSkipping $dbname" -ForegroundColor Cyan
			continue 
		}

		if (($database.status.toString()).StartsWith("Normal") -eq $false) { 
			Write-Warning "Skipping $dbname. Status not Normal."
			$skippedb.Add($dbname,"Skipped. Database status not Normal (Status: $($database.status)).")
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
					Write-Host "$dbname already exists. -Force was specified. Dropping $dbname on $destination." -ForegroundColor Yellow
					$dropresult = Drop-SQLDatabase $destserver $dbname
					if (!$dropresult) { $skippedb[$dbname] = "Database exists and could not be dropped."; continue }
				}
		}
		Write-Host "Started: $dbstart" -ForegroundColor Cyan
		
		if ($sourceserver.versionMajor -ge 9) {
			$sourcedbownerchaining = $sourceserver.databases[$dbname].DatabaseOwnershipChaining
			$sourcedbtrustworthy = $sourceserver.databases[$dbname].Trustworthy
			$sourcedbbrokerenabled = $sourceserver.databases[$dbname].BrokerEnabled
			
		}
		
		$sourcedbreadonly = $sourceserver.Databases[$dbname].ReadOnly
		
		if ($SetSourceReadOnly) { 
			If ($Pscmdlet.ShouldProcess($source,"Set $dbname to read-only")) {	
				$result = Update-SQLdbReadOnly $sourceserver $dbname $true
			}
		}
				
		if ($BackupRestore) {
			If ($Pscmdlet.ShouldProcess($destination,"Backup $dbname from $source and restoring.")) {
				$result = (Start-SQLBackupRestore $sourceserver $destserver $dbname $networkshare $force)
				$dbfinish = Get-Date					
				if ($result -eq $true) {
					$migrateddb.Add($dbname,"Successfully migrated,$dbstart,$dbfinish")
					Add-Content -Path "$csvfilename-db.csv" "$dbname,Successfully migrated,$dbstart,$dbfinish"
					$result = Update-SQLdbowner $sourceserver $destserver -dbname $dbname
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
				$result = Start-SQLDetachAttach $sourceserver $destserver $filestructure $dbname $force
				$dbfinish = Get-Date
				if ($result -eq $true) {
					$migrateddb.Add($dbname,"Successfully migrated,$dbstart,$dbfinish")
					Add-Content -Path "$csvfilename-db.csv" "$dbname,Successfully migrated,$dbstart,$dbfinish"
					$result = Update-SQLdbowner $sourceserver $destserver -dbname $dbname
					
					If ($result) {
						Add-Content -Path "$csvfilename-dbowner.csv" "$dbname,$dbowner" 
					}
				} else { 
					$skippedb[$dbname] = $result
					Add-Content -Path "$csvfilename-db.csv" "$dbname,Migration failed - $result,$dbstart,$dbfinish"
				}
				
				if ($ReattachAtSource) {
					$null = ($sourceserver.databases).Refresh() 
					$result = Mount-SQLDatabase $sourceserver $dbname $sourcefilestructure $dbowner
					if ($result -eq $true) {
						$sourceserver.databases[$dbname].DatabaseOwnershipChaining = $sourcedbownerchaining 
						$sourceserver.databases[$dbname].Trustworthy = $sourcedbtrustworthy
						$sourceserver.databases[$dbname].BrokerEnabled = $sourcedbbrokerenabled
						$sourceserver.databases[$dbname].alter()
						if ($SetSourceReadOnly) { 
							$null = Update-SQLdbReadOnly $sourceserver $dbname $true 
						} else { $null = Update-SQLdbReadOnly $sourceserver $dbname $sourcedbreadonly }
						Write-Host "Successfully reattached $dbname to $source" -ForegroundColor Green
						
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
						Write-Host "Successfully updated DatabaseOwnershipChaining for $sourcedbownerchaining on $dbname on $destination" -ForegroundColor Green
					} catch { Write-Host "Failed to update DatabaseOwnershipChaining for $sourcedbownerchaining on $dbname on $destination" -ForegroundColor Red }
				}
			}
			
			if ($sourcedbtrustworthy -ne $destserver.databases[$dbname].Trustworthy ) {
				If ($Pscmdlet.ShouldProcess($destination,"Updating Trustworthy on $dbname")) {
					try {
						$destserver.databases[$dbname].Trustworthy = $sourcedbtrustworthy
						$destserver.databases[$dbname].alter()
						Write-Host "Successfully updated Trustworthy to $sourcedbtrustworthy for $dbname on $destination" -ForegroundColor Green
					} catch { Write-Host "Failed to update Trustworthy to $sourcedbtrustworthy for $dbname on $destination" -ForegroundColor Red }
				}
			}
			
			if ($sourcedbbrokerenabled -ne $destserver.databases[$dbname].BrokerEnabled ) {
				If ($Pscmdlet.ShouldProcess($destination,"Updating BrokerEnabled on $dbname")) {
					try {
						$destserver.databases[$dbname].BrokerEnabled = $sourcedbbrokerenabled
						$destserver.databases[$dbname].alter()
						Write-Host "Successfully updated BrokerEnabled to $sourcedbbrokerenabled for $dbname on $destination" -ForegroundColor Green
					} catch { Write-Host "Failed to update BrokerEnabled to $sourcedbbrokerenabled for $dbname on $destination" -ForegroundColor Red }
				}
			}
		}
		
		if ($sourcedbreadonly -ne $destserver.databases[$dbname].ReadOnly ) {
			If ($Pscmdlet.ShouldProcess($destination,"Updating ReadOnly status on $dbname")) {
				try {
					$result = Update-SQLdbReadOnly $destserver $dbname $sourcedbreadonly
				} catch { Write-Host "Failed to update ReadOnly status on $dbname" -ForegroundColor Red }
			}
		}
	
	$dbtotaltime=$dbfinish-$dbstart
	$dbtotaltime = ($dbtotaltime.toString().Split(".")[0])

	Write-Host "Finished: $dbfinish" -ForegroundColor Cyan
	Write-Host "Elapsed time: $dbtotaltime" -ForegroundColor Cyan
	} # end db by db processing
	
	$alldbtotaltime = ($alldbelapsed.Elapsed.toString().Split(".")[0])
	Add-Content -Path "$csvfilename-db.csv" "`r`nElapsed time,$alldbtotaltime"
	if ($migrateddb.count -eq 0) { 
		If (Test-Path "$csvfilename-db.csv") { Remove-Item -Path "$csvfilename-db.csv" }
	}
	$migrateddb.GetEnumerator() | Sort-Object Value; $skippedb.GetEnumerator() | Sort-Object Value
	Write-Host "`nCompleted database migration" -ForegroundColor Green
}

# Login Functions

Function Copy-SqlLogins {
	<#
	.SYNOPSIS
	  Migrates logins from source to destination SQL Servers. Database & Server securables & permissions are preserved.
	
	.EXAMPLE
	 Copy-SqlLogins -Source $sourceserver -Destination $destserver -Force $true
	
	 Copies logins from source server to destination server.
	 
	.OUTPUTS
	   A CSV log and visual output of added or skipped logins.
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
            [string[]]$IncludeLogins,
			
			[Parameter()]
            [string[]]$ExcludeLogins,
			
			[Parameter()]
            [bool]$Force
		)
		
	if ($sourceserver.versionMajor -gt 10 -and $destserver.versionMajor -lt 11) {
		throw "SQL login migration from SQL Server version $($sourceserver.versionMajor) to $($destserver.versionMajor) not supported. Halting."
	}

	$skippedlogin = @{}; $migratedlogin = @{}; $source = $sourceserver.name; $destination = $destserver.name
	$ExcludeLogins | Where-Object {!([string]::IsNullOrEmpty($_))} | ForEach-Object { $skippedlogin.Add($_,"Explicitly Skipped") }
	$timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
	$csvfilename = "$($sourceserver.name.replace('\','$'))-to-$($destserver.name.replace('\','$'))-$timenow"
	
	foreach ($sourcelogin in $sourceserver.logins) {

		$username = $sourcelogin.name
		if ($IncludeLogins -ne $null -and $IncludeLogins -notcontains $username) { continue }
		if ($skippedlogin.ContainsKey($username) -or $username.StartsWith("##") -or $username -eq 'sa') { continue }
		$servername = Get-NetBIOSName $sourceserver

		$admin = $sourceserver.ConnectionContext.truelogin

		if ($admin -eq $username -and $force) {
			Write-Warning "Cannot drop login performing the migration. Skipping"
			$skippedlogin.Add("$username","Skipped. Cannot drop login performing the migration.")
			continue
		}
		
		$userbase = ($username.Split("\")[0]).ToLower()
		if ($servername -eq $userbase -or $username.StartsWith("NT ")) {
			$skippedlogin.Add("$username","Skipped. Local machine username.")
			continue }
		if (($login = $destserver.Logins.Item($username)) -ne $null -and !$force) { 
			$skippedlogin.Add("$username","Already exists in destination. Use -force to drop and recreate.")
			continue }
	
		if ($login -ne $null -and $force) {
			if ($username -eq $destserver.ServiceAccount) { Write-Warning "$username is the destination service account. Skipping drop."; continue }
				If ($Pscmdlet.ShouldProcess($destination,"Dropping $username")) {
					# Kill connections, delete user
					Write-Host "Attempting to migrate $username" -ForegroundColor Yellow
					Write-Host "Force was specified. Attempting to drop $username on $destination" -ForegroundColor Yellow
					try {
						$destserver.EnumProcesses() | Where { $_.Login -eq $username }  | ForEach-Object {$destserver.KillProcess($_.spid)}		
						$destserver.Databases | Where { $_.Owner -eq $username } | ForEach-Object { $_.SetOwner('sa'); $_.Alter()  }	
						$login.drop()
						Write-Host "Successfully dropped $username on $destination" -ForegroundColor Green
					} catch {
						$ex = (($_.Exception.Message -Split ":")[1])
						if ($ex -ne $null) { $ex.trim() }
						$skippedlogin.Add("$username","Couldn't drop on $destination`: $ex") 
						Write-Warning "Could not drop $username`: $ex"
						continue }
				}
		}
				
		If ($Pscmdlet.ShouldProcess($destination,"Adding SQL login $username")) {
			Write-Host "Attempting to add $username to $destination" -ForegroundColor Yellow
			$destlogin = new-object Microsoft.SqlServer.Management.Smo.Login($destserver, $username)
			Write-Host "Setting $username SID to source username SID" -ForegroundColor Green
			$destlogin.set_Sid($sourcelogin.get_Sid())
			$defaultdb = $sourcelogin.DefaultDatabase
			$destlogin.Language = $sourcelogin.Language
			
			if ($destserver.databases[$defaultdb] -eq $null) {
				Write-Warning "$defaultdb does not exist on destination. Setting defaultdb to master."
				$defaultdb = "master" 
			}
			Write-Host "Set $username defaultdb to $defaultdb" -ForegroundColor Green
			$destlogin.DefaultDatabase = $defaultdb

			$checkexpiration = "ON"; $checkpolicy = "ON"
			if (!$sourcelogin.PasswordPolicyEnforced) { 
				$destlogin.PasswordPolicyEnforced = $false 
				$checkpolicy = "OFF"
			}
			if (!$sourcelogin.PasswordExpirationEnabled) { 
				$destlogin.PasswordExpirationEnabled = $false
				$checkexpiration = "OFF"
			}

			# Attempt to add SQL Login
			if ($sourcelogin.LoginType -eq "SqlLogin") {
				$destlogin.LoginType = "SqlLogin"
				$sourceloginname = $sourcelogin.name
				
				switch ($sourceserver.versionMajor) 
				{ 	0 {$sql = "SELECT convert(varbinary(256),password) as hashedpass FROM master.dbo.syslogins WHERE loginname='$sourceloginname'"} 
					8 {$sql = "SELECT convert(varbinary(256),password) as hashedpass FROM dbo.syslogins WHERE name='$sourceloginname'"} 
					9 {$sql = "SELECT convert(varbinary(256),password_hash) as hashedpass FROM sys.sql_logins where name='$sourceloginname'"} 
					default {$sql = "SELECT CAST(CONVERT(varchar(256), CAST(LOGINPROPERTY(name,'PasswordHash') 
						AS varbinary (256)), 1) AS nvarchar(max)) as hashedpass FROM sys.server_principals
						WHERE principal_id = $($sourcelogin.id)"
					} 
				}

				try { $hashedpass = $sourceserver.ConnectionContext.ExecuteScalar($sql) }
				catch { 
					$hashedpassdt = $sourceserver.databases['master'].ExecuteWithResults($sql) 
					$hashedpass = $hashedpassdt.Tables[0].Rows[0].Item(0)
				}
				
				if ($hashedpass.gettype().name -ne "String") {
					$passtring = "0x"; $hashedpass | % {$passtring += ("{0:X}" -f $_).PadLeft(2, "0")}
					$hashedpass = $passtring
				}
				
				try {
					$destlogin.Create($hashedpass, [Microsoft.SqlServer.Management.Smo.LoginCreateOptions]::IsHashed)
					$migratedlogin.Add("$username","SQL Login Added successfully") 
					$destlogin.refresh()
					Write-Host "Successfully added $username to $destination" -ForegroundColor Green }
				catch {
					try {
						$sid = "0x"; $sourcelogin.sid | % {$sid += ("{0:X}" -f $_).PadLeft(2, "0")}
						$sqlfailsafe = "CREATE LOGIN [$username] WITH PASSWORD = $hashedpass HASHED, SID = $sid, 
						DEFAULT_DATABASE = [$defaultdb], CHECK_POLICY = $checkpolicy, CHECK_EXPIRATION = $checkexpiration"
						$null = $destserver.ConnectionContext.ExecuteNonQuery($sqlfailsafe) 
						$destlogin = $destserver.logins[$username]
						$migratedlogin.Add("$username","SQL Login Added successfully") 
						Write-Host "Successfully added $username to $destination" -ForegroundColor Green
					} catch {
						$ex = ($_.Exception.InnerException).tostring()
						$ex = ($ex -split "at Microsoft.SqlServer.Management.Common.ConnectionManager")[0]
						$skippedlogin.Add("$username","Add failed: $ex")
						Write-Warning "Failed to add $username to $destination. See log for details."
						continue 
					}
				}
			}
			# Attempt to add Windows Login
			elseif ($sourcelogin.LoginType -eq "WindowsUser" -or $sourcelogin.LoginType -eq "WindowsGroup") {
				$destlogin.LoginType = $sourcelogin.LoginType
				$destlogin.Language = $sourcelogin.Language
				try {
					$destlogin.Create()
					$migratedlogin.Add("$username","Windows user/group added successfully") 
					$destlogin.refresh()
					Write-Host "Successfully added $username to $destination" -ForegroundColor Green }
				catch { 
					$skippedlogin.Add("$username","Add failed")
					Write-Warning "Failed to add $username to $destination. See log for details."
					continue }
			}
			# This script does not currently support certificate mapped or asymmetric key users.
			else { 
				$skippedlogin.Add("$username","Skipped. $($sourcelogin.LoginType) logins not supported.")
				Write-Warning "$($sourcelogin.LoginType) logins not supported. $($sourcelogin.name) skipped."
				continue }
			
			if ($sourcelogin.IsDisabled) { try { $destlogin.Disable() } catch { Write-Warning "$username disabled on source, but could not be disabled on destination." } }
			if ($sourcelogin.DenyWindowsLogin) { try { $destlogin.DenyWindowsLogin = $true } catch { Write-Warning "$username denied login on source, but could not be denied ogin on destination." } }
		}
		
		
		# Server Roles: sysadmin, bulkadmin, etc
		foreach ($role in $sourceserver.roles) {
		try { $rolemembers = $role.EnumMemberNames() } catch { $rolemembers = $role.EnumServerRoleMembers() }
			if ($rolemembers -contains $sourcelogin.name) {
				if ($destserver.roles[$role.name] -ne $null) { 
					If ($Pscmdlet.ShouldProcess($destination,"Adding $username to $($role.name) server role")) {
						try {
							$destlogin.AddToRole($role.name)
							Write-Host "Added $username to $($role.name) server role."  -ForegroundColor Green
							} catch {
							Write-Warning "Failed to add $username to $($role.name) server role." }
							}
						}
					}
				}

		if ($sourceserver.versionMajor -ge 9 -and $destserver.versionMajor -ge 9) { # These operations are only supported by SQL Server 2005 and above.
			# Securables: Connect SQL, View any database, Administer Bulk Operations, etc.
			$perms = $sourceserver.EnumServerPermissions($username)
			foreach ($perm in $perms) {
				$permstate = $perm.permissionstate
				if ($permstate -eq "GrantWithGrant") { $grantwithgrant = $true; $permstate = "grant" } else { $grantwithgrant = $false }
				$permset = New-object Microsoft.SqlServer.Management.Smo.ServerPermissionSet($perm.permissiontype)
				If ($Pscmdlet.ShouldProcess($destination,"Performing $permstate on $($perm.permissiontype) for $username")) {
					try { 
						$destserver.PSObject.Methods[$permstate].Invoke($permset, $username, $grantwithgrant)
						Write-Host "Successfully performed $permstate $($perm.permissiontype) to $username"  -ForegroundColor Green
					} catch {
						Write-Warning "Failed to $permstate $($perm.permissiontype) to $username" 
					}
				}
			}
			
			# Credential mapping
			$logincredentials = $sourceserver.credentials | Where-Object {$_.Identity -eq $sourcelogin.name}
			foreach ($credential in $logincredentials) {
				if ($destserver.Credentials[$credential.name] -eq $null) {
					If ($Pscmdlet.ShouldProcess($destination,"Adding $($credential.name) to $username")) {
						try {
							$newcred = new-object Microsoft.SqlServer.Management.Smo.Credential($destserver, $credential.name)
							$newcred.identity = $sourcelogin.name
							$newcred.Create() 
							Write-Host "Successfully performed $permstate $($perm.permissiontype) to $username on $destination"  -ForegroundColor Green
						} catch {
							Write-Warning "Failed to $permstate $($perm.permissiontype) to $username on $destination" }
					}
				}
			}
		}
			
		if ($destserver.versionMajor -lt 9) { Write-Warning "Database mappings skipped when destination is < SQL Server 2005"; continue }
		
		# Database mappings and securables
		foreach ($db in $sourcelogin.EnumDatabaseMappings()) {
			$dbname = $db.dbname
			$destdb = $destserver.databases[$dbname]
			$sourcedb = $sourceserver.databases[$dbname]
			$dbusername = $db.username; $dblogin = $db.loginName
			
			if ($destdb -ne $null) {
				if ($destdb.users[$dbusername] -eq $null) {
					If ($Pscmdlet.ShouldProcess($destination,"Adding $dbusername to $dbname")) {
						$sql = $sourceserver.databases[$dbname].users[$dbusername].script()
						try { $destdb.ExecuteNonQuery($sql)
							Write-Host "Added username $dbusername (login: $dblogin) to $dbname" -ForegroundColor Green }
						catch { Write-Warning "Failed to add $dbusername ($dblogin) to $dbname on $destination."
						}
					}
				}	
			 # DB owner
				If ($sourcedb.owner -eq $username) {
					If ($Pscmdlet.ShouldProcess($destination,"Changing $dbname dbowner to $username")) {
						try {
							$result = Update-SQLdbowner $sourceserver $destserver -dbname $dbname
							if ($result -eq $true) {
								Write-Host "Changed $($destdb.name) owner to $($sourcedb.owner)." -ForegroundColor Green
							} else { Write-Warning "Failed to update $($destdb.name) owner to $($sourcedb.owner)." }
						} catch { Write-Warning "Failed to update $($destdb.name) owner to $($sourcedb.owner)." }
					}
				}
				
			 # Database Roles: db_owner, db_datareader, etc
				foreach ($role in $sourcedb.roles) {
					if ($role.EnumMembers() -contains $username) {
						$destdbrole = $destdb.roles[$role.name]
						if ($destdbrole -ne $null -and $dbusername -ne "dbo" -and $destdbrole.EnumMembers() -notcontains $username) { 
							If ($Pscmdlet.ShouldProcess($destination,"Adding $username to $($role.name) database role on $dbname")) {
								try { $destdbrole.AddMember($username)
								$destdb.Alter() }
								catch { Write-Warning "Failed to add $username to $($role.name) database role on $dbname." }
							}
						}
					}
				}
				# Connect, Alter Any Assembly, etc
				$perms = $sourcedb.EnumDatabasePermissions($username)
				foreach ($perm in $perms) {
					$permstate = $perm.permissionstate
					if ($permstate -eq "GrantWithGrant") { $grantwithgrant = $true; $permstate = "grant" } else { $grantwithgrant = $false }
					$permset = New-object Microsoft.SqlServer.Management.Smo.DatabasePermissionSet($perm.permissiontype)
					If ($Pscmdlet.ShouldProcess($destination,"Performing $permstate on $($perm.permissiontype) for $username on $dbname")) {
						try { $destdb.PSObject.Methods[$permstate].Invoke($permset, $username, $grantwithgrant) }
						catch { Write-Warning "Failed to perform $permstate on $($perm.permissiontype) for $username on $dbname." }		
					}
				}
			}
		}
	}
	
	$migratedlogin.GetEnumerator() | Sort-Object value; $skippedlogin.GetEnumerator() | Sort-Object value
	$migratedlogin.GetEnumerator() | Sort-Object value | Select Name, Value | Export-Csv -Path "$csvfilename-logins.csv" -NoTypeInformation
	$skippedlogin.GetEnumerator() | Sort-Object value | Select Name, Value | Export-Csv -Append -Path "$csvfilename-logins.csv" -NoTypeInformation
	Write-Host "Completed user migration" -ForegroundColor Green
			
}

# SP Configure Functions

Function Export-SQLSPConfigure     {
 <#
            .SYNOPSIS
              Exports advanced sp_configure global configuration options to sql file.

            .EXAMPLE
               $sql = Export-SQLSPConfigure $sourceserver

            .OUTPUTS
                SQL formatted string.
			
        #>
		[CmdletBinding()]
        param(
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [object]$server	
		)
		

	$timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
	$filename = "$($sourceserver.name.replace('\','$'))-$timenow-sp_configure.sql"
	Set-Content -Path $filename "EXEC sp_configure 'show advanced options' , 1;  RECONFIGURE WITH OVERRIDE"
	
	$server.Configuration.ShowAdvancedOptions.ConfigValue = $true
	$server.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE")
	foreach ($sourceprop in $server.Configuration.Properties) {
		$displayname = $sourceprop.DisplayName
		$configvalue = $sourceprop.ConfigValue
		Add-Content -Path $filename "EXEC sp_configure '$displayname' , $configvalue; RECONFIGURE WITH OVERRIDE"
	}
	$server.Configuration.ShowAdvancedOptions.ConfigValue = $false
	$server.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE")
	
	Write-Host "Completed SQL sp_configure export" -ForegroundColor Green
	
	return $filename
}

Function Import-SQLSPConfigure     {
 <#
            .SYNOPSIS
              Updates sp_configure settings on destination server.

            .EXAMPLE
                Import-SQLSPConfigure $sourceserver $destserver

            .OUTPUTS
                $true if success
                $false if failure

#>
		[cmdletbinding(SupportsShouldProcess = $true)] 
        param(
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [object]$sourceserver,
			
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [object]$destserver
			
		)
		
		$sqlfilename = Export-SQLSPConfigure $sourceserver

		if ($sourceserver.versionMajor -ne $destserver.versionMajor) {
			Throw "Source SQL Server major version and Destination SQL Server major version must match for sp_configure migration. Check the exported sql file, $sqlfilename, and run manually."
	}
	
		If ($Pscmdlet.ShouldProcess($destination,"Execute sp_configure")) {
			$sourceserver.Configuration.ShowAdvancedOptions.ConfigValue = $true
			$sourceserver.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE")
			$destserver.Configuration.ShowAdvancedOptions.ConfigValue = $true
			$destserver.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE")

			$destprops = $destserver.Configuration.Properties

			foreach ($sourceprop in $sourceserver.Configuration.Properties) {
				$displayname = $sourceprop.DisplayName
				
				$destprop = $destprops | where-object{$_.Displayname -eq $displayname}
				if ($destprop -ne $null) {
					try { 
						$destprop.configvalue = $sourceprop.configvalue
						$destserver.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE")
						Write-Host "updated $($destprop.displayname) to $($sourceprop.configvalue)" -ForegroundColor Green
					} catch { Write-Host "Could not $($destprop.displayname) to $($sourceprop.configvalue)" -ForegroundColor Red } 
				}
			}
			try { $destserver.Configuration.Alter() } catch { $needsrestart = $true }
			$sourceserver.Configuration.ShowAdvancedOptions.ConfigValue = $false
			$sourceserver.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE")
			$destserver.Configuration.ShowAdvancedOptions.ConfigValue = $false
			$destserver.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE")

			if ($needsrestart -eq $true) { Write-Warning "Some configuration options will be updated once SQL Server is restarted." 
			} else { Write-Host "Configuration option has been updated." -ForegroundColor Green }
		}
	return $true
}

# Agent Functions

Function Test-SQLAgent  {
 <#
            .SYNOPSIS
              Checks to see if SQL Server Agent is running on a server.  

            .EXAMPLE
              if (!(Test-SQLAgent $server)) { Write-Host "SQL Agent not running on $($server.name)."  }

            .OUTPUTS
                $true if running and accessible
                $false if not running or inaccessible
			
        #>
		[CmdletBinding()]
        param(
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [object]$server
			
		)
	if ($server.JobServer -eq $null) { return $false }
	try { $null = $server.JobServer.script(); return $true } catch { return $false }
}

Function Copy-Sqljobs      {
 <#
            .SYNOPSIS
              Copies ProxyAccounts, JobSchedule, SharedSchedules, AlertSystem, JobCategories, 
			  OperatorCategories AlertCategories, Alerts, TargetServerGroups, TargetServers, 
			  Operators, Jobs, Mail and general SQL Agent settings from one SQL Server Agent 
			  to another. $sourceserver and $destserver are SMO server objects. Ignores -force:
			  does not drop and recreate.

            .EXAMPLE
               Copy-Sqljobs $sourceserver $destserver  

            .OUTPUTS
                $true if success
                $false if failure
			
        #>
		[cmdletbinding(SupportsShouldProcess = $true)] 
        param(
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [object]$sourceserver,
			
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [object]$destserver	
		)
		
	if (!(Test-SQLAgent $sourceserver)) { Write-Host "SQL Agent not running on $source. Halting job import." -ForegroundColor Red; return }
	if (!(Test-SQLAgent $sourceserver)) { Write-Host "SQL Agent not running on $destination. Halting job import." -ForegroundColor Red; return }
	$timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
	$csvfilename = "$($sourceserver.name.replace('\','$'))-to-$($destserver.name.replace('\','$'))-$timenow"
	
	$sourceagent = $sourceserver.jobserver
	$migratedjob = @{}; $skippedjob = @{}
	
	$jobobjects = "ProxyAccounts","JobSchedule","SharedSchedules","AlertSystem","JobCategories","OperatorCategories"
	$jobobjects += "AlertCategories","Alerts","TargetServerGroups","TargetServers","Operators", "Jobs", "Mail"
	
	$errorcount = 0
	foreach ($jobobject in $jobobjects) {
		foreach($agent in $sourceagent.($jobobject)) {		
		$agentname = $agent.name
		If ($Pscmdlet.ShouldProcess($destination,"Adding $jobobject $agentname")) {
			Write-Host "Attempting migration of $jobobject $agentname" -ForegroundColor Yellow
				try {
				$sql = $agent.script()	
				$null = $destserver.ConnectionContext.ExecuteNonQuery($sql)
				$migratedjob["$jobobject $agentname"] = "Successfully added"
				Write-Host "Successfully migrated jobobject $agentname" -ForegroundColor Green
				} 
				catch { 
					if ($_.Exception -like '*duplicate*' -or $_.Exception -like '*exist*') {
						$skippedjob.Add("$jobobject $agentname","Skipped. $agentname exists at destination.") }
					else { $skippedjob["$jobobject $agentname"] = $_.Exception.Message }
				}
			}
		}
	 }
	
	$migratedjob.GetEnumerator() | Sort-Object | Select Name, Value | Export-Csv -Path "$csvfilename-jobs.csv" -NoTypeInformation
	$skippedjob.GetEnumerator() | Sort-Object | Select Name, Value | Export-Csv -Append -Path "$csvfilename-jobs.csv" -NoTypeInformation
	
	Write-Host "`nCompleted job migration" -ForegroundColor Green
}

# Supporting Database Functions

Function Update-SQLdbowner  { 
        <#
            .SYNOPSIS
                Updates specified database dbowner.

            .EXAMPLE
                Update-SQLdbowner $sourceserver $destserver -dbname $dbname

            .OUTPUTS
                $true if success
                $false if failure
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
            [string]$dbname
        )

		$destdb = $destserver.databases[$dbname]
		$dbowner = $sourceserver.databases[$dbname].owner
		
		if ($dbowner -eq $null -or $destserver.logins[$dbowner] -eq $null) { $dbowner = 'sa' }
				
		try {
			if ($destdb.ReadOnly -eq $true) 
			{
				$changeroback = $true
				Update-SQLdbReadOnly $destserver $dbname $false
			}
			
			$destdb.SetOwner($dbowner)
			Write-Host "Changed $dbname owner to $dbowner." -ForegroundColor Green
			
			if ($changeroback) {
				Update-SQLdbReadOnly $destserver $dbname $true
				$changeroback = $null
			}
			
			return $true
		} catch { 
			Write-Host "Failed to update $dbname owner to $dbowner." -ForegroundColor Red
			return $false 
		}
}

Function Update-SQLdbReadOnly  { 
        <#
            .SYNOPSIS
                Updates specified database to read-only or read-write. Necessary because SMO doesn't appear to support NO_WAIT.

            .EXAMPLE
               Update-SQLdbReadOnly $server $dbname $true

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
            [bool]$readonly
        )
		
		if ($readonly) {
			$sql = "ALTER DATABASE [$dbname] SET READ_ONLY WITH NO_WAIT"
		} else {
			$sql = "ALTER DATABASE [$dbname] SET READ_WRITE WITH NO_WAIT"
		}

		try {
			$null = $server.ConnectionContext.ExecuteNonQuery($sql)
			Write-Host "Changed ReadOnly status to $readonly for $dbname on $($server.name)." -ForegroundColor Green
			return $true
		} catch { 
			Write-Host "Could not change readonly status for $dbname on $($server.name)" -ForegroundColor Red
			return $false }

}

Function Start-SQLFileTransfer  {
 <#
	SYNOPSIS
	Uses BITS to transfer detached files (.mdf, .ndf, .ldf, and filegroups) to 
	another server over admin UNC paths. Locations of data files are kept in the
	custom object generated by Get-SQLFileStructures

	.EXAMPLE
	 $result = Start-SQLFileTransfer $filestructure $dbname

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
			Write-Host "Copied $fn for $dbname" -ForegroundColor DarkGreen
		} catch { return $false }
	}
	return $true
}

Function Copy-UserObjectsinSysDBs  { 
        <#
            .SYNOPSIS
                Imports user objects found in source SQL Server's master, msdb and model databases to the destination.
				This is useful because many DBA's store backup/maintenance procs (among other things) in master or msdb.
				If Copy-UserObjectsinSysDBs is called via -Everything, the objects are just exported to a .sql file, 
				not actually imported to the destination (unless -force is used).

            .EXAMPLE
               Copy-UserObjectsinSysDBs $sourceserver $destserver

            .OUTPUTS
                $true
        #>
		[CmdletBinding()]
        param(
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [object]$sourceserver,
			
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [object]$destserver
        )
			
	$systemdbs = "master","model","msdb"
	$timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
	
	foreach ($systemdb in $systemdbs) {
		$sysdb = $sourceserver.databases[$systemdb]
		$logfile = "$($sourceserver.name.replace('\','$'))-to-$($destserver.name.replace('\','$'))-$timenow-$systemdb-updates.sql"
		$transfer = New-Object Microsoft.SqlServer.Management.Smo.Transfer $sysdb
		$transfer.CopyAllObjects = $false
		$transfer.CopyAllDatabaseTriggers = $true
		$transfer.CopyAllTables = $true
		$transfer.CopyAllViews = $true
		$transfer.CopyAllStoredProcedures = $true
		$transfer.CopyAllUserDefinedAggregates = $true
		$transfer.CopyAllUserDefinedDataTypes = $true
		$transfer.CopyAllUserDefinedTableTypes = $true
		$transfer.CopyAllUserDefinedTypes = $true
		$transfer.PreserveDbo = $true
		$transfer.Options.AllowSystemObjects = $false
		$transfer.Options.ContinueScriptingOnError = $true
		Write-Host "Migrating user objects in $systemdb" -ForegroundColor Yellow
		try { 
			$sqlQueries = $transfer.scriptTransfer()
			foreach ($query in $sqlQueries) {				
				Add-Content $logfile "$query`r`nGO"
				try {
					if (($everything -and $force) -or !$everything) {
						$destserver.Databases[$systemdb].ExecuteNonQuery($query)
					}
				} catch {}  # This usually occurs if there are existing objects in destination
			}
		} catch { Write-Host "Exception caught." -ForegroundColor Yellow}
	}
	return $true
}

Function Drop-SQLDatabase {
 <#
            .SYNOPSIS
             Uses SMO's KillDatabase to drop all user connections then drop a database. $server is
			 an SMO server object.

            .EXAMPLE
              Drop-SQLDatabase $server $dbname

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
		
	try {
		$server.KillDatabase($dbname)
		$server.refresh()
		Write-Host "Successfully dropped $dbname on $($server.name)." -ForegroundColor Green
		return $true
	}
	catch {	return $false }
}

Function Get-SQLDefaultPaths     {
 <#
            .SYNOPSIS
			Gets the default data and log paths for SQL Server. Needed because SMO's server.defaultpath is sometimes null.

            .EXAMPLE
            $directory = Get-SQLDefaultPaths $server data
			$directory = Get-SQLDefaultPaths $server log

            .OUTPUTS
              String with file path.
			
        #>
		[CmdletBinding()]
        param(
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [object]$server,
			
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [string]$filetype
		)
		
	switch ($filetype) { "data" { $filetype = "mdf" } "log" {  $filetype = "ldf" } }
	
	if ($filetype -eq "ldf") {
		# First attempt
		$filepath = $server.DefaultLog
		# Second attempt
		if ($filepath.Length -eq 0) { $filepath = $server.Information.MasterDBLogPath }
		# Third attempt
		if ($filepath.Length -eq 0) {
			$sql = "select SERVERPROPERTY('InstanceDefaultLogPath') as physical_name"
			$filepath = $server.ConnectionContext.ExecuteScalar($sql)
		}
	} else {
		# First attempt
		$filepath = $server.DefaultFile
		# Second attempt
		if ($filepath.Length -eq 0) { $filepath = $server.Information.MasterDBPath }
		# Third attempt
		if ($filepath.Length -eq 0) {
			 $sql = "select SERVERPROPERTY('InstanceDefaultDataPath') as physical_name"
			 $filepath = $server.ConnectionContext.ExecuteScalar($sql)
		}
	}
	
	if ($filepath.Length -eq 0) { throw "Cannot determine the required directory path." }
	$filepath = $filepath.TrimEnd("\")
	return $filepath
}

Function Join-AdminUNC {
 <#
            .SYNOPSIS
             Parses a path to make it an admin UNC.   

            .EXAMPLE
             Join-AdminUNC sqlserver C:\windows\system32
			 Output: \\sqlserver\c$\windows\system32
			 
            .OUTPUTS
             String
			
        #>
		[CmdletBinding()]
        param(
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [string]$servername,
			
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [string]$filepath
			
		)
		
	if (!$filepath) { return }
	if ($filepath.StartsWith("\\")) { return $filepath }

	if ($filepath.length -gt 0 -and $filepath -ne [System.DBNull]::Value) {
		$newpath = Join-Path "\\$servername\" $filepath.replace(':\','$\')
		return $newpath
	}
	else { return }
}

Function Test-SQLSA      {
 <#
            .SYNOPSIS
              Ensures sysadmin account access on SQL Server. $server is an SMO server object.

            .EXAMPLE
              if (!(Test-SQLSA $server)) { throw "Not a sysadmin on $source. Quitting." }  

            .OUTPUTS
                $true if syadmin
                $false if not
			
        #>
		[CmdletBinding()]
        param(
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [object]$server	
		)
		
try {
		return ($server.ConnectionContext.FixedServerRoles -match "SysAdmin")
	}
	catch { return $false }
}

Function Get-NetBIOSName {
 <#
	.SYNOPSIS
	Takes a best guess at the NetBIOS name of a server. 

	.EXAMPLE
	$sourcenetbios = Get-NetBIOSName $server
	
	.OUTPUTS
	  String with netbios name.
			
 #>
		[CmdletBinding()]
        param(
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [object]$server
		)

	$servernetbios = $server.ComputerNamePhysicalNetBIOS
	
	if ($servernetbios -eq $null) {
		$servernetbios = ($server.name).Split("\")[0]
		$servernetbios = $servernetbios.Split(",")[0]
	}
	
	return $($servernetbios.ToLower())
}

}

PROCESS {
	$elapsed = [System.Diagnostics.Stopwatch]::StartNew() 
	$started = Get-Date
	<# ----------------------------------------------------------
		Sanity Checks
			- Is SMO available?
			- Are all required params there?
			- Are SQL Servers reachable?
			- Is the account running this script an admin?
			- Are SQL Versions >= 2000?
			- If specified, is $NetworkShare valid?
	---------------------------------------------------------- #>
	# One user reported that the #Requires line didn't prevent the script from running, so let's double check
	if ((Get-Host).Version.Major -lt 3) { throw "PowerShell 3.0 and above required." }
	
	if ($source -eq $destination) { throw "Source and Destination SQL Servers are the same. Quitting." }

	if ($Everything -eq $true) { 
		$AllUserDBs = $true; $IncludeSupportDBs = $true; 
		$AllLogins = $true; $MigrateJobServer = $true; 
		$ExportSPConfigure = $true; $MigrateUserObjectsinSysDBs = $true
	}
	
	if (($AllUserDBs -or $IncludeSupportDBs -or $IncludeDBs.IsSet) -and !$DetachAttach -and !$BackupRestore) {
      throw "You must specify -DetachAttach or -BackupRestore when migrating databases."
    }

	if (!([string]::IsNullOrEmpty($NetworkShare))) {
		if (!($NetworkShare.StartsWith("\\"))) {
			throw "Network share must be a valid UNC path (\\server\share)." 
		}
		
		if (!(Test-Path $NetworkShare)) {
			throw "Specified network share does not exist or cannot be accessed." 
		}
	}

	if ([Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMO") -eq $null )
	{ throw "Quitting: SMO Required. You can download it from http://goo.gl/R4yA6u" }

	if ([Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMOExtended") -eq $null )
	{ throw "Quitting: Extended SMO Required. You can download it from http://goo.gl/R4yA6u" }
	
	Write-Host "Attempting to connect to SQL Servers.."  -ForegroundColor Green
	$sourceserver = New-Object Microsoft.SqlServer.Management.Smo.Server $source
	$destserver = New-Object Microsoft.SqlServer.Management.Smo.Server $destination
	
	if ($UseSqlLoginSource -eq $true) {
		$sourcemsg = "Enter the SQL Login credentials for the SOURCE server, $($source.ToUpper())"; 
		$sourceserver.ConnectionContext.LoginSecure = $false
		$sourcelogin = Get-Credential -Message $sourcemsg
		$sourceserver.ConnectionContext.set_Login($sourcelogin.username)
		$sourceserver.ConnectionContext.set_SecurePassword($sourcelogin.Password)
	}
	
	if ($UseSqlLoginDestination -eq $true) {
		$destmsg = "Enter the SQL Login credentials for the DESTINATION server, $($destination.ToUpper())"; 
		$destserver.ConnectionContext.LoginSecure = $false
		$destlogin = Get-Credential -Message $destmsg
		$destserver.ConnectionContext.set_Login($destlogin.username)
		$destserver.ConnectionContext.Set_SecurePassword($destlogin.Password)	
	}
		
	try { $sourceserver.ConnectionContext.Connect() } catch { throw "Can't connect to $source or access denied. Quitting." }
	try { $destserver.ConnectionContext.Connect() } catch { throw "Can't connect to $destination or access denied. Quitting." }

	$sourceserver.ConnectionContext.Disconnect()
	$destserver.ConnectionContext.Disconnect()
	$sourceserver = New-Object Microsoft.SqlServer.Management.Smo.Server $source
	$destserver = New-Object Microsoft.SqlServer.Management.Smo.Server $destination
	$sourceserver.ConnectionContext.ConnectTimeout = 0
	$destserver.ConnectionContext.ConnectTimeout = 0
	$sourceserver.ConnectionContext.Connect() 
	$destserver.ConnectionContext.Connect()
	
	
	if ($sourceserver.versionMajor -lt 8 -and $destserver.versionMajor -lt 8) {
		throw "This script can only be run on SQL Server 2000 and above. Quitting." 
	}
	
	if ($destserver.versionMajor -lt 9 -and $DetachAttach) {
		throw "Detach/Attach not supported when destination SQL Server is version 2000. Quitting." 
	}
	if ($sourceserver.versionMajor -lt 9 -and $destserver.versionMajor -gt 10) {
		throw "SQL Server 2000 databases cannot be migrated to SQL Server versions 2012 and above. Quitting." 
	}
	if ($sourceserver.versionMajor -lt 9 -and $ReattachAtSource) { 
		throw "-ReattachAtSource was specified, but is not supported in SQL Server 2000. Quitting."
	}
	if ($sourceserver.versionMajor -eq 9 -and $destserver.versionMajor -gt 9 -and !$BackupRestore -and !$Force -and $DetachAttach)  {
		throw "Backup and restore is the safest method for migrating from SQL Server 2005 to other SQL Server versions.
		Please use the -BackupRestore switch or override this requirement by specifying -Force." 
	}
		
	if (!(Test-SQLSA $sourceserver)) { throw "Not a sysadmin on $source. Quitting." }
	if (!(Test-SQLSA $destserver)) { throw "Not a sysadmin on $destination. Quitting." }
	
	<# ----------------------------------------------------------
		Preps
	---------------------------------------------------------- #>

	# Convert from RuntimeDefinedParameter  object to regular array
	if ($IncludeDBs.Value -ne $null) {$IncludeDBs = @($IncludeDBs.Value)}  else {$IncludeDBs = $null}
	if ($ExcludeDBs.Value -ne $null) {$ExcludeDBs = @($ExcludeDBs.Value)}  else {$ExcludeDBs = $null}
	if ($IncludeLogins.Value -ne $null) {$IncludeLogins = @($IncludeLogins.Value)}  else {$IncludeLogins = $null}
	if ($ExcludeLogins.Value -ne $null) {$ExcludeLogins = @($ExcludeLogins.Value)}  else {$ExcludeLogins = $null}
	
	if (($IncludeDBs -or $ExcludeDBs) -and (!$DetachAttach -and !$BackupRestore)) {
		throw "You did not select a migration method. Please use -BackupRestore or -DetachAttach"
	}
	
	if ((!$IncludeDBs -and !$AllUserDBs) -and ($DetachAttach -or $BackupRestore)) {
		throw "You did not select any databases to migrate. Please use -AllUserDBs or -IncludeDBs"
	}
	
	# SMO's filestreamlevel is sometimes null
	$sql = "select coalesce(SERVERPROPERTY('FilestreamConfiguredLevel'),0) as fs"
	$sourcefilestream = $sourceserver.ConnectionContext.ExecuteScalar($sql)
	$destfilestream = $destserver.ConnectionContext.ExecuteScalar($sql)
	if ($sourcefilestream -gt 0 -and $destfilestream -eq 0)  { $fswarning = $true }
	
	<# ----------------------------------------------------------
		Run
	---------------------------------------------------------- #>

	if ($AllUserDBs -or !([string]::IsNullOrEmpty($ExcludeDBs)) -or $IncludeSupportDBs -or !([string]::IsNullOrEmpty($IncludeDBs)))
	{ 
		Copy-SqlDatabases  -sourceserver $sourceserver -destserver $destserver -AllUserDBs $AllUserDBs `
		 -IncludeDBs $IncludeDBs -ExcludeDBs $ExcludeDBs -IncludeSupportDBs $IncludeSupportDBs -Force $force
	}
	
	if ($AllLogins -or $IncludeLogins) {  Write-Host "Attempting User Migration" -ForegroundColor Green; 
		Copy-SqlLogins -sourceserver $sourceserver -destserver $destserver -includelogins $IncludeLogins `
		-excludelogins $ExcludeLogins -Force $force
	}		
	
	if ($MigrateJobServer) { Write-Host "Attempting Job Server Migration" -ForegroundColor Green; Copy-Sqljobs $sourceserver $destserver }
	if ($MigrateUserObjectsinSysDBs) { 
		Write-Host "Attempting MigrateUserObjectsinSysDBs" -ForegroundColor Green 
		$null = Copy-UserObjectsinSysDBs $sourceserver $destserver 
	}
	
	if ($ExportSPconfigure) { 
		if ($sourceserver.versionMajor -lt 9 -or $destserver.versionMajor -lt 9) {
			Write-Host "Windows 2000 not supported for sp_configure export. Skipped." -ForegroundColor Red
		} else {	
			Write-Host "Attempting sp_configure export" -ForegroundColor Green
			$null = Export-SQLSPConfigure $sourceserver
		}
	}
	
	if ($RunSPConfigure) {
		if ($sourceserver.versionMajor -lt 9 -or $destserver.versionMajor -lt 9) {
				Write-Host "Windows 2000 not supported for sp_configure export. Skipped." -ForegroundColor Red
		} else {
				Write-Host "Attempting sp_configure export" -ForegroundColor Green
				$result = Import-SQLSPConfigure $sourceserver $destserver
		}
	}
}

END {
	$totaltime = ($elapsed.Elapsed.toString().Split(".")[0])
	$sourceserver.ConnectionContext.Disconnect()
	$destserver.ConnectionContext.Disconnect()
	Write-Host "Script completed" -ForegroundColor Green
	Write-Host "Migration started: $started"  -ForegroundColor Cyan
	Write-Host "Migration completed: $(Get-Date)"  -ForegroundColor Cyan
	Write-Host "Total Elapsed time: $totaltime"  -ForegroundColor Cyan
	if ($networkshare.length -gt 0) { Write-Warning "This script does not delete backup files. Backups may still exist at $networkshare." }
}