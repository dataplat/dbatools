# TODO
Stuff that needs to be done

Start-SQLMigration.ps1
--------------
Will not drop login in destination if permissions are set
Make into module
Script Only
Azure Support
AlwaysOn
Migrate via mirroring
Option to update db compatability after migration to newer server
option to DBCC UPDATEUSAGE, rebuild indexes, update index statistics and recompile procedures (maybe)
Enerprise -> Std detection for databases and sp_configure options that require Enterprise
Resource pools
Warn in differing server collations
Determine total number of MB to transfer. Best guess migration time?
Detect schema ownership proper to user drop attempt
SQL Server Reporting Server
Support cross-domain non-trusted migrations
local file moves
Disable jobs after migration (requires granular job object migration)
Replace system dbs & run post name change scripts?
Suggest Compression if not enabled?

Auto detect related: 
Certificates
Logins
SQL Agent Jobs (then find related...)
Endpoints 
SSIS Packages


Copy-SQLServerLogins.ps1
--------------
Will not drop login in destination if permissions are set
Detect schema ownership proper to user drop attempt
Script Only

Auto detect related: 
Certificates
Logins
SQL Agent Jobs (then find related...)
Endpoints 
SSIS Packages
	
Watch-DBLogins.ps1
--------------
Add auditing instead or create new script to use SQL Server Auditing
	
Copy-LinkedServers.ps1
--------------
Automatically setup ODBC entry
Copy files?
	
Restore-HallengrenBackups.ps1
--------------
Finish replacing systems db (run post name change scripts)
Support explicitly specified directory structures

Copy-CentralManagementServer.ps1
--------------

Get-SQLServerKeys.ps1
--------------
	
Copy-SQLServerCredentials.ps1
--------------