Function Start-SqlMigration {
<# 
.SYNOPSIS 
Migrates SQL Server *ALL* databases, logins, database mail profies/accounts, credentials, SQL Agent objects, linked servers, 
Central Management Server objects, server configuration settings (sp_configure), user objects in systems databases,
system triggers and backup devices from one SQL Server to another. 

For more granular control, please use one of the -Skip parameters and use the other functions available within the dbatools module.

Automatically outputs a transcript to disk.

.DESCRIPTION 

Start-SqlMigration consolidates most of the migration tools in dbatools into one command.  This is useful when you're looking to migrate entire instances. It less flexible than using the underlying functions. Think of it as an easy button. It migrates:

All user databases. Use -SkipDatabases to skip.
All logins. Use -SkipLogins to skip.
All database mail objects. Use -SkipDatabaseMail
All credentials. Use -SkipCredentials to skip.
All objects within the Job Server (SQL Agent). Use -SkipJobServer to skip.
All linked servers. Use -SkipLinkedServers to skip.
All groups and servers within Central Management Server. Use -SkipCentralManagementServer to skip.
All SQL Server configuration objects (everything in sp_configure). Use -SkipSpConfigure to skip.
All user objects in system databases. Use -SkipSysDbUserObjects to skip.
All system triggers. Use -SkipSystemTriggers to skip.
All system backup devices. Use -SkipBackupDevices to skip.

This script provides the ability to migrate databases using detach/copy/attach or backup/restore. SQL Server logins, including passwords, SID and database/server roles can also be migrated. In addition, job server objects can be migrated and server configuration settings can be exported or migrated. This script works with named instances, clusters and SQL Express.

By default, databases will be migrated to the destination SQL Server's default data and log directories. You can override this by specifying -ReuseFolderStructure. Filestreams and filegroups are also migrated. Safety is emphasized.

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

.PARAMETER Source
Source SQL Server. You must have sysadmin access and server version must be > SQL Server 7.

.PARAMETER Destination
Destination SQL Server. You must have sysadmin access and server version must be > SQL Server 7.

.PARAMETER SourceSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, this pass $scred object to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.PARAMETER DestinationSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$dcred = Get-Credential, this pass this $dcred to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

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

.PARAMETER SetSourceReadOnly
Sets all migrated databases to ReadOnly prior to detach/attach & backup/restore. If -Reattach is used, db is set to read-only after reattach.

.PARAMETER SkipDatabases
Skips the database migration.

.PARAMETER SkipLogins
Skips the login migration.

.PARAMETER SkipJobServer
Skips the job server (SQL Agent) migration.

.PARAMETER SkipCredentials
Skips the credential migration.

.PARAMETER SkipLinkedServers
Skips the Linked Server migration.

.PARAMETER SkipSpConfigure
Skips the global configuration migration.

.PARAMETER SkipCentralManagementServer
Skips the CMS migration.

.PARAMETER SkipDatabaseMail
Skips the database mail migration.

.PARAMETER SkipSysDbUserObjects
Skips the import of user objects found in source SQL Server's master, msdb and model databases to the destination.

.PARAMETER SkipSystemTriggers
Skips the System Triggers migration.

.PARAMETER SkipBackupDevices
Skips the backup device migration.

.PARAMETER Force
If migrating users, forces drop and recreate of SQL and Windows logins. 
If migrating databases, deletes existing databases with matching names. 
If using -DetachAttach, -Force will break mirrors and drop dbs from Availability Groups.

For other migration objects, it will just drop existing items and readd, if -force is supported within the udnerlying function.

.PARAMETER CsvLog
Outputs a CSV of some of the results. Left in for backwards compatability, as it's slightly more organized than the transcript.

.NOTES 
Author  : Chrissy LeMaire
Limitations: 	Doesn't cover what it doesn't cover (replication, certificates, etc)
			SQL Server 2000 login migrations have some limitations (server perms aren't migrated)
			SQL Server 2000 databases cannot be directly migrated to SQL Server 2012 and above.
			Logins within SQL Server 2012 and above logins cannot be migrated to SQL Server 2008 R2 and below.	

dbatools PowerShell module (http://git.io/b3oo, clemaire@gmail.com)
Copyright (C) 2105 Chrissy LeMaire

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
https://gallery.technet.microsoft.com/scriptcenter/Use-PowerShell-to-Migrate-86c841df/

.EXAMPLE   
Start-SqlMigration -Source sqlserver\instance -Destination sqlcluster -DetachAttach 

Description

All databases, logins, job objects and sp_configure options will be migrated from sqlserver\instance to sqlcluster. Databases will be migrated using the detach/copy files/attach method. Dbowner will be updated. User passwords, SIDs, database roles and server roles will be migrated along with the login.

.EXAMPLE  
Start-SqlMigration -Verbose -Source sqlcluster -Destination sql2016 -SourceSqlCredential $scred -ReuseFolderstructure -DestinationSqlCredential $cred -Force -NetworkShare \\fileserver\share\sqlbackups\Migration -BackupRestore

Migrate databases uses backup/restore. Also migrate logins, database mail, credentials, SQL Agent, Central Management Server, SQL global configuration.

.EXAMPLE
Start-SqlMigration -Verbose -Source sqlcluster -Destination sql2016 -SkipDatabases -SkipLogins

Migrates everything but logins and databases.

.EXAMPLE
Start-SqlMigration -Verbose -Source sqlcluster -Destination sql2016 -DetachAttach -Reattach -SetSourceReadonly

Migrate databases using detach/copy/attach. Reattach at source and set source databases read-only. Also migrates everything else. 

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
	[switch]$NoRecovery,
	[System.Management.Automation.PSCredential]$SourceSqlCredential,
	[System.Management.Automation.PSCredential]$DestinationSqlCredential,
	[switch]$SkipDatabases,
	[switch]$SkipLogins,
	[switch]$SkipJobServer,
	[switch]$SkipCredentials,
	[switch]$SkipLinkedServers,
	[switch]$SkipSpConfigure,
	[switch]$SkipCentralManagementServer,
	[switch]$SkipDatabaseMail,
	[switch]$SkipSysDbUserObjects,
	[switch]$SkipSystemTriggers,
	[switch]$SkipBackupDevices,
	[switch]$Force,
	[switch]$CsvLog
	)

BEGIN { 
	$transcript = ".\dbatools-startmigration-transcript.txt"
	if (Test-Path $transcript) { Start-Transcript -Path $transcript -Append }
	else  { Start-Transcript -Path $transcript }
}

PROCESS {
	
	
	$elapsed = [System.Diagnostics.Stopwatch]::StartNew() 
	$started = Get-Date
	
	$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
	$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential

	$source = $sourceserver.name
	$destination = $destserver.name	


	if (!$SkipCredentials) {
		Write-Output "`n`nMigrating SQL credentials"
		try { Copy-SqlCredential -Source $sourceserver.name -Destination $destserver.name -Force:$Force
		} catch { Write-Error "Credential migration reported the following error $($_.Exception.Message) "}
	}
		
	if (!$SkipDatabases) {
		# Test some things
		if ($networkshare.length -gt 0) {$netshare += "-NetworkShare $NetworkShare" }
			if (!$DetachAttach -and !$BackupRestore) { throw "You must specify a migration method using -BackupRestore or -DetachAttach."}
		# Do it
		Write-Output "`nMigrating databases"
		try {
			if ($BackupRestore) {
				Copy-SqlDatabase -Source $sourceserver -Destination $destserver -All -SetSourceReadOnly:$SetSourceReadOnly -ReuseFolderstructure:$ReuseFolderstructure -BackupRestore -NetworkShare $NetworkShare -Force:$Force -CsvLog:$csvlog -NoRecovery:$NoRecovery
			} else {
				Copy-SqlDatabase -Source $sourceserver -Destination $destserver -All -SetSourceReadOnly:$SetSourceReadOnly -ReuseFolderstructure:$ReuseFolderstructure -DetachAttach:$DetachAttach -Reattach:$Reattach -Force:$Force -CsvLog:$csvlog
			}
		} catch { Write-Error "Database migration reported the following error $($_.Exception.Message)" }
	}

	if (!$SkipSysDbUserObjects) {
	Write-Output "`n`nMigrating user objects in system databases (this can take a second)"
	try { 
			If ($Pscmdlet.ShouldProcess($destination,"Copying user objects.")) {
			Copy-SqlSysDbUserObjects -Source $sourceserver -Destination $destserver
		}
	
	} catch { Write-Error "Couldn't copy all user objects in system databases." }
}

	if (!$SkipLogins) {
		Write-Output "`n`nMigrating logins"
		try { 
			Copy-SqlLogin -Source $sourceserver -Destination $destserver -Force:$Force -CsvLog:$csvlog
		} catch { Write-Error "Login migration reported the following error $($_.Exception.Message) "}
	}

	if (!$SkipLogins -and !$SkipDatabases -and !$NoRecovery) {
		Write-Output "`n`nUpdating database owners to match newly migrated logins"
		try { 
			 Update-SqlDbOwner -Source $sourceserver -Destination $destserver
		} catch { Write-Error "Login migration reported the following error $($_.Exception.Message) "}
	}
		
	if (!$SkipJobServer) {
	Write-Output "`n`nMigrating job server"
		if ($force) { Write-Warning " Copy-SqlJobServer currently does not support force." }
		try { Copy-SqlJobServer -Source $sourceserver -Destination $destserver -CsvLog:$csvlog
		} catch { Write-Error "Job Server migration reported the following error $($_.Exception.Message) "}
	}

	if (!$SkipLinkedServers) {
		Write-Output "`n`nMigrating linked servers"
		try { Copy-SqlLinkedServer -Source $sourceserver -Destination $destserver -Force:$force
		} catch { Write-Error "Linked server migration reported the following error $($_.Exception.Message) "}
	}
	
	if (!$SkipCentralManagementServer) {
		Write-Output "`n`nMigrating Central Management Server"
		
		if ($sourceserver.versionMajor -lt 10 -or $destserver.versionMajor -lt 10) {
		throw "Central Management Server is only supported in SQL Server 2008 and above. Skipping." 
		} else {
			if ($force) { Write-Warning " Copy-SqlCentralManagementServer currently does not support force." }
			try { Copy-SqlCentralManagementServer -Source $sourceserver -Destination $destserver
			} catch { Write-Error "Central Management Server migration reported the following error $($_.Exception.Message)" }
		}
	}	
	
	if (!$SkipDatabaseMail) {
		Write-Output "`n`nMigrating database mail"
		if ($force) { Write-Warning " Copy-SqlDatabaseMail currently does not support force." }
		try { Copy-SqlDatabaseMail -Source $sourceserver -Destination $destserver 
		} catch { Write-Error "Database mail migration reported the following error $($_.Exception.Message)" }
	}	

	if (!$SkipSystemTriggers) {
		Write-Output "`n`nMigrating System Triggers"
		try { Copy-SqlServerTrigger -Source $sourceserver -Destination $destserver -Force:$force
		} catch { Write-Error "System Triggers migration reported the following error $($_.Exception.Message)" }
	}	

	if (!$SkipBackupDevices) {
		Write-Output "`n`nMigrating Backup Devices"
		try { Copy-SqlBackupDevice -Source $sourceserver -Destination $destserver -Force:$force
		} catch { Write-Error "Backup device migration reported the following error $($_.Exception.Message)" }
	}
	
	if (!$SkipSpConfigure) {
		Write-Output "`n`nMigrating SQL Server Configuration"
		try { Import-SqlSpConfigure -Source $sourceserver -Destination $destserver -Force:$force
			} catch { Write-Error "Configuration migration reported the following error $($_.Exception.Message) " }
		}
}

END {
	$totaltime = ($elapsed.Elapsed.toString().Split(".")[0])
	
	if ($sourceserver.ConnectionContext.IsOpen -eq $true) { $sourceserver.ConnectionContext.Disconnect() }
	if ($destserver.ConnectionContext.IsOpen -eq $true) { $destserver.ConnectionContext.Disconnect() }
	
	If ($Pscmdlet.ShouldProcess("console","Showing SQL Server migration finished message")) {
	Write-Output "`n`nSQL Server migration complete"
	Write-Output "Migration started: $started" 
	Write-Output "Migration completed: $(Get-Date)" 
	Write-Output "Total Elapsed time: $totaltime" 
	Stop-Transcript
	}
}
}