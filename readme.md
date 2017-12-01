# dbatools

Ultimately, you can think of dbatools as a command-line SQL Server Management Studio. The project initially started out as Start-SqlMigration.ps1, but has now grown into a collection of over 3000 commands that help automate SQL Server tasks and encourage best practices.

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

Ultimately, you can think of dbatools as a command-line SQL Server Management Studio. But in addition to the simple things you can do in SSMS (like starting a job), we've also read a whole bunch of docs and came up with commands that do nifty things quickly.

* Lost sysadmin access and need to regain entry to your SQL Server? Use [Reset-DbaAdmin](/Reset-DbaAdmin).
* Need to easily test your backups? Use [Test-DbaLastBackup](/Test-DbaLastBackup).
* SPN management got you down? Use [our suite of SPN commands](/schwifty) to find which SPNs are missing and easily add them.
* Got so many databases you can't keep track? Congrats on your big ol' environment! Use [Find-DbaDatabase](/Find-DbaDatabase) to easily find your database.

## Usage examples

dbatools now offers over 325 commands! [Here are some of the ones we highlight at conferences](https://gist.github.com/potatoqualitee/e8932b64aeb6ef404e252d656b6318a2).

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