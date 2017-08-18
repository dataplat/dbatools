# dbatools

This module is a SQL Server DBA's best friend.

The dbatools project initially started out as Start-SqlMigration.ps1, but has now grown into a collection of over 150 commands that help automate DBA tasks and encourage best practices.

See the [getting started](https://dbatools.io/getting-started) page on [dbatools.io](https://dbatools.io) for more information.

<center>![dbatools logo](https://blog.netnerds.net/wp-content/uploads/2016/05/dbatools.png)</center>

Got ideas for new commands? Please propose them as [issues](https://dbatools.io/issues) and let us know what you'd like to see. Bug reports should also be filed under this repository's [issues](https://github.com/sqlcollaborative/dbatools/issues) section.

There's also around 500 of us on the [SQL Server Community Slack](https://sqlcommunity.slack.com) in the #dbatools channel. Need an invite? Check out the [self-invite page](https://dbatools.io/slack/). Drop by if you'd like to chat about dbatools or even [join the team](https://dbatools.io/team)!

## Installer
This module is now in the PowerShell Gallery. Run the following from an administrative prompt to install:
```powershell
Install-Module dbatools
```

Or if you don't have a version of PowerShell that supports the Gallery, you can install it manually:
```powershell
Invoke-Expression (Invoke-WebRequest https://dbatools.io/in)
```

## dbatools.io is awesome
This module has been documented in its entirety pretty much, using Markdown, at [dbatools.io](https://dbatools.io). Please go visit there, it's pretty. To skip right to the documentation, [visit the functions page](https://dbatools.io/functions/) or you can start with the [getting started](https://dbatools.io/getting-started/) page.