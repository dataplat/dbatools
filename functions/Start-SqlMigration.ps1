Function Start-SqlMigration
{
<# 
.SYNOPSIS 
Migrates SQL Server *ALL* databases, logins, database mail profies/accounts, credentials, SQL Agent objects, linked servers, 
Central Management Server objects, server configuration settings (sp_configure), user objects in systems databases,
system triggers and backup devices from one SQL Server to another. 

For more granular control, please use one of the -No parameters and use the other functions available within the dbatools module.

Automatically outputs a transcript to disk.

.DESCRIPTION 

Start-SqlMigration consolidates most of the migration tools in dbatools into one command.  This is useful when you're looking to migrate entire instances. It less flexible than using the underlying functions. Think of it as an easy button. It migrates:

All user databases. Use -NoDatabases to skip.
All logins. Use -NoLogins to skip.
All database mail objects. Use -NoDatabaseMail
All credentials. Use -NoCredentials to skip.
All objects within the Job Server (SQL Agent). Use -NoAgentServer to skip.
All linked servers. Use -NoLinkedServers to skip.
All groups and servers within Central Management Server. Use -NoCentralManagementServer to skip.
All SQL Server configuration objects (everything in sp_configure). Use -NoSpConfigure to skip.
All user objects in system databases. Use -NoSysDbUserObjects to skip.
All system triggers. Use -NoSystemTriggers to skip.
All system backup devices. Use -NoBackupDevices to skip.
All Audits. Use -NoAudits to skip.
All Endpoints. Use -NoEndpoints to skip.
All Extended Events. Use -NoExtendedEvents to skip.
All Policy Management objects. Use -NoPolicyManagement to skip.
All Resource Governor objects. Use -NoResourceGovernor to skip.
All Server Audit Specifications. Use -NoServerAuditSpecifications to skip.
All Custom Errors (User Defined Messages). Use -NoCustomErrors to skip.
Copies All Data Collector collection sets. Does not configure the server. Use -NoDataCollector to skip.

This script provides the ability to migrate databases using detach/copy/attach or backup/restore. SQL Server logins, including passwords, SID and database/server roles can also be migrated. In addition, job server objects can be migrated and server configuration settings can be exported or migrated. This script works with named instances, clusters and SQL Express.

By default, databases will be migrated to the destination SQL Server's default data and log directories. You can override this by specifying -ReuseSourceFolderStructure. Filestreams and filegroups are also migrated. Safety is emphasized.

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

.PARAMETER Source
Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER Destination
Destination SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

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

.PARAMETER ReuseSourceFolderStructure
By default, databases will be migrated to the destination SQL Server's default data and log directories. You can override this by specifying -ReuseSourceFolderStructure. The same structure will be kept exactly, so consider this if you're migrating between different versions and use part of Microsoft's default SQL structure (MSSQL12.INSTANCE, etc)

.PARAMETER NetworkShare
Specifies the network location for the backup files. The SQL Service service accounts must read/write permission to access this location.

.PARAMETER SetSourceReadOnly
Sets all migrated databases to ReadOnly prior to detach/attach & backup/restore. If -Reattach is used, db is set to read-only after reattach.

.PARAMETER WithReplace
It's exactly WITH REPLACE. This is useful if you want to stage some complex file paths.

.PARAMETER NoDatabases
Skips the database migration.

.PARAMETER NoLogins
Skips the login migration.

.PARAMETER NoAgentServer
Skips the job server (SQL Agent) migration.

.PARAMETER NoCredentials
Skips the credential migration.

.PARAMETER NoLinkedServers
Skips the Linked Server migration.

.PARAMETER NoSpConfigure
Skips the global configuration migration.

.PARAMETER NoCentralManagementServer
Skips the CMS migration.

.PARAMETER NoDatabaseMail
Skips the database mail migration.

.PARAMETER NoSysDbUserObjects
Skips the import of user objects found in source SQL Server's master, msdb and model databases to the destination.

.PARAMETER NoSystemTriggers
Skips the System Triggers migration.

.PARAMETER NoBackupDevices
Skips the backup device migration.

.PARAMETER NoAudits
Skips the Audit migration.

.PARAMETER NoEndpoints
Skips the Endpoin migration.

.PARAMETER NoExtendedEvents
Skips the Extended Event migration.

.PARAMETER NoPolicyManagement
Skips the Policy Management migration.

.PARAMETER NoResourceGovernor
Skips the Resource Governor migration.

.PARAMETER NoServerAuditSpecifications
Skips the Server Audit Specification migration.

.PARAMETER NoCustomErrors
Skips the Custom Error (User Defined Messages) migration.

.PARAMETER NoDataCollector
Skips the Data Collector migration.
	
.PARAMETER NoSaRename
Skips renaming of the sa account to match on destination. 
	
.PARAMETER DisableJobsOnDestination
Disables migrated SQL Agent jobs on destination server

.PARAMETER DisableJobsOnSource
Disables migrated SQL Agent jobs on source server

.PARAMETER Force
If migrating users, forces drop and recreate of SQL and Windows logins. 
If migrating databases, deletes existing databases with matching names. 
If using -DetachAttach, -Force will break mirrors and drop dbs from Availability Groups.

For other migration objects, it will just drop existing items and readd, if -force is supported within the udnerlying function.

.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed.

.NOTES 
Author: Chrissy LeMaire
Limitations: 	Doesn't cover what it doesn't cover (certificates, etc)
				SQL Server 2000 login migrations have some limitations (server perms aren't migrated)
				SQL Server 2000 databases cannot be directly migrated to SQL Server 2012 and above.
				Logins within SQL Server 2012 and above logins cannot be migrated to SQL Server 2008 R2 and below.	

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
https://dbatools.io/Start-SqlMigration

.EXAMPLE   
Start-SqlMigration -Source sqlserver\instance -Destination sqlcluster -DetachAttach 

Description

All databases, logins, job objects and sp_configure options will be migrated from sqlserver\instance to sqlcluster. Databases will be migrated using the detach/copy files/attach method. Dbowner will be updated. User passwords, SIDs, database roles and server roles will be migrated along with the login.

.EXAMPLE  
Start-SqlMigration -Verbose -Source sqlcluster -Destination sql2016 -SourceSqlCredential $scred -ReuseSourceFolderStructure -DestinationSqlCredential $cred -Force -NetworkShare \\fileserver\share\sqlbackups\Migration -BackupRestore

Migrate databases uses backup/restore. Also migrate logins, database mail, credentials, SQL Agent, Central Management Server, SQL global configuration.

.EXAMPLE
Start-SqlMigration -Verbose -Source sqlcluster -Destination sql2016 -NoDatabases -NoLogins

Migrates everything but logins and databases.

.EXAMPLE
Start-SqlMigration -Verbose -Source sqlcluster -Destination sql2016 -DetachAttach -Reattach -SetSourceReadonly

Migrate databases using detach/copy/attach. Reattach at source and set source databases read-only. Also migrates everything else. 

#>	
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	Param (
		[parameter(Position = 1, Mandatory = $true)]
		[object]$Source,
		[parameter(Position = 2, Mandatory = $true)]
		[object]$Destination,
		[parameter(Position = 3, Mandatory = $true, ParameterSetName = "DbAttachDetach")]
		[switch]$DetachAttach,
		[parameter(Position = 4, ParameterSetName = "DbAttachDetach")]
		[switch]$Reattach,
		[parameter(Position = 5, Mandatory = $true, ParameterSetName = "DbBackup")]
		[switch]$BackupRestore,
		[parameter(Position = 6, Mandatory = $true, ParameterSetName = "DbBackup",
				   HelpMessage = "Specify a valid network share in the format \\server\share that can be accessed by your account and both Sql Server service accounts.")]
		[string]$NetworkShare,
		[parameter(Position = 7, ParameterSetName = "DbBackup")]
		[switch]$WithReplace,
		[parameter(Position = 8, ParameterSetName = "DbBackup")]
		[switch]$NoRecovery,
		[parameter(Position = 9, ParameterSetName = "DbBackup")]
		[parameter(Position = 10, ParameterSetName = "DbAttachDetach")]
		[switch]$SetSourceReadOnly,
		[Alias("ReuseFolderStructure")]
		[parameter(Position = 11, ParameterSetName = "DbBackup")]
		[parameter(Position = 12, ParameterSetName = "DbAttachDetach")]
		[switch]$ReuseSourceFolderStructure,
		[parameter(Position = 13, ParameterSetName = "DbBackup")]
		[parameter(Position = 14, ParameterSetName = "DbAttachDetach")]
		[switch]$IncludeSupportDbs,
		[parameter(Position = 15)]
		[System.Management.Automation.PSCredential]$SourceSqlCredential,
		[parameter(Position = 16)]
		[System.Management.Automation.PSCredential]$DestinationSqlCredential,
		[Alias("SkipDatabases")]
		[switch]$NoDatabases,
		[switch]$NoLogins,
		[Alias("SkipJobServer", "NoJobServer")]
		[switch]$NoAgentServer,
		[Alias("SkipCredentials")]
		[switch]$NoCredentials,
		[Alias("SkipLinkedServers")]
		[switch]$NoLinkedServers,
		[Alias("SkipSpConfigure")]
		[switch]$NoSpConfigure,
		[Alias("SkipCentralManagementServer")]
		[switch]$NoCentralManagementServer,
		[Alias("SkipDatabaseMail")]
		[switch]$NoDatabaseMail,
		[Alias("SkipSysDbUserObjects")]
		[switch]$NoSysDbUserObjects,
		[Alias("SkipSystemTriggers")]
		[switch]$NoSystemTriggers,
		[Alias("SkipBackupDevices")]
		[switch]$NoBackupDevices,
		[switch]$NoAudits,
		[switch]$NoEndpoints,
		[switch]$NoExtendedEvents,
		[switch]$NoPolicyManagement,
		[switch]$NoResourceGovernor,
		[switch]$NoServerAuditSpecifications,
		[switch]$NoCustomErrors,
		[switch]$NoDataCollector,
		[switch]$DisableJobsOnDestination,
		[switch]$DisableJobsOnSource,
		[switch]$NoSaRename,
		[switch]$Force
	)
	
	BEGIN
	{
		$docs = [Environment]::GetFolderPath("mydocuments")
		$transcript = "$docs\dbatools-startmigration-transcript.txt"
		
		if (Test-Path $transcript)
		{
			Start-Transcript -Path $transcript -Append
		}
		else
		{
			Start-Transcript -Path $transcript
		}
		
		$elapsed = [System.Diagnostics.Stopwatch]::StartNew()
		$started = Get-Date
		
		$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
		
		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName
	}
	
	PROCESS
	{
		
		if ($BackupRestore -eq $false -and $DetachAttach -eq $false -and $NoDatabases -eq $false)
		{
			throw "You must specify a database migration method (-BackupRestore or -DetachAttach) or -NoDatabases"
		}
		
		if (!$NoSpConfigure)
		{
			Write-Output "`n`nMigrating SQL Server Configuration"
			try
			{
				Copy-SqlSpConfigure -Source $sourceserver -Destination $destserver
			}
			catch { Write-Error "Configuration migration reported the following error $($_.Exception.Message) " }
		}
		
		
		if (!$NoCustomErrors)
		{
			Write-Output "`n`nMigrating custom errors (user defined messages)"
			try
			{
				Copy-SqlCustomError -Source $sourceserver -Destination $destserver -Force:$Force
			}
			catch { Write-Error "Couldn't copy custom errors." }
		}
		
		if (!$NoCredentials)
		{
			if ($sourceserver.versionMajor -lt 9 -or $destserver.versionMajor -lt 9)
			{
				Write-Output "Credentials are only supported in SQL Server 2005 and above. Skipping."
			}
			else
			{
				Write-Output "`n`nMigrating SQL credentials"
				try
				{
					Copy-SqlCredential -Source $sourceserver.name -Destination $destserver.name -Force:$Force
				}
				catch { Write-Error "Credential migration reported the following error $($_.Exception.Message) " }
			}
		}
		
		if (!$NoDatabaseMail)
		{
			if ($sourceserver.versionMajor -lt 9 -or $destserver.versionMajor -lt 9)
			{
				Write-Output "Database Mail is only supported in SQL Server 2005 and above. Skipping."
			}
			else
			{
				Write-Output "`n`nMigrating database mail"
				try
				{
					Copy-SqlDatabaseMail -Source $sourceserver -Destination $destserver -Force:$Force
				}
				catch { Write-Error "Database mail migration reported the following error $($_.Exception.Message)" }
			}
		}
		
		if (!$NoSysDbUserObjects)
		{
			Write-Output "`n`nMigrating user objects in system databases (this can take a second)"
			try
			{
				If ($Pscmdlet.ShouldProcess($destination, "Copying user objects."))
				{
					Copy-SqlSysDbUserObjects -Source $sourceserver -Destination $destserver
				}
				
			}
			catch { Write-Error "Couldn't copy all user objects in system databases." }
		}
		
		if (!$NoCentralManagementServer)
		{
			if ($sourceserver.versionMajor -lt 10 -or $destserver.versionMajor -lt 10)
			{
				Write-Output "Central Management Server is only supported in SQL Server 2008 and above. Skipping."
			}
			else
			{
				Write-Output "`n`nMigrating Central Management Server"
				try
				{
					Copy-SqlCentralManagementServer -Source $sourceserver -Destination $destserver -Force:$Force
				}
				catch
				{
					Write-Error "Central Management Server migration reported the following error $($_.Exception.Message)"
				}
			}
		}
		
		if (!$NoBackupDevices)
		{
			Write-Output "`n`nMigrating Backup Devices"
			try
			{
				Copy-SqlBackupDevice -Source $sourceserver -Destination $destserver -Force:$Force
			}
			catch { Write-Error "Backup device migration reported the following error $($_.Exception.Message)" }
		}
		
		if (!$NoLinkedServers)
		{
			Write-Output "`n`nMigrating linked servers"
			try
			{
				Copy-SqlLinkedServer -Source $sourceserver.name -Destination $destserver.name -Force:$Force
			}
			catch { Write-Error "Linked server migration reported the following error $($_.Exception.Message) " }
		}
		
		if (!$NoSystemTriggers)
		{
			if ($sourceserver.versionMajor -lt 9 -or $destserver.versionMajor -lt 9)
			{
				Write-Output "Server Triggers are only supported in SQL Server 2008 and above. Skipping."
			}
			else
			{
				Write-Output "`n`nMigrating System Triggers"
				try
				{
					Copy-SqlServerTrigger -Source $sourceserver -Destination $destserver -Force:$Force
				}
				catch { Write-Error "System Triggers migration reported the following error $($_.Exception.Message)" }
			}
		}
		
		################################################################################################################################################################
		
		if (!$NoDatabases)
		{
			# Test some things
			if ($networkshare.length -gt 0) { $netshare += "-NetworkShare $NetworkShare" }
			if (!$DetachAttach -and !$BackupRestore) { throw "You must specify a migration method using -BackupRestore or -DetachAttach." }
			# Do it
			Write-Output "`nMigrating databases"
			try
			{
				if ($BackupRestore)
				{
					Copy-SqlDatabase -Source $sourceserver -Destination $destserver -All -SetSourceReadOnly:$SetSourceReadOnly -ReuseSourceFolderStructure:$ReuseSourceFolderStructure -BackupRestore -NetworkShare $NetworkShare -Force:$Force -NoRecovery:$NoRecovery -WithReplace:$WithReplace
				}
				else
				{
					Copy-SqlDatabase -Source $sourceserver -Destination $destserver -All -SetSourceReadOnly:$SetSourceReadOnly -ReuseSourceFolderStructure:$ReuseSourceFolderStructure -DetachAttach:$DetachAttach -Reattach:$Reattach -Force:$Force
				}
			}
			catch { Write-Error "Database migration reported the following error $($_.Exception.Message)" }
		}
		
		
		if (!$NoLogins)
		{
			Write-Output "`n`nMigrating logins"
			try
			{
				if ($NoSaRename -eq $false)
				{
					Copy-SqlLogin -Source $sourceserver -Destination $destserver -Force:$Force -SyncSaName
				}
				else
				{
					Copy-SqlLogin -Source $sourceserver -Destination $destserver -Force:$Force
				}
			}
			catch { Write-Error "Login migration reported the following error $($_.Exception.Message) " }
		}
		
		if (!$NoLogins -and !$NoDatabases -and !$NoRecovery)
		{
			Write-Output "`n`nUpdating database owners to match newly migrated logins"
			try
			{
				Update-SqlDbOwner -Source $sourceserver -Destination $destserver
			}
			catch { Write-Error "Login migration reported the following error $($_.Exception.Message) " }
		}
		
		if (!$NoDataCollector)
		{
			if ($sourceserver.versionMajor -lt 10 -or $destserver.versionMajor -lt 10)
			{
				Write-Output "Data Collection sets are only supported in SQL Server 2008 and above. Skipping."
			}
			else
			{
				Write-Output "`n`nMigrating Data Collector collection sets"
				try
				{
					Copy-SqlDataCollector -Source $sourceserver -Destination $destserver -Force:$Force
				}
				catch { Write-Error "Job Server migration reported the following error $($_.Exception.Message) " }
			}
		}
		
		
		if (!$NoAudits)
		{
			if ($sourceserver.versionMajor -lt 10 -or $destserver.versionMajor -lt 10)
			{
				Write-Output "Server Audit Specifications are only supported in SQL Server 2008 and above. Skipping."
			}
			else
			{
				Write-Output "`n`nMigrating Audits"
				try
				{
					Copy-SqlAudit -Source $sourceserver -Destination $destserver -Force:$Force
				}
				catch { Write-Error "Backup device migration reported the following error $($_.Exception.Message)" }
			}
		}
		
		if (!$NoServerAuditSpecifications)
		{
			if ($sourceserver.versionMajor -lt 10 -or $destserver.versionMajor -lt 10)
			{
				Write-Output "Server Audit Specifications are only supported in SQL Server 2008 and above. Skipping."
			}
			else
			{
				Write-Output "`n`nMigrating Server Audit Specifications"
				try
				{
					Copy-SqlAuditSpecification -Source $sourceserver -Destination $destserver -Force:$Force
				}
				catch { Write-Error "Server Audit Specification migration reported the following error $($_.Exception.Message)" }
			}
		}
		
		if (!$NoEndpoints)
		{
			if ($sourceserver.versionMajor -lt 9 -or $destserver.versionMajor -lt 9)
			{
				Write-Output "Server Endpoints are only supported in SQL Server 2008 and above. Skipping."
			}
			else
			{
				Write-Output "`n`nMigrating Endpoints"
				try
				{
					Copy-SqlEndpoint -Source $sourceserver -Destination $destserver -Force:$Force
				}
				catch { Write-Error "Backup device migration reported the following error $($_.Exception.Message)" }
			}
		}
		
		
		if (!$NoPolicyManagement)
		{
			if ($sourceserver.versionMajor -lt 10 -or $destserver.versionMajor -lt 10)
			{
				Write-Output "Policy Management is only supported in SQL Server 2008 and above. Skipping."
			}
			else
			{
				Write-Output "`n`nMigrating Policy Management "
				try
				{
					Copy-SqlPolicyManagement -Source $sourceserver -Destination $destserver -Force:$Force
				}
				catch { Write-Error "Policy Management migration reported the following error $($_.Exception.Message)" }
			}
		}
		
		if (!$NoResourceGovernor)
		{
			if ($sourceserver.versionMajor -lt 10 -or $destserver.versionMajor -lt 10)
			{
				Write-Output "Resource Governor is only supported in SQL Server 2008 and above. Skipping."
			}
			else
			{
				Write-Output "`n`nMigrating Resource Governor"
				try
				{
					Copy-SqlResourceGovernor -Source $sourceserver -Destination $destserver -Force:$Force
				}
				catch { Write-Error "Resource Governor migration reported the following error $($_.Exception.Message)" }
			}
		}
		
		if (!$NoExtendedEvents)
		{
			if ($sourceserver.versionMajor -lt 11 -or $destserver.versionMajor -lt 11)
			{
				Write-Output "Extended Events are only supported in SQL Server 2012 and above. Skipping."
			}
			else
			{
				Write-Output "`n`nMigrating Extended Events"
				try
				{
					Copy-SqlExtendedEvent -Source $sourceserver -Destination $destserver -Force:$Force
				}
				catch { Write-Error "Extended Event migration reported the following error $($_.Exception.Message)" }
			}
		}
		
		if (!$NoAgentServer)
		{
			Write-Output "`n`nMigrating job server"
			try
			{
				Copy-SqlServerAgent -Source $sourceserver -Destination $destserver -DisableJobsOnDestination:$DisableJobsOnDestination -DisableJobsOnSource:$DisableJobsOnSource -Force:$Force
			}
			catch { Write-Error "Job Server migration reported the following error $($_.Exception.Message) " }
		}
		
	}
	
	END
	{
		$totaltime = ($elapsed.Elapsed.toString().Split(".")[0])
		
		if ($sourceserver.ConnectionContext.IsOpen -eq $true) { $sourceserver.ConnectionContext.Disconnect() }
		if ($destserver.ConnectionContext.IsOpen -eq $true) { $destserver.ConnectionContext.Disconnect() }
		
		If ($Pscmdlet.ShouldProcess("console", "Showing SQL Server migration finished message"))
		{
			Write-Output "`n`nSQL Server migration complete"
			Write-Output "Migration started: $started"
			Write-Output "Migration completed: $(Get-Date)"
			Write-Output "Total Elapsed time: $totaltime"
			Stop-Transcript
		}
	}
}