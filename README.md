# dbatools
A collection of modules for SQL Server DBAs. It initially started out as 'sqlmigration', but has now grown into a collection of various commands that help automate DBA tasks.

In my domain joined Windows 10, PowerShell v5, SMO v12 lab, these commands work swimmingly on SQL Server 2000-2016. If you're still using SMO v10 (SQL Server 2008 R2) on your workstation, some functionality may be reduced, but give it a try anyway. 

<p align="center"><img src=https://blog.netnerds.net/wp-content/uploads/2016/05/dbatools.png></p>

Got any suggestions or bug reports? I check github, but I prefer <a href=https://trello.com/b/LcvGHeTF/dbatools>Trello</a>. Let me know what you'd like to see.

Installer
--------------
This module is now in the PowerShell Gallery! Run the following to install:

    Install-Module dbatools
    
Or if you don't have a version of PowerShell that supports the Gallery, you can install it manually.

    Invoke-Expression (Invoke-WebRequest https://git.io/vn1hQ)

This will install the following commands

    Copy-SqlAgentCategory          
    Copy-SqlAlert                  
    Copy-SqlAudit                  
    Copy-SqlAuditSpecification     
    Copy-SqlBackupDevice           
    Copy-SqlCentralManagementServer
    Copy-SqlCredential             
    Copy-SqlCustomError            
    Copy-SqlDatabase               
    Copy-SqlDatabaseAssembly       
    Copy-SqlDatabaseMail           
    Copy-SqlDataCollector          
    Copy-SqlEndpoint               
    Copy-SqlExtendedEvent          
    Copy-SqlJob                    
    Copy-SqlLinkedServer           
    Copy-SqlLogin                  
    Copy-SqlOperator               
    Copy-SqlPolicyManagement       
    Copy-SqlProxyAccount           
    Copy-SqlResourceGovernor       
    Copy-SqlServerAgent            
    Copy-SqlServerRole             
    Copy-SqlServerTrigger          
    Copy-SqlSharedSchedule         
    Copy-SqlSpConfigure            
    Copy-SqlSysDbUserObjects
	Start-SqlMigration 
	
    Expand-SqlTLogResponsibly      
    Export-SqlLogin                
    Export-SqlSpConfigure          
    Find-SqlDuplicateIndex         
    Get-DetachedDbInfo             
    Get-SqlMaxMemory               
    Get-SqlRegisteredServerName    
    Get-SqlServerKey               
    Import-CsvToSql                
    Import-SqlSpConfigure          
    Move-SqlDatabaseFile           
    Reset-SqlAdmin                 
    Restore-HallengrenBackup       
    Set-SqlMaxMemory               
    Show-SqlMigrationConstraint
    Sync-SqlLoginPermissions       
    Test-SqlConnection             
    Test-SqlNetworkLatency         
    Test-SqlPath
    Watch-SqlDbLogin 
    Update-dbatools  

A few important notes
--------------
 - I try to support SQL Server 2000-2016 and clustered instances when possible
 - SQL Auth and Windows Auth are supported when possible
 - Windows authentication/Windows admin access is required at the *Windows Server level* for Copy-SqlCredential, Copy-SqlLinkedServer, and Reset-SqlAdmin.
 - SQL Sysadmin access is required unless otherwise specified
 - This module requires SQL Management Objects (SMO). SMO is included when you install SQL Server Management Studio, or you can download it from Microsoft: [SQL Server 2014 32-bit SMO](http://download.microsoft.com/download/1/3/0/13089488-91FC-4E22-AD68-5BE58BD5C014/ENU/x86/SharedManagementObjects.msi) or [SQL Server 2014 64-bit SMO](http://download.microsoft.com/download/1/3/0/13089488-91FC-4E22-AD68-5BE58BD5C014/ENU/x64/SharedManagementObjects.msi). The higher the version the better.


dbatools.io is awesome
--------------
I documented the module in its entirety pretty much, using markdown, at [dbatools.io](https://dbatools.io). Please go visit there, it's pretty. To skip right to the documentation, [visit the functions page](https://dbatools.io/functions/)