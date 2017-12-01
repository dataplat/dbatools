# dbatools

dbatools is sort of like a command-line SQL Server Management Studio. The project initially started out as Start-SqlMigration.ps1, but has now grown into a collection of [over 300 commands](https://dbatools.io/commands) that help automate SQL Server tasks and encourage best practices.

![dbatools logo](https://blog.netnerds.net/wp-content/uploads/2016/05/dbatools.png)

Got ideas for new commands? Please propose them as [issues](https://dbatools.io/issues) and let us know what you'd like to see. Bug reports should also be filed under this repository's [issues](https://github.com/sqlcollaborative/dbatools/issues) section.

There's also over 1000 of us on the [SQL Server Community Slack](https://sqlcommunity.slack.com) in the #dbatools channel. Need an invite? Check out the [self-invite page](https://dbatools.io/slack/). Drop by if you'd like to chat about dbatools or even [join the team](https://dbatools.io/team)!

## Installer
This module is now in the PowerShell Gallery. Run the following from an administrative prompt to install:
```powershell
Install-Module dbatools
```

Or if you don't have a version of PowerShell that supports the Gallery, you can install it manually:
```powershell
Invoke-Expression (Invoke-WebRequest https://dbatools.io/in)
```

## Usage scenarios

In addition to the simple things you can do in SSMS (like starting a job), we've also read a whole bunch of docs and came up with commands that do nifty things quickly.

* Lost sysadmin access and need to regain entry to your SQL Server? Use [Reset-DbaAdmin](/Reset-DbaAdmin).
* Need to easily test your backups? Use [Test-DbaLastBackup](/Test-DbaLastBackup).
* SPN management got you down? Use [our suite of SPN commands](/schwifty) to find which SPNs are missing and easily add them.
* Got so many databases you can't keep track? Congrats on your big ol' environment! Use [Find-DbaDatabase](/Find-DbaDatabase) to easily find your database.

## Usage examples

As previously mentioned, dbatools now offers [over 300 commands](https://dbatools.io/commands)! [Here are some of the ones we highlight at conferences](https://gist.github.com/potatoqualitee/e8932b64aeb6ef404e252d656b6318a2).

```powershell
# Set some vars
$new = "localhost\sql2016"
$old = $instance = "localhost"
$allservers = $old, $new

# Alternatively, use Registerd Servers? 
Get-DbaRegisteredServer -SqlInstance $instance | Out-GridView

# Quick overview of commands
Start-Process https://dbatools.io/commands

# Need to restore a database? It can be as simple as this:
Restore-DbaDatabase -SqlInstance $instance -Path "C:\temp\AdventureWorks2012-Full Database Backup.bak"

# But what if the database already exists? You'll be warned to add -WithReplace
Restore-DbaDatabase -SqlInstance $instance -Path "C:\temp\AdventureWorks2012-Full Database Backup.bak" -WithReplace

# Use Ola Hallengren's backup script? We can restore an *ENTIRE INSTNACE* with just one line
Get-ChildItem -Directory \\workstation\backups\sql2012 | Restore-DbaDatabase -SqlInstance $new

# What about if you need to make a backup? And you are logging in with alternative credentials?
Get-DbaDatabase -SqlInstance $new -SqlCredential (Get-Credential sa) | Backup-DbaDatabase

# Testing your backups is crazy easy! 
Start-Process https://dbatools.io/Test-DbaLastBackup
Test-DbaLastBackup -SqlInstance $old | Out-GridView

# But what if you want to test your backups on a different server?
Test-DbaLastBackup -SqlInstance $old -Destination $new | Out-GridView

# Nowadays, we don't just backup databases. Now, we're backing up logins
Export-DbaLogin -SqlInstance $instance -Path C:\temp\logins.sql
Invoke-Item C:\temp\logins.sql

# And Agent Jobs
Get-DbaAgentJob -SqlInstance $old | Export-DbaScript -Path C:\temp\jobs.sql

# What if you just want to script out your restore?
Get-ChildItem -Directory \\workstation\backups\subset\ | Restore-DbaDatabase -SqlInstance $new -OutputScriptOnly -WithReplace | Out-File -Filepath c:\temp\restore.sql
Invoke-Item c:\temp\restore.sql

# You've probably heard about how easy migrations can be with dbatools. Here's an example 
$startDbaMigrationSplat = @{
    Source = $old
    Destination = $new
    BackupRestore = $true
    NetworkShare = 'C:\temp'
    NoSysDbUserObjects = $true
    NoCredentials = $true
    NoBackupDevices = $true
    NoEndPoints = $true
}
		
Start-DbaMigration @startDbaMigrationSplat -Force | Select * | Out-GridView

# Know how snapshots used to be a PITA? Now they're super easy
New-DbaDatabaseSnapshot -SqlInstance $new -Database db1 -Name db1_snapshot
Get-DbaDatabaseSnapshot -SqlInstance $new
Get-DbaProcess -SqlInstance $new -Database db1 | Stop-DbaProcess
Restore-DbaFromDatabaseSnapshot -SqlInstance $new -Database db1 -Snapshot db1_snapshot
Remove-DbaDatabaseSnapshot -SqlInstance $new -Snapshot db1_snapshot # or -Database db1

# Have you tested your last good DBCC CHECKDB? We've got a command for that
$old | Get-DbaLastGoodCheckDb | Out-GridView

# Here's how you can find your integrity jobs and easily start them. Then, you can watch them run, and finally check your newest DBCC CHECKDB results
$old | Get-DbaAgentJob | Where Name -match integrity | Start-DbaAgentJob
$old | Get-DbaRunningJob
$old | Get-DbaLastGoodCheckDb | Out-GridView

# Our new build website is super useful!
Start-Process https://dbatools.io/builds

# You can use the same JSON the website uses to check the status of your own environment
$allservers | Get-DbaSqlBuildReference

# We evaluated 37,545 SQL Server stored procedures on 9 servers in 8.67 seconds!
$new | Find-DbaStoredProcedure -Pattern dbatools

# Check out the differences when you use Select *
$new | Find-DbaStoredProcedure -Pattern dbatools | Select * | Out-GridView

# Here's how you can search for email patterns
$new | Find-DbaStoredProcedure -Pattern '\w+@\w+\.\w+'

# Have an employee who is leaving? Find all of their objects.
$allservers | Find-DbaUserObject -Pattern ad\jdoe | Out-GridView
 
# Find detached databases, by example
Detach-DbaDatabase -SqlInstance $instance -Database AdventureWorks2012
Find-DbaOrphanedFile -SqlInstance $instance | Out-GridView

# Find it! - JSON file powers command and website search
Find-DbaCommand Backup
Find-DbaCommand -Tag Backup | Out-GridView

# View and change service account
Get-DbaSqlService -ComputerName workstation | Out-GridView
Get-DbaSqlService -ComputerName workstation | Select * | Out-GridView
Get-DbaSqlService -Instance SQL2016 -Type Agent | Update-DbaSqlServiceAccount -Username 'Local system'

# Check out how complete our sp_configure command is
Get-DbaSpConfigure -SqlInstance $new | Out-GridView
Get-DbaSpConfigure -SqlInstance $new -ConfigName XPCmdShellEnabled

# Easily update configuration values
Set-DbaSpConfigure -SqlInstance $new -ConfigName XPCmdShellEnabled -Value $true

# DB Cloning too!
Invoke-DbaDatabaseClone -SqlInstance $new -Database db1 -CloneDatabase db1_clone | Out-GridView

# XEvents - more coming soon, like easy replays on remote servers

# Easy start/stop
Get-DbaXESession -SqlInstance $new
$session = Get-DbaXESession -SqlInstance $new -Session system_health | Stop-DbaXESession
$session | Start-DbaXESession

# Read and watch
Get-DbaXEventSession -SqlInstance $new -Session system_health | Read-DbaXEventFile
Get-DbaXEventSession -SqlInstance $new -Session system_health | Read-DbaXEventFile | Select -ExpandProperty Fields | Out-GridView

# Reset-DbaAdmin
Reset-DbaAdmin -SqlInstance $instance -Login sqladmin -Verbose
Get-DbaDatabase -SqlInstance $instance -SqlCredential (Get-Credential sqladmin)

# Configs and enterprise logging
Get-DbaConfig | Out-GridView
Invoke-Item (Get-DbaConfig -FullName path.dbatoolslogpath).Value

Get-DbaConfig -Module tabexpansion
Set-DbaConfig -Name tabexpansion.disable -Value $true

Get-DbatoolsLog | Out-GridView
New-DbatoolsSupportPackage

# sp_whoisactive
Install-DbaWhoIsActive -SqlInstance $instance -Database master
Invoke-DbaWhoIsActive -SqlInstance $instance -ShowOwnSpid -ShowSystemSpids

# Diagnostic query!
$instance | Invoke-DbaDiagnosticQuery -UseSelectionHelper | Export-DbaDiagnosticQuery -Path $home
Invoke-Item $home

# Ola, yall
$instance | Install-DbaMaintenanceSolution -ReplaceExisting -BackupLocation C:\temp -InstallJobs

# Startup parameters
Get-DbaStartupParameter -SqlInstance $instance
Set-DbaStartupParameter -SqlInstance $instance -SingleUser -WhatIf

# Database clone
Invoke-DbaDatabaseClone -SqlInstance $new -Database dbwithsprocs -CloneDatabase dbwithsprocs_clone

# Schema change and Pester tests
Invoke-Sqlcmd2 -SqlInstance $new -Database tempdb -Query "CREATE TABLE dbatoolsci_schemachange (id int identity)"
Invoke-Sqlcmd2 -SqlInstance $new -Database tempdb -Query "EXEC sp_rename 'dbatoolsci_schemachange', 'dbatoolsci_schemachange_new'"
Get-DbaSchemaChangeHistory -SqlInstance $new -Database tempdb
Invoke-Sqlcmd2 -SqlInstance $new -Database tempdb -Query "DROP TABLE dbatoolsci_schemachange_new"

# Get Db Free Space AND write it to table
Get-DbaDatabaseSpace -SqlInstance $instance | Out-GridView
Get-DbaDatabaseSpace -SqlInstance $instance -IncludeSystemDB | Out-DbaDataTable | Write-DbaDataTable -SqlInstance $instance -Database tempdb -Table DiskSpaceExample -AutoCreateTable
Invoke-Sqlcmd2 -ServerInstance $instance -Database tempdb -Query 'SELECT * FROM dbo.DiskSpaceExample' | Out-GridView

# History
Get-Command -Module dbatools *history*

# More histories
Get-DbaAgentJobHistory -SqlInstance $instance | Out-GridView
Get-DbaBackupHistory -SqlInstance $new | Out-GridView

# Identity usage
Test-DbaIdentityUsage -SqlInstance $instance | Out-GridView

# Test/Set SQL max memory
$allservers | Get-DbaMaxMemory
$allservers | Test-DbaMaxMemory | Format-Table
$allservers | Test-DbaMaxMemory | Where-Object { $_.SqlMaxMB -gt $_.TotalMB } | Set-DbaMaxMemory -WhatIf
Set-DbaMaxMemory -SqlInstance $instance -MaxMb 1023

# Test recovery models for "pseudo simple"
Test-DbaFullRecoveryModel -SqlInstance $new
Test-DbaFullRecoveryModel -SqlInstance $new | Where { $_.ConfiguredRecoveryModel -ne $_.ActualRecoveryModel }

# Testing sql server linked server connections
Test-DbaLinkedServerConnection -SqlInstance $instance

# See protocols
Get-DbaServerProtocol -ComputerName $instance | Out-GridView

# SQL Modules - View, TableValuedFunction, DefaultConstraint, StoredProcedure, Rule, InlineTableValuedFunction, Trigger, ScalarFunction
Get-DbaSqlModule -SqlInstance $instance | Out-GridView
Get-DbaSqlModule -SqlInstance $instance -ModifiedSince (Get-Date).AddDays(-7) | Select-String -Pattern sp_executesql

# Reads trace files - default trace by default
Read-DbaTraceFile -SqlInstance $instance | Out-GridView

# Get the registry root
Get-DbaSqlRegistryRoot -ComputerName $instance

# don't have remoting access? Explore the filesystem. Uses master.sys.xp_dirtree
Get-DbaFile -SqlInstance $instance
Get-DbaFile -SqlInstance $instance -Depth 3 -Path 'C:\Program Files\Microsoft SQL Server' | Out-GridView
New-DbaSqlDirectory -SqlInstance $instance  -Path 'C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQLSERVER\test'

# Test your SPNs and see what'd happen if you'd set them
$servers | Test-DbaSpn | Out-GridView
$servers | Test-DbaSpn | Out-GridView -PassThru | Set-DbaSpn -WhatIf

# Get Virtual Log File information
Get-DbaDbVirtualLogFile -SqlInstance $new -Database db1
Get-DbaDbVirtualLogFile -SqlInstance $new -Database db1 | Measure-Object

# Out-GridView madness <3
Get-DbaDatabase -SqlInstance $old | Out-GridView -PassThru | Copy-DbaDatabase -Destination $new -BackupRestore -NetworkShare \\workstation\c$\temp -Force
```

## Support

dbatools aims to support as many configurations as possible, including

<ul>
 	<li>SQL Server 2000 - 2017</li>
 	<li>Express - Datacenter Edition</li>
 	<li>Clustered and stand-alone instances</li>
 	<li>Windows and SQL authentication</li>
 	<li>Default and named instances</li>
 	<li>Multiple instances on one server</li>
 	<li>Auto-populated parameters for command-line completion (think -Database and -Login)</li>
</ul>

Read more at our website at [dbatools.io](https://dbatools.io)