# TODO
Stuff that needs to be done

Start-SQLMigration
--------------
- Warn in differing server collations
- Enerprise -> Std detection for databases and sp_configure options that require Enterprise
- Support cross-domain non-trusted migrations
- Will not drop login in destination if permissions are set
- Support for NORECOVERY
- Script Only
- local file moves
- Migrate via mirroring
- Resource pools
- Detect schema ownership proper to user drop attempt
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
- Investigate limiting RAM
- Existing Backups (Last Full Backup from server taken from the backup history)
- Existing Backups (Point-in-time backups using backup files from server backup history)
- Remap logins via CSV - http://www.reddit.com/r/SQLServer/comments/35xqy2/im_doing_a_webinar_today_on_simplifying_sql/crac39e
- Option to update db compatability after migration to newer server
- option to DBCC UPDATEUSAGE, rebuild indexes, update index statistics and recompile procedures (maybe)
- Determine total number of MB to transfer. Best guess migration time?
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
- SQL Server Reporting Server
- Azure Support
- AlwaysOn

Copy-SQLServerLogins
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
	
Watch-DBLogins
--------------
- Investigate benefits of using Auditing. So far, seems it doesn't track application names.
- Add a most recent field too?
	
Copy-LinkedServers
--------------
- Automatically setup ODBC entry
- Copy files?

	
Restore-HallengrenBackup
--------------
- Finish replacing systems db (run post name change scripts)
- Support explicitly specified directory structures
- add escapes to names in dynamic params

Copy-CentralManagementServer
--------------
- Support for -force to drop and recreate

Get-SqlServerKey
--------------
	
Copy-SQLServerCredentials
--------------