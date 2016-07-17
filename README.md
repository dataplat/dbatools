# dbatools
A collection of modules for SQL Server DBAs. It initially started out as 'sqlmigration', but has now grown into a collection of various commands that help automate DBA tasks and encourage best practices.

In my domain joined Windows 10, PowerShell v5, SMO v13 lab, these commands work swimmingly on SQL Server 2000-2016. If you're still using SMO v10 (SQL Server 2008 R2) on your workstation, some functionality may be reduced, but give it a try anyway. 

<p align="center"><img src=https://blog.netnerds.net/wp-content/uploads/2016/05/dbatools.png></p>

Got any suggestions or bug reports? I check github, but I prefer <a href=https://trello.com/b/LcvGHeTF/dbatools>Trello</a>. Let me know what you'd like to see.

There's also around a hundred of us on the <a href="https://sqlcommunity.slack.com">SQL Server Community Slack</a> in the #dbatools channel. Need an invite? Check out the <a href="https://dbatools.io/slack/">self-invite page</a>.

Installer
--------------
This module is now in the PowerShell Gallery! Run the following to install:

    Install-Module dbatools
    
Or if you don't have a version of PowerShell that supports the Gallery, you can install it manually.

    Invoke-Expression (Invoke-WebRequest https://git.io/vn1hQ)

dbatools.io is awesome
--------------
I documented the module in its entirety pretty much, using markdown, at [dbatools.io](https://dbatools.io). Please go visit there, it's pretty. To skip right to the documentation, [visit the functions page](https://dbatools.io/functions/) or you can start with the [getting started](https://dbatools.io/getting-started/) page.