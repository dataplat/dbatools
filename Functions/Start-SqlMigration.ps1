Function Start-SqlMigration {
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
 
 .PARAMETER SourceSqlCredential
	Uses SQL Login credentials to connect to Source server. Note this is a switch. You will be prompted to enter your SQL login credentials. 
	
	Windows Authentication will be used if SourceSqlCredential is not specified.
	
	NOTE: Auto-populating parameters (ExcludeDbs, ExcludeLogins, IncludeDbs, IncludeLogins) are populated by the account running the PowerShell script.

 .PARAMETER DestinationSqlCredential
	Uses SQL Login credentials to connect to Destination server. Note this is a switch. You will be prompted to enter your SQL login credentials. 
	
	Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.
	
 .PARAMETER AllUserDbs
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
	By default, databases will be migrated to the destination SQL Server's default data and log directories. You can override this by specifying -ReuseFolderStructure. The same structure will be kept exactly, so consider this if you're migrating between different versions and use part of Microsoft's default SQL structure (MSSQL12.INSTANCE, etc)
	
 .PARAMETER NetworkShare
	Specifies the network location for the backup files. The SQL Service service accounts must read/write permission to access this location.

 .PARAMETER AllLogins
	Migrates all logins, along with their passwords, sids, databasae roles and server roles. Use ExcludeLogins to exclude specific users. Use -force to drop and recreate any existing users on destination. Otherwise, they will be skipped. The 'sa' user and users starting with ## will be skipped. Also updates database owners on destination.

 .PARAMETER ExcludeDbs
	Excludes specified databases when performing -AllUserDbs migrations. This list is auto-populated for tab completion.

 .PARAMETER IncludeDbs
  Migrates ONLY specified databases. This list is auto-populated for tab completion.

 .PARAMETER ExcludeLogins
	Excludes specified logins when performing -AllUserDbs migrations. This list is auto-populated for tab completion.
	
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

 .PARAMETER SysDbUserObjects
	This switch migrates user-created objects in the systems databases to the new server. This is useful for DbA's who create environment specific stored procedures, tables, etc in the master, model or msdb databases.

 .PARAMETER SetSourceReadOnly
	Sets all migrated databases to ReadOnly prior to detach/attach & backup/restore. If -Reattach is used, db is set to read-only after reattach.
 
 .PARAMETER Everything
	Migrates all logins, databases, agent objects, except those listed by ExcludeDbs and ExcludeLogins. 
	Also exports sp_configure settings and user created objects within system databases.
	
.PARAMETER Force
	If migrating users, forces drop and recreate of SQL and Windows logins. 
	If migrating databases, deletes existing databases with matching names. 
	If using -DetachAttach, -Force will break mirrors and drop dbs from Availability Groups.
	MigrateJobServer not supported.
	
 .NOTES 
    Author  : Chrissy LeMaire
    Requires: PowerShell Version 3.0, SQL Server SMO
	DateUpdated: 2015-Sept-22
	Version: 2.0
	Limitations: 	Doesn't cover what it doesn't cover (replication, linked servers, certificates, etc)
					SQL Server 2000 login migrations have some limitations (server perms aren't migrated, etc)
					SQL Server 2000 databases cannot be directly migrated to SQL Server 2012 and above.
					Logins within SQL Server 2012 and above logins cannot be migrated to SQL Server 2008 R2 and below.				

 .LINK 
  	https://gallery.technet.microsoft.com/scriptcenter/Use-PowerShell-to-Migrate-86c841df/

 .EXAMPLE   
Start-SqlMigration -Source sqlserver\instance -Destination sqlcluster -DetachAttach -Everything

Description

All databases, logins, job objects and sp_configure options will be migrated from sqlserver\instance to sqlcluster. Databases will be migrated using the detach/copy files/attach method. Dbowner will be updated. User passwords, SIDs, database roles and server roles will be migrated along with the login.

 .EXAMPLE   
Start-SqlMigration -Source sqlserver\instance -Destination sqlcluster -AllUserDbs -ExcludeDbs Northwind, pubs -IncludeSupportDbs -force -AllLogins -ExcludeLogins nwuser, pubsuser, "corp\domain admins"  -MigrateJobServer -ExportSPconfigure -SourceSqlCredential -DestinationSqlCredential

Description

Prompts for SQL login usernames and passwords on both the Source and Destination then connects to each using the SQL Login credentials. 

All logins except for nwuser, pubsuser and the corp\domain admins group will be migrated from sqlserver\instance to sqlcluster, along with their passwords, server roles and database roles. A logfile named SQLSERVER-SqlCLUSTER-$date-logins.csv will be written to the current directory. Existing SQL users will be dropped and recreated.

Migrates all user databases except for Northwind and pubs by performing the following: kick all users out of the database, detach all data/log files, move files across the network over an admin share (\\SQLSERVER\M$\MSSQL...), attach file on destination server. If the database exists on the destination, it will be dropped prior to attach.

It also includes the support databases (ReportServer, ReportServerTempDb, SSIDb, distribution). 

If the database files (*.mdf, *.ndf, *.ldf) on SQLCLUSTER exist and aren't in use, they will be overwritten. A logfile named SQLSERVER-SqlCLUSTER-$date-Sqls.csv will be written to the current directory.

All job server objects will be migrated. A logfile named SQLSERVER-SqlCLUSTER-$date-jobs.csv will be written to the current directory.

A file named SQLSERVER-SqlCluster-$date-sp_configure.sql with global server configurations will be written to the current directory. This file can then be executed manually on SQLCLUSTER.
#> 
[CmdletBinding(DefaultParameterSetName="Default", SupportsShouldProcess = $true)] 
Param(
	[parameter(Mandatory = $true)]
	[object]$Source,
	[parameter(Mandatory = $true)]
	[object]$Destination,
	
	[switch]$DetachAttach,
	[switch]$BackupRestore,
	[switch]$ReuseFolderstructure,
	[switch]$Reattach,
	[string]$NetworkShare,
	[switch]$SetSourceReadOnly,
	[System.Management.Automation.PSCredential]$SourceSqlCredential,
	[System.Management.Automation.PSCredential]$DestinationSqlCredential,
	[switch]$Force,
	[switch]$SkipDatabases,
	[switch]$SkipLogins,
	[switch]$SkipJobServer,
	[switch]$SkipCredentials,
	[switch]$SkipLinkedServers,
	[switch]$SkipSpConfigure,
	[switch]$SkipCentralManagementServer,
	[switch]$SkipDatabaseMail
	)

BEGIN {}
PROCESS {
	# Just in case
	if ($WhatIf -eq $null) { $WhatIf = $false }
	if ($Force -eq $null) { $Force = $false }
	
	$elapsed = [System.Diagnostics.Stopwatch]::StartNew() 
	$started = Get-Date
	
	$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
	$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential

	$source = $sourceserver.name
	$destination = $destserver.name	

	if (!$SkipDatabases) {
		# Test some things
		if ($networkshare.length -gt 0) {$netshare += "-NetworkShare $NetworkShare" }
			if (!$DetachAttach -and !$BackupRestore) { throw "You must specify a migration method using -BackupRestore or -DetachAttach."}
		# Do it
		Write-Output "Migrating databases..."
		try {
			if ($BackupRestore) {
				Copy-SqlDatabases -Source $sourceserver -Destination $destserver -AllUserDbs -SysDbUserObjects -IncludeSupportDbs -SetSourceReadOnly:$SetSourceReadOnly -ReuseFolderstructure:$ReuseFolderstructure -BackupRestore -NetworkShare $NetworkShare -Force:$force -WhatIf:$whatif
			} else {
				Copy-SqlDatabases -Source $sourceserver -Destination $destserver -AllUserDbs -SysDbUserObjects -IncludeSupportDbs -SetSourceReadOnly:$SetSourceReadOnly -ReuseFolderstructure:$ReuseFolderstructure -DetachAttach:$DetachAttach -Reattach:$Reattach -Force:$force -WhatIf:$whatif
			}
		} catch { Write-Error "Database migration reported the following error $($_.Exception.Message)" }
	}
	
	if (!$SkipCredentials) {
		Write-Output "`n`nMigrating SQL credentials..."
		try { Copy-SqlCredentials -Source $sourceserver -Destination $destserver -Force:$force -WhatIf:$whatif
		} catch { Write-Error "Credential migration reported the following error $($_.Exception.Message) "}
	}
	
	if (!$SkipLogins) {
		Write-Output "`n`nMigrating logins..."
		try { Copy-SqlLogins -Source $sourceserver -Destination $destserver -Force:$force -WhatIf:$whatif
		} catch { Write-Error "Login migration reported the following error $($_.Exception.Message) "}
	}
	
	if (!$SkipJobServer) {
	Write-Output "`n`nMigrating job server..."
		try { Copy-SqlJobServer -Source $sourceserver -Destination $destserver -WhatIf:$whatif
		} catch { Write-Error "Job Server migration reported the following error $($_.Exception.Message) "}
	}
	
	if (!$SkipLinkedServers) {
		Write-Output "`n`nMigrating linked servers..."
		try { Copy-SqlLinkedServers -Source $sourceserver -Destination $destserver -Force:$force -WhatIf:$whatif
		} catch { Write-Error "Linked server migration reported the following error $($_.Exception.Message) "}
	}
	
	if (!$SkipCentralManagementServer) {
		Write-Output "`n`nMigrating Central Management Server..."
		try { Copy-SqlCentralManagementServer -Source $sourceserver -Destination $destserver -WhatIf:$whatif
		} catch { Write-Error "Central Management Server migration reported the following error $($_.Exception.Message)" }
	}	
	
	if (!$SkipDatabaseMail) {
		Write-Output "`n`nMigrating database mail..."
		try { Copy-SqlDatabaseMail -Source $sourceserver -Destination $destserver -WhatIf:$whatif
		} catch { Write-Error "Database mail migration reported the following error $($_.Exception.Message)" }
	}	
	
	if (!$SkipSpConfigure) {
		Write-Output "`n`nMigrating SQL Server Configuration..."
		try { Import-SqlSpConfigure -Source $sourceserver -Destination $destserver -WhatIf:$whatif
			} catch { Write-Error "Configuration migration reported the following error $($_.Exception.Message) " }
		}
}

END {
	$totaltime = ($elapsed.Elapsed.toString().Split(".")[0])
	
	if ($sourceserver.ConnectionContext.IsOpen -eq $true) { $sourceserver.ConnectionContext.Disconnect() }
	if ($destserver.ConnectionContext.IsOpen -eq $true) { $destserver.ConnectionContext.Disconnect() }
	Write-Output "`n`nSQL Server migration complete"
	Write-Output "Migration started: $started" 
	Write-Output "Migration completed: $(Get-Date)" 
	Write-Output "Total Elapsed time: $totaltime" 
}
}