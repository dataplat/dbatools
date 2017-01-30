Function Rename-DbaLogin
{
<#
.SYNOPSIS 
Rename-DbaLogin will rename login and database mapping for a specified login. 

.DESCRIPTION
There are times where you might want to rename a login that was copied down, or if the name is not descriptive for what it does. 

It can be a pain to update all of the mappings for a spefic user, this does it for you. 

.PARAMETER SqlInstance
Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER Destination
Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SqlInstance 
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter. 

Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. 	
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER Login 
The current Login on the server

.PARAMETER NewLogin 
The new Login that you wish to use. If it is a windows user login, then the SID must match.  

.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed. 
 

.NOTES 
Original Author: Mitchell Hamann (@SirCaptainMitch)

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Rename-DbaLogin

.EXAMPLE   
Rename-DbaLogin -SqlInstance localhost -Login 'DbaToolsUser' -NewLogin 'captain' 

SQL Login Example 

.EXAMPLE   
Rename-DbaLogin -SqlInstance localhost -Login 'domain\oldname' -NewLogin 'domain\newname' 

Change the windowsuser login name.

.EXAMPLE 
Rename-DbaLogin -SqlInstance localhost -Login 'dbatoolsuser' -NewLogin 'captain' -WhatIf

WhatIf Example 


#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true)]
		[object]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlInstanceCredential,
		[parameter(Mandatory = $true)]
		[String]$Login, 
		[parameter(Mandatory = $true)]
		[String]$NewLogin
	)	
	
	BEGIN
	{	
		$sourceserver = Connect-SqlServer -SqlServer $SqlInstance -SqlCredential $SqlInstanceCredential					
		$Databases = $sourceserver.Databases
		$currentUser = $sourceserver.Logins[$Login]
		
	}
	PROCESS
	{		
		if($Pscmdlet.ShouldProcess($SqlInstance, "Changing Login name and database mappings from $Login to $NewLogin")){ 
			try { 
				$currentUser.rename($NewLogin)
			} catch { 
				Write-Warning "Failed to rename the user $Login, please chack the log."
				Write-Exception $_ 
			}			
			foreach ($db in $currentUser.EnumDatabaseMappings())
			{
				$db = $databases[$db.DBName]

				Write-Output "Starting update for $($db.Name)" 

				try { 
									
					Write-Output "Changing database user: $Login to $NewLogin"
					$db.Users[$Login].Rename($NewLogin)
					
				} catch {

					Write-Warning "Rolling back update to login: $Login"
					$currentUser.rename($Login) 

					Write-Warning "The update to User: $Login failed on $($db.Name) Please check the log."				
					Write-Exception $_ 
				}
			}			
		}
				
	}
	
	END
	{		
		If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "Login update completed." }
	}
}