# sqlmigration
A collection of scripts that help facilitate SQL Server Migrations

Start-SQLMigration.ps1
--------------
This script provides the ability to migrate databases using detach/copy/attach or backup/restore. SQL Server logins, including passwords, SID and database/server roles can also be migrated. In addition, job server objects can be migrated and server configuration settings can be exported or migrated. This script works with named instances, clusters and SQL Express.
	
By default, databases will be migrated to the destination SQL Server's default data and log directories. You can override this by specifying -ReuseFolderStructure. Filestreams and filegroups are also migrated. Safety is emphasized.

Eventually, all scripts within this directory will be integrated into Start-SQLMigration.ps1

    .\Start-SQLMigration.ps1 -Source sqlserver\instance -Destination sqlcluster -DetachAttach -Everything
	
Copy-SQLServerLogins.ps1
--------------
Migrates only logins from source to destination SQL Servers. Supports SQL Server versions 2000 and above.  Migrates logins with SIDs, passwords, defaultdb, server roles & securables, database permissions & securables, login attributes (enforce password policy, expiration, etc)

    .\Copy-SQLServerLogins.ps1 -Source sqlserver -Destination sqlcluster 
	
Copy-CentralManagementServer.ps1
--------------
Copies all groups, subgroups, and server instances from one SQL Server to another. 

    .\Copy-CentralManagementServer.ps1 -Source sqlserver -Destination sqlcluster
	
Watch-DBLogins.ps1
--------------
Watch-DBLogins.ps1 uses SQL Server process enumeration to track logins in a SQL Server table. This is helpful when you need to migrate a SQL Server, and update connection strings, but have inadequate documentation on which servers/applications are logging into your SQL instance. 

Running this script every 5 minutes for a week should give you a sufficient idea about database and login usage.

    .\Watch-DBLogins.ps1 -WatchDBServer sqlserver -CMServer cmserver1

Get-SQLServerKeys.ps1
--------------
Using a string of servers, a text file, or Central Management Server to provide a list of servers, this script obtains the product key for all installed instances on a server or cluster. Requires regular user access to the SQL instances, SMO installed locally, and, if accessing remote servers, Remote Registry must enabled and acessible by the account running the script.

Uses key decoder by Jakob Bindslet (http://goo.gl/1jiwcB)

   .\Get-SQLServerKeys.ps1
   .\Get-SQLServerKeys.ps1 -CentralMgmtServer sqlserver01
   .\Get-SQLServerKeys.ps1 sqlservera, sqlserver2014a, sql01
	
Copy-SQLServerCredentials.ps1
--------------
By using password decryption techniques provided by Antti Rantasaari (NetSPI, 2014), this script migrates SQL Server Credentials from one server to another, while maintaining login names and passwords.

Very early version.

Credit: https://blog.netspi.com/decrypting-mssql-database-link-server-passwords/
License: BSD 3-Clause http://opensource.org/licenses/BSD-3-Clause

    .\Copy-SQLServerCredentials.ps1 -Source sqlserver\instance -Destination sqlcluster
	
Copy-LinkedServers.ps1
--------------
By using password decryption techniques provided by Antti Rantasaari (NetSPI, 2014), this script migrates SQL Server Linked Servers from one server to another, while maintaining username and password. 

Very early version.

Credit: https://blog.netspi.com/decrypting-mssql-database-link-server-passwords/
License: BSD 3-Clause http://opensource.org/licenses/BSD-3-Clause

    .\Copy-SQLServerCredentials.ps1 -Source sqlserver\instance -Destination sqlcluster
	
Restore-HallengrenBackups.ps1
--------------
Many SQL Server database administrators use Ola Hallengren's SQL Server Maintenance Solution which can be found at http://ola.hallengren.com  Hallengren uses a predictable backup structure which made it relatively easy to create a script that can restore an entire SQL Server database instance, down to the master database (next version), to a new server. This script is intended to be used in the event that the originating SQL Server becomes unavailable, thus rendering my other SQL restore script (http://goo.gl/QmfQ6s) ineffective. Note, this only works with his script's default paths.

Very early version.

    .\Restore-HallengrenBackups.ps1 -ServerName sqlcluster -RestoreFromDirectory \\fileserver\share\sqlbackups\SQLSERVER2014A