# TODO
Stuff that needs to be done

Start-SQLMigration.ps1
--------------
- Will not drop login in destination if permissions are set
- Migrate database mail
- Make into module
- Script Only
- Azure Support
- AlwaysOn
- Migrate via mirroring
- Option to update db compatability after migration to newer server
- option to DBCC UPDATEUSAGE, rebuild indexes, update index statistics and recompile procedures (maybe)
- Enerprise -> Std detection for databases and sp_configure options that require Enterprise
- Resource pools
- Warn in differing server collations
- Determine total number of MB to transfer. Best guess migration time?
- Detect schema ownership proper to user drop attempt
- SQL Server Reporting Server
- Support cross-domain non-trusted migrations
- local file moves
- Disable jobs after migration (requires granular job object migration)
- Replace system dbs & run post name change scripts?
- Suggest Compression if not enabled?
- allow user to specify destination data and log files
- add escapes to names in dynamic params

- Auto detect related certificates
- Auto detect related SSIS Packages
- Auto detect related Endpoints 
- Auto detect related Logins
- Auto detect related SQL Agent Jobs (then find related...)


Copy-SQLServerLogins.ps1
--------------
- Will not drop login in destination if permissions are set
- Detect schema ownership proper to user drop attempt
- Script Only
- add escapes to names in dynamic params

- Auto detect related certificates
- Auto detect related SSIS Packages
- Auto detect related Endpoints 
- Auto detect related Logins
- Auto detect related SQL Agent Jobs (then find related...)
	
Watch-DBLogins.ps1
--------------
- Investigate benefits of using Auditing. So far, seems it doesn't track application names.
- Add a most recent field too?
	
Copy-LinkedServers.ps1
--------------
- Automatically setup ODBC entry
- Copy files?

	
Restore-HallengrenBackups.ps1
--------------
- Finish replacing systems db (run post name change scripts)
- Support explicitly specified directory structures
- add escapes to names in dynamic params

Copy-CentralManagementServer.ps1
--------------
- Support for -force to drop and recreate

Get-SQLServerKeys.ps1
--------------
	
Copy-SQLServerCredentials.ps1
--------------