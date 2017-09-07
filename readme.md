# dbatools

This module is a SQL Server Pro's best friend.

The dbatools project initially started out as Start-SqlMigration.ps1, but has now grown into a collection of over 250 commands that help automate SQL Server tasks and encourage best practices.

![dbatools logo](https://blog.netnerds.net/wp-content/uploads/2016/05/dbatools.png)

Got ideas for new commands? Please propose them as [issues](https://dbatools.io/issues) and let us know what you'd like to see. Bug reports should also be filed under this repository's [issues](https://github.com/sqlcollaborative/dbatools/issues) section.

There's also nearly 800 of us on the [SQL Server Community Slack](https://sqlcommunity.slack.com) in the #dbatools channel. Need an invite? Check out the [self-invite page](https://dbatools.io/slack/). Drop by if you'd like to chat about dbatools or even [join the team](https://dbatools.io/team)!

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
This module has been documented in its entirety pretty much, using Markdown, at [dbatools.io](https://dbatools.io). Please go visit there, it's pretty. 

To skip right to the documentation, [visit the functions page](https://dbatools.io/functions/) or you can start with the [getting started](https://dbatools.io/getting-started/) page.

We're preparing for our 1.0 release and will offer more documentation once it's complete. Sorry the [getting started](https://dbatools.io/getting-started) is lacking at the moment - we're working on it!