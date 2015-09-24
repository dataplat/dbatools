# dbatools
A collection of modules that help dba productivity

Installer
--------------
Will place in PowerShell Gallery when it's slightly more mature. 

	Invoke-Expression (Invoke-WebRequest  http://git.io/vn1hQ).Content

This will install the following functions

	Copy-SqlCentralManagementServer
	Copy-SqlCredentials
	Copy-SqlDatabaseMail
	Copy-SqlDatabases
	Copy-SqlJobServer
	Copy-SqlLinkedServers
	Copy-SqlLogins
	Export-SqlSpConfigure
	Get-DetachedDBinfo
	Get-SqlMaxMemory
	Get-SqlServerKeys
	Import-SqlSpConfigure
	Reset-SqlSaPassword
	Restore-HallengrenBackups
	Set-SqlMaxMemory
	Start-SqlMigration
	Update-dbatools
	Watch-SqlDbLogins

A couple quick notes
--------------

 - I try to support SQL Server 2000-2016 when possible
 - SQL Auth and Windows Auth are supported when possible
 - SQL Sysadmin access is required unless otherwise specified
 - This module requires SQL Management Objects (SMO). SMO is included when you install SQL Server Management Studio, or you can download it from Microsoft: [SQL Server 2014 32-bit SMO](http://download.microsoft.com/download/1/3/0/13089488-91FC-4E22-AD68-5BE58BD5C014/ENU/x86/SharedManagementObjects.msi) or [SQL Server 2014 64-bit SMO](http://download.microsoft.com/download/1/3/0/13089488-91FC-4E22-AD68-5BE58BD5C014/ENU/x64/SharedManagementObjects.msi)

Copy-SqlDatabases
--------------
Copy-SqlDatabases allows you to migrate using detach/copy/attach or backup/restore. 
By default, databases will be migrated to the destination SQL Server's default data and log directories. You can override this by specifying -ReuseFolderStructure. Filestreams and filegroups are also migrated. Safety is emphasized.

	# Windows Authentication with Detach/Attach
	Copy-SqlDatabases -Source sqlcluster -Destination sql2016 -DetachAttach -Reattachatsource -AllUserDbs

	# SQL Authentication with Backup/Restore. 
	# Note that both SQL Server service accounts must have access to the share.
	Copy-SqlDatabases -Source sqlserver -Destination sqlcluster -SourceSqlCredential $SourceSqlCredential -DestinationSqlCredential $DestinationSqlCredential -AllUserDbs -SetSourceReadOnly
    
Copy-SqlLogins
--------------
Migrates logins from source to destination SQL Servers. Supports SQL Server versions 2000 and above.  Migrates logins with SIDs, passwords, defaultdb, server roles & securables, database permissions & securables, login attributes (enforce password policy, expiration, etc). -Sync option will sync permissions but not add or drop logins. Requires SQL sa access.

	# Windows Authentication
    Copy-SqlLogins -Source sqlserver -Destination sqlcluster
	
	# SQL Authentication
	$scred = Get-Credential 
	$dcred = Get-Credential
	Copy-SqlLogins -Source sqlserver -Destination sqlcluster -SourceSqlCredential $scred -DestinationSqlCredential $dcred
	
	# Mix it up
	$dcred = Get-Credential
	Copy-SqlLogins -Source sqlserver -Destination sqlcluster --DestinationSqlCredential $dcred

	
Copy-SqlCentralManagementServer
--------------
Copies all groups, subgroups, and server instances from one SQL Server to another. 

	# Windows Authentication
    Copy-SqlCentralManagementServer -Source sqlserver -Destination sqlcluster

	# SQL Authentication
	$scred = Get-Credential 
	$dcred = Get-Credential
	Copy-SqlCentralManagementServer -Source sqlserver -Destination sqlcluster -SourceSqlCredential $scred -DestinationSqlCredential $dcred

	
Copy-SqlCredentials
--------------
By using password decryption techniques provided by Antti Rantasaari (NetSPI, 2014), this script migrates SQL Server Credentials from one server to another, while maintaining login names and passwords. 

Requires SQL sa acccess, and, if accessing remote servers, Remote Registry must enabled and accessible by the account running the script.

Credit: https://blog.netspi.com/decrypting-mssql-database-link-server-passwords/
License: BSD 3-Clause http://opensource.org/licenses/BSD-3-Clause

	# Windows Authentication
    Copy-SqlCredentials -Source sqlserver -Destination sqlcluster
	
	# SQL Authentication
	$scred = Get-Credential 
	$dcred = Get-Credential
	Copy-SqlCredentials -Source sqlserver -Destination sqlcluster -SourceSqlCredential $scred -DestinationSqlCredential $dcred
    
	
Copy-SqlLinkedServers
--------------
By using password decryption techniques provided by Antti Rantasaari (NetSPI, 2014), this script migrates SQL Server Linked Servers from one server to another, while maintaining username and password. 

Credit: https://blog.netspi.com/decrypting-mssql-database-link-server-passwords/
License: BSD 3-Clause http://opensource.org/licenses/BSD-3-Clause

    Copy-SqlCredentials -Source sqlserver\instance -Destination sqlcluster
	
Copy-SqlDatabaseMail
--------------
Copy-SqlDatabaseMail imports *all * database mail profiles. Like the Copy-SqlJobServer, it doesn't have many features, but it does support SQL Authentication, and it works ;).

	 Copy-SqlDatabaseMail -Source sqlserver\instance -Destination sqlcluster
	 
Export-SqlSpConfigure
--------------
 Exports advanced sp_configure global configuration options to SQL file..

	 Export-SqlSpConfigure $sourceserver -Path C:\temp\sp_configure.sql
	 
Import-SqlSpConfigure
--------------
Updates sp_configure settings on destination server. Can use either a file or another server as the source.

	 Import-SqlSpConfigure sqlserver sqlcluster $SourceSqlCredential 	 	 	$DestinationSqlCredential
	 Import-SqlSpConfigure -SqlServer sqlserver -Path .\spconfig.sql -SqlCredential $SqlCredential
	 
Start-SqlServerMigration
--------------
This brings the rest of the functions together, which is useful when you're looking to migrate entire instances. It less flexible than using the underlying functions, but it's sort of like an easy button.

 - All user databases. Use -SkipDatabases to skip.
 - All logins. Use -SkipLogins to skip.
 - All database mail objects. Use -SkipDatabaseMail 
 - All credentials. Use -SkipCredentials to skip.
 - All objects within the Job Server (SQL Agent). Use -SkipJobServer to skip.
 - Linked Server. Use -SkipLinkedServers to skip. 
 - All items within Central Management Server. Use -SkipCentralManagementServer to skip.
 - SQL Server configuration objects (everything in sp_configure). Use -SkipSpConfigure to skip.

Examples

    # Migrate databases uses backup/restore. Also migrate logins, database mail, credentials, SQL Agent, Central Management Server, SQL global configuration.
    
    Start-SqlMigration -Verbose -Source sqlcluster -Destination sql2016 -SourceSqlCredential \$cred -ReuseFolderstructure -DestinationSqlCredential $cred -Force -NetworkShare \\fileserver\share\sqlbackups\Migration -BackupRestore
    
    # Migrate only database mail, credentials, SQL Agent, Central Management Server, SQL global configuration. 
    
    Start-SqlMigration -Verbose -Source sqlcluster -Destination sql2016 -SkipDatabases -SkipLogins
    
    # Migrate databases using detach/copy/attach. Reattach at source and set source databases read-only. Also migrate logins, database mail, credentials, SQL Agent, Central Management Server, SQL global configuration. 
    
    Start-SqlMigration -Verbose -Source sqlcluster -Destination sql2016 -DetachAttach -Reattach -SetSourceReadonly
    

Restore-HallengrenBackups
--------------
Many SQL Server database administrators use Ola Hallengren's SQL Server Maintenance Solution which can be found at http://ola.hallengren.com  Hallengren uses a predictable backup structure which made it relatively easy to create a script that can restore an entire SQL Server database instance, down to the master database (next version), to a new server. Note, this only works with his script's default paths.

Very early version.

    Restore-HallengrenBackups -SqlServer sqlcluster -Path \\fileserver\share\sqlbackups\SQLSERVER2014A
    
Watch-SqlDbLogins
--------------
Watch-SqlDbLogins uses SQL Server process enumeration to track logins in a SQL Server table. This is helpful when you need to migrate a SQL Server, and update connection strings, but have inadequate documentation on which servers/applications are logging into your SQL instance. 

Running this script every 5 minutes for a week should give you a sufficient idea about database and login usage.

    Watch-SqlDbLogins -SqlServer sqlserver -SqlCms cmserver1

Get-SqlServerKeys
--------------
Using a string of servers, a text file, or Central Management Server to provide a list of servers, this script obtains the product key for all installed instances on a server or cluster. Requires regular user access to the SQL instances, and, if accessing remote servers, Remote Registry must enabled and acessible by the account running the script.

Uses key decoder by Jakob Bindslet (http://goo.gl/1jiwcB)
	
    # Windows Authentication
    Get-SqlServerKeys
    Get-SqlServerKeys -CentralMgmtServer sqlserver01
    Get-SqlServerKeys sqlservera, sqlserver2014a, sql01
   
    # SQL Auth - uses same auth for all connections. 
    # Windows account is still used to access (remote/local) registry.
    $cred = Get-Credential 
    Get-SqlServerKeys -SqlCms sqlserver -SqlCredential $cred
    
Get-DetachedDBinfo
--------------

    Get-DetachedDbInfo -SqlServer sqlserver -MDF M:\Archive\mydb.mdf
    Get-DetachedDbInfo -SqlServer sqlserver -SqlCredential $SqlCredential -MDF M:\Archive\mydb.mdf

Gets the following

    Database Name      : mydb
    Database Collation : SQL_Latin1_General_CP1_CI_AS
    Data files         : {M:\MSSQL12.MSSQLSERVER\MSSQL\DATA\mydb.mdf,M:\MSSQL12.MSSQLSERVER\MSSQL\DATA\mydb_ndf.ndf}
    Log files          : {L:\MSSQL12.MSSQLSERVER\MSSQL\Data\mydb_log.ldf}
    Database Version   : SQL Server 2014

Get-SqlMaxMemory
--------------
Displays information relating to SQL Server Max Memory configuration settings.  Inspired by Jonathan Kehayias's post about SQL Server Max memory (http://bit.ly/sqlmemcalc), this script displays a SQL Server's: total memory, currently configured SQL max memory, and the calculated recommendation.

Jonathan notes that the formula used provides a *general recommendation* that doesn't account for everything that may be going on in your specific environment. 

    Get-SqlMaxMemory -SqlCms sqlserver -SqlCredential $SqlCredential
    Get-SqlMaxMemory -SqlServers sql2016 -SqlCredential $SqlCredential | Set-SqlMaxMemory -UseRecommended
    Set-SqlMaxMemory sql2016 -UseRecommended