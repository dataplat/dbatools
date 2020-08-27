## Getting Started

<img align="left" src=bin/dbatools.png alt="dbatools logo">  dbatools is PowerShell module that you may think of like a command-line SQL Server Management Studio. The project initially started out as just `Start-SqlMigration.ps1`, but has now grown into a collection of [over 500 commands](https://dbatools.io/commands) that help automate SQL Server tasks and encourage best practices.

Want to contribute to the project? We'd love to have you! Visit our [contributing.md](contributing.md) for a jump start.

Want to say thanks? Click the star at the top of the page 🌟

## Key links for reference:

- [dbatools Slack channel](https://sqlcommunity.slack.com/messages/C1M2WEASG/) for general discussion on the module and asking questions
- [dbatools-dev Slack channel](https://sqlcommunity.slack.com/messages/C3EJ852JD/) for discussion around contributing to the project
- [dbatools documentation](https://docs.dbatools.io)

_Need an invite to the SQL Community Slack workspace? Check out the [self-invite page](https://dbatools.io/slack/). Drop by if you'd like to chat about dbatools or even [join the team](https://dbatools.io/team)!_

## Installer

dbatools now works on PowerShell Core (aka PowerShell 6+). This means that you can run a large majority of our commands on <strong>Linux</strong> and <strong>macOS </strong>🤩👍

Run the following to install dbatools from the PowerShell Gallery (to install on a server or for all users, remove the `-Scope` parameter and run in an elevated session):

```powershell
Install-Module dbatools -Scope CurrentUser
```

If you don't have a version of PowerShell that supports the PowerShell Gallery, you can install it manually:

```powershell
Invoke-Expression (Invoke-WebRequest https://dbatools.io/in)
```

> Note: please only use `Invoke-Expression (Invoke-WebRequest..)` from sources you trust, like us 👍

## Usage scenarios

In addition to the simple things you can do in SSMS (e.g. starting a job, backing up a database), we've also read a whole bunch of docs and came up with commands that do nifty things quickly.

- Lost sysadmin access and need to regain entry to your SQL Server? Use [Reset-DbaAdmin](http://dbatools.io/Reset-DbaAdmin).
- Need to easily test your backups? Use [Test-DbaLastBackup](http://dbatools.io/Test-DbaLastBackup).
- SPN management got you down? Use [our suite of SPN commands](http://dbatools.io/schwifty) to find which SPNs are missing and easily add them.
- Got so many databases you can't keep track? Congrats on your big ol' environment! Use [Find-DbaDatabase](http://dbatools.io/Find-DbaDatabase) to easily find your database.

## Usage examples

As previously mentioned, dbatools now offers [over 500 commands](https://dbatools.io/commands)! [Here are some of the ones we highlight at conferences](https://gist.github.com/potatoqualitee/e8932b64aeb6ef404e252d656b6318a2).

PowerShell v3 and above required. (See below for important information about alternative logins and specifying SQL Server ports).

```powershell
# Set some vars
$new = "localhost\sql2016"
$old = $instance = "localhost"
$allservers = $old, $new

# Alternatively, use Registered Servers
$allservers = Get-DbaCmsRegServer -SqlInstance $instance

# Need to restore a database? It can be as simple as this:
Restore-DbaDatabase -SqlInstance $instance -Path "C:\temp\AdventureWorks2012-Full Database Backup.bak"

# Use Ola Hallengren's backup script? We can restore an *ENTIRE INSTANCE* with just one line
Get-ChildItem -Directory \\workstation\backups\sql2012 | Restore-DbaDatabase -SqlInstance $new

# What about if you need to make a backup? And you are logging in with alternative credentials?
Get-DbaDatabase -SqlInstance $new -SqlCredential sqladmin | Backup-DbaDatabase

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
    SharedPath = 'C:\temp'
    Exclude = 'BackupDevice','SysDbUserObjects','Credentials'
}

Start-DbaMigration @startDbaMigrationSplat -Force | Select-Object * | Out-GridView

# Know how snapshots used to be a PITA? Now they're super easy
New-DbaDbSnapshot -SqlInstance $new -Database db1 -Name db1_snapshot
Get-DbaDbSnapshot -SqlInstance $new
Get-DbaProcess -SqlInstance $new -Database db1 | Stop-DbaProcess
Restore-DbaFromDatabaseSnapshot -SqlInstance $new -Database db1 -Snapshot db1_snapshot
Remove-DbaDbSnapshot -SqlInstance $new -Snapshot db1_snapshot # or -Database db1

# Have you tested your last good DBCC CHECKDB? We've got a command for that
$old | Get-DbaLastGoodCheckDb | Out-GridView

# Here's how you can find your integrity jobs and easily start them. Then, you can watch them run, and finally check your newest DBCC CHECKDB results
$old | Get-DbaAgentJob | Where-Object Name -match integrity | Start-DbaAgentJob
$old | Get-DbaRunningJob
$old | Get-DbaLastGoodCheckDb | Out-GridView

# Our new build website is super useful!
Start-Process https://dbatools.io/builds

# You can use the same JSON the website uses to check the status of your own environment
$allservers | Get-DbaBuildReference

# We evaluated 37,545 SQL Server stored procedures on 9 servers in 8.67 seconds!
$new | Find-DbaStoredProcedure -Pattern dbatools

# Have an employee who is leaving? Find all of their objects.
$allservers | Find-DbaUserObject -Pattern ad\jdoe | Out-GridView

# Find detached databases, by example
Detach-DbaDatabase -SqlInstance $instance -Database AdventureWorks2012
Find-DbaOrphanedFile -SqlInstance $instance | Out-GridView

# Check out how complete our sp_configure command is
Get-DbaSpConfigure -SqlInstance $new | Out-GridView

# Easily update configuration values
Set-DbaSpConfigure -SqlInstance $new -ConfigName XPCmdShellEnabled -Value $true

# DB Cloning too!
Invoke-DbaDbClone -SqlInstance $new -Database db1 -CloneDatabase db1_clone | Out-GridView

# Read and watch XEvents
Get-DbaXESession -SqlInstance $new -Session system_health | Read-DbaXEFile
Get-DbaXESession -SqlInstance $new -Session system_health | Read-DbaXEFile | Select-Object -ExpandProperty Fields | Out-GridView

# Reset-DbaAdmin
Reset-DbaAdmin -SqlInstance $instance -Login sqladmin -Verbose
Get-DbaDatabase -SqlInstance $instance -SqlCredential sqladmin

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
Invoke-DbaDbClone -SqlInstance $new -Database dbwithsprocs -CloneDatabase dbwithsprocs_clone

# Schema change and Pester tests
Get-DbaSchemaChangeHistory -SqlInstance $new -Database tempdb

# Get Db Free Space AND write it to table
Get-DbaDbSpace -SqlInstance $instance | Out-GridView
Get-DbaDbSpace -SqlInstance $instance -IncludeSystemDB | ConvertTo-DbaDataTable | Write-DbaDataTable -SqlInstance $instance -Database tempdb -Table DiskSpaceExample -AutoCreateTable
Invoke-DbaQuery -SqlInstance $instance -Database tempdb -Query 'SELECT * FROM dbo.DiskSpaceExample' | Out-GridView

# History
Get-Command -Module dbatools *history*

# Identity usage
Test-DbaIdentityUsage -SqlInstance $instance | Out-GridView

# Test/Set SQL max memory
$allservers | Get-DbaMaxMemory
$allservers | Test-DbaMaxMemory | Format-Table
$allservers | Test-DbaMaxMemory | Where-Object { $_.SqlMaxMB -gt $_.TotalMB } | Set-DbaMaxMemory -WhatIf
Set-DbaMaxMemory -SqlInstance $instance -MaxMb 1023

# Testing sql server linked server connections
Test-DbaLinkedServerConnection -SqlInstance $instance

# See protocols
Get-DbaServerProtocol -ComputerName $instance | Out-GridView

# Reads trace files - default trace by default
Read-DbaTraceFile -SqlInstance $instance | Out-GridView

# don't have remoting access? Explore the filesystem. Uses master.sys.xp_dirtree
Get-DbaFile -SqlInstance $instance

# Test your SPNs and see what'd happen if you'd set them
$servers | Test-DbaSpn | Out-GridView
$servers | Test-DbaSpn | Out-GridView -PassThru | Set-DbaSpn -WhatIf

# Get Virtual Log File information
Get-DbaDbVirtualLogFile -SqlInstance $new -Database db1
Get-DbaDbVirtualLogFile -SqlInstance $new -Database db1 | Measure-Object
```

## Important Note

#### Alternative SQL Credentials

By default, all SQL-based commands will login to SQL Server using Trusted/Windows Authentication. To use alternative credentials, including SQL Logins or alternative Windows credentials, use the `-SqlCredential`. This parameter accepts the results of `Get-Credential` which generates a [PSCredential](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.security/get-credential?view=powershell-5.1) object.

```powershell
Get-DbaDatabase -SqlInstance sql2017 -SqlCredential sqladmin
```

<a href="https://dbatools.io/wp-content/uploads/2016/05/cred.jpg"><img class="aligncenter size-full wp-image-6897" src="https://dbatools.io/wp-content/uploads/2016/05/cred.jpg" alt="" width="322" height="261" /></a>

A few (or maybe just one - [Restore-DbaDatabase](/Restore-DbaDatabase)), you can also use `-AzureCredential`.

#### Alternative Windows Credentials

For commands that access Windows such as [Get-DbaDiskSpace](/Get-DbaDiskSpace), you will pass the `-Credential` parameter.

```powershell
$cred = Get-Credential ad\winadmin
Get-DbaDiskSpace -ComputerName sql2017 -Credential $cred
```

To store credentials to disk, please read more at [Jaap Brasser's blog](https://www.jaapbrasser.com/quickly-and-securely-storing-your-credentials-powershell/).

#### Servers with custom ports

If you use non-default ports and SQL Browser is disabled, you can access servers using a semicolon (functionality we've added) or a comma (the way Microsoft does it).

```powershell
-SqlInstance sql2017:55559
-SqlInstance 'sql2017,55559'
```

Note that PowerShell sees commas as arrays, so you must surround the host name with quotes.

#### Using Start-Transcript

Due to an [issue](https://github.com/sqlcollaborative/dbatools/issues/2722) in the way PowerShell 5.1 works you need to use `Import-Module dbatools` before you run `Start-Transcript`. If this isn't done then your transcript will stop when the module is imported:

```powershell
Import-Module dbatools
Start-Transcript
Get-DbaDatabase -SqlInstance sql2017
Stop-Transcript
```

## Support

dbatools aims to support as many configurations as possible, including

* PowerShell v3 and above
* Windows, macOS and Linux
* SQL Server 2000 - 2017
* Express - Datacenter Edition
* Clustered and stand-alone instances
* Windows and SQL authentication
* Default and named instances
* Multiple instances on one server
* Auto-populated parameters for command-line completion (think -Database and -Login)

Read more at our website at [dbatools.io](https://dbatools.io)
