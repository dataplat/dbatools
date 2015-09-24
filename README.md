# dbatools
A collection of modules for SQL Server DBAs. It initually started out as 'sqlmigration', but has now grown into a collection of various commands that help automate DBA tasks. The consolidation was done pretty quickly, so there will be bugs, and documentation will be slightly out of date for about a month or so.

Installer
--------------
Run the following command to automatically install the module.

	Invoke-Expression (Invoke-WebRequest  http://git.io/vn1hQ).Content

This will install the following commands

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
	Import-CsvToSql
	Import-SqlSpConfigure
	Reset-SqlSaPassword
	Restore-HallengrenBackups
	Set-SqlMaxMemory
	Start-SqlMigration
	Update-dbatools
	Watch-SqlDbLogins

This module will be placed in PowerShell Gallery when it's slightly more mature. 
	
A few quick notes
--------------

 - I try to support SQL Server 2000-2016 when possible
 - SQL Auth and Windows Auth are supported when possible
 - SQL Sysadmin access is required unless otherwise specified
 - This module requires SQL Management Objects (SMO). SMO is included when you install SQL Server Management Studio, or you can download it from Microsoft: [SQL Server 2014 32-bit SMO](http://download.microsoft.com/download/1/3/0/13089488-91FC-4E22-AD68-5BE58BD5C014/ENU/x86/SharedManagementObjects.msi) or [SQL Server 2014 64-bit SMO](http://download.microsoft.com/download/1/3/0/13089488-91FC-4E22-AD68-5BE58BD5C014/ENU/x64/SharedManagementObjects.msi)

Copy-SqlDatabases
--------------
Copy-SqlDatabases allows you to migrate using detach/copy/attach or backup/restore. 
By default, databases will be migrated to the destination SQL Server's default data and log directories. You can override this by specifying -ReuseFolderStructure. Filestreams and filegroups are also migrated. Safety is emphasized.

This function used to be a core part of Start-SqlServerMigration. While the documentation is slightly outdated, you can visit [ScriptCenter](https://gallery.technet.microsoft.com/scriptcenter/Use-PowerShell-to-Migrate-86c841df) for details and a video of the script in action.

	# Windows Authentication with Detach/Attach
	Copy-SqlDatabases -Source sqlcluster -Destination sql2016 -DetachAttach -Reattachatsource -All

	# SQL Authentication with Backup/Restore. 
	# Note that both SQL Server service accounts must have access to the share.
	Copy-SqlDatabases -Source sqlserver -Destination sqlcluster -SourceSqlCredential $SourceSqlCredential -DestinationSqlCredential $DestinationSqlCredential -All -SetSourceReadOnly -BackupRestore -NetworkShare \\fileshare\sql\migration
    
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

Migrate databases uses backup/restore. Also migrate logins, database mail, credentials, SQL Agent, Central Management Server, SQL global configuration.
    
    Start-SqlMigration -Verbose -Source sqlcluster -Destination sql2016 -SourceSqlCredential \$cred -ReuseFolderstructure -DestinationSqlCredential $cred -Force -NetworkShare \\fileserver\share\sqlbackups\Migration -BackupRestore

Migrate only database mail, credentials, SQL Agent, Central Management Server, SQL global configuration. 
    
    Start-SqlMigration -Verbose -Source sqlcluster -Destination sql2016 -SkipDatabases -SkipLogins
    
Migrate databases uses backup/restore. Also migrate logins, database mail, credentials, SQL Agent, Central Management Server, SQL global configuration.Migrate databases using detach/copy/attach. Reattach at source and set source databases read-only. Also migrate logins, database mail, credentials, SQL Agent, Central Management Server, SQL global configuration. 
    
    Start-SqlMigration -Verbose -Source sqlcluster -Destination sql2016 -DetachAttach -Reattach -SetSourceReadonly

Restore-HallengrenBackups
--------------
Many SQL Server database administrators use Ola Hallengren's SQL Server Maintenance Solution which can be found at http://ola.hallengren.com  Hallengren uses a predictable backup structure which made it relatively easy to create a script that can restore an entire SQL Server database instance, down to the master database (next version), to a new server. Note, this only works with his script's default paths.

Very early version.

    Restore-HallengrenBackups -SqlServer sqlcluster -Path \\fileserver\share\sqlbackups\SQLSERVER2014A
    
Reset-SqlSaPassword
--------------
 This function allows administrators to regain access to local or remote SQL Servers by either resetting the sa password, adding sysadmin role to existing login, or adding a new login (SQL or Windows) and granting it sysadmin privileges.

![Reset-SqlSaPassword](https://i1.gallery.technet.s-msft.com/scriptcenter/reset-sql-sa-password-15fb488d/image/file/138615/1/salsapassword-scriptcenter-1.gif)

This is accomplished by stopping the SQL services or SQL Clustered Resource Group, then restarting SQL via the command-line using the /mReset-SqlSaPassword paramter which starts the server in Single-User mode, and only allows this script to connect.
	  
Once the service is restarted, the following tasks are performed:

 - Login is added if it doesn't exist
 - If login is a Windows User, an attempt is made to ensure it exists
 - If login is a SQL Login, password policy will be set to OFF when creating the login, and SQL Server authentication will be set to Mixed Mode.
 - Login will be enabled and unlocked
 - Login will be added to sysadmin role
	  
If failures occur at any point, a best attempt is made to restart the SQL Server.
	  
In order to make this script as portable as possible, [the original module on Script Center](https://gallery.technet.microsoft.com/scriptcenter/Use-PowerShell-to-Migrate-86c841df) only uses System.Data.SqlClient and Get-WmiObject are used (as opposed to requiring the Failover Cluster Admin tools or SMO).  If using this function against a remote SQL Server, ensure WinRM is configured and accessible. If this is not possible, run the script locally.
	  
Tested on Windows XP, 7, 8.1, Server 2012 and Windows Server Technical Preview 2. Tested on SQL Server 2005 SP4 through 2016 CTP2.

Watch-SqlDbLogins
--------------
Watch-SqlDbLogins uses SQL Server process enumeration to track logins in a SQL Server table. This is helpful when you need to migrate a SQL Server, and update connection strings, but have inadequate documentation on which servers/applications are logging into your SQL instance. See the [Script Center](https://gallery.technet.microsoft.com/scriptcenter/SQL-Server-DatabaseApp-4abbd73a) page for more information.

Running this script every 5 minutes for a week should give you a sufficient idea about database and login usage.

    Watch-SqlDbLogins -SqlServer sqlserver -SqlCms cmserver1
  
  The data in the SQL table looks like this:
  
![enter image description here](https://gallery.technet.microsoft.com/scriptcenter/site/view/file/124201/1/Watch-DBLogins.png)

Use the following code to setup the required SQL table

    CREATE DATABASE DatabaseLogins
    GO
    USE DatabaseLogins
    GO
        CREATE TABLE [dbo].[DbLogins]( 
        [SQLServer] varchar(128),
        [LoginName] varchar(128),
        [Host] varchar(128),
        [DbName] varchar(128),
        [Program] varchar(256),
        [Timestamp] datetime default getdate(),
    )
    -- Create Unique Clustered Index with IGNORE_DUPE_KEY=ON to avoid duplicates
    CREATE UNIQUE CLUSTERED INDEX [ClusteredIndex-Combo] ON [dbo].[DbLogins]
        (
        [SQLServer] ASC,
        [LoginName] ASC,
        [Host] ASC,
        [DbName] ASC,
        [Program] ASC
    ) WITH (IGNORE_DUP_KEY = ON)
    GO

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
    
Output looks like this

![enter image description here](https://i1.gallery.technet.s-msft.com/scriptcenter/get-sql-server-product-4b5bf4f8/image/file/135405/1/sql6.png)

Get-DetachedDBinfo
--------------
Get-DetachedDBinfo gathers the following information from detached database files: database name, SQL Server version (compatibility level), collation, and file structure. "Data files" and "Log file" report the structure of the data and log files as they were when the database was detached. "Database version" is the compatibility level.

    Get-DetachedDbInfo -SqlServer sqlserver -MDF M:\Archive\mydb.mdf
    Get-DetachedDbInfo -SqlServer sqlserver -SqlCredential $SqlCredential -MDF M:\Archive\mydb.mdf

Gets the following

    Database Name      : mydb
    Database Collation : SQL_Latin1_General_CP1_CI_AS
    Data files         : {M:\MSSQL12.MSSQLSERVER\MSSQL\DATA\mydb.mdf,M:\MSSQL12.MSSQLSERVER\MSSQL\DATA\mydb_ndf.ndf}
    Log files          : {L:\MSSQL12.MSSQLSERVER\MSSQL\Data\mydb_log.ldf}
    Database Version   : SQL Server 2014

Get-SqlMaxMemory and Set-SqlMaxMemory
--------------
Displays information relating to SQL Server Max Memory configuration settings.  Inspired by Jonathan Kehayias's post about SQL Server Max memory (http://bit.ly/sqlmemcalc), this script displays a SQL Server's: total memory, currently configured SQL max memory, and the calculated recommendation.

![Get-SqlMaxMemory](https://i1.gallery.technet.s-msft.com/scriptcenter/get-set-sql-max-memory-19147057/image/file/138076/1/sqlmaxmemory.png)

Jonathan notes that the formula used provides a *general recommendation* that doesn't account for everything that may be going on in your specific environment. 

    Get-SqlMaxMemory -SqlCms sqlserver -SqlCredential $SqlCredential
    Get-SqlMaxMemory -SqlServers sql2016 -SqlCredential $SqlCredential | Set-SqlMaxMemory -UseRecommended
    Set-SqlMaxMemory sql2016 -UseRecommended
    Set-SqlMaxMemory sqlcluster 10240

	
Import-CsvtoSql
--------------

Impport-CsvToSql is also a stand-alone module, but I decided it really fit well within this toolset, because it's sort of a command-line DTS Wizard from back in the days when it was easy and just worked. Until I get more time to document this here, you can [see this blog post](https://blog.netnerds.net/2015/09/import-csvtosql-super-fast-csv-to-sql-server-import-powershell-module/)  fore more details about this tool which can import more than 10.5 million records in 2 minutes.

![awesome](https://i1.gallery.technet.s-msft.com/scriptcenter/import-large-csvs-into-sql-fa339046/image/file/142180/1/importcsvsql-win10win-small.gif)

You may also like...
--------------
It's not super polished, but you may also like Invoke-CsvSqlcmd, which allows you to query CSV files using SQL syntax. Visit [Script Center](https://gallery.technet.microsoft.com/scriptcenter/Query-CSV-with-SQL-c6c3c7e5) or **Install-Module CsvSqlcmd** from PSGallery.