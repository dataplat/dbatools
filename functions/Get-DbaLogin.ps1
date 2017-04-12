Function Get-DbaLogin
{
<#
.SYNOPSIS 
Function to get an SMO login object of the logins for a given SQL Instance. Takes a server object from the pipe 

.DESCRIPTION
The Get-DbaLogin function returns an SMO Login object for the users passed, if there are no users passed it will return all logins.  

.PARAMETER SqlInstance
The SQL Server instance.You must have sysadmin access and server version must be SQL Server version 2000 or higher.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. 

.PARAMETER Logins 
Pass a single login, or a list of them. Comma delimited. 

.PARAMETER NoSystemLogins
A switch to exlude system logins from returning.

.PARAMETER Detail 
Adds several extra columns by executing a TSQL Script against the server to get more information about the specified User. 
This includes, LastLogin, netname, servicename as computername, instancename and sqlinstance.

.NOTES 
Original Author: Mitchell Hamann (@SirCaptainMitch)

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.	

.LINK
https://dbatools.io/Get-DbaLogin

.EXAMPLE
Get-DbaLogin -SqlInstance SQl2016 
Gets all the logins for a given SQL Server using NT authentication and returns the SMO login objects 

.EXAMPLE   
Get-DbaLogin -SqlInstance SQl2016 -SqlCredential $sqlcred 
Gets all the logins for a given SQL Server using a passed credential object and returns the SMO login objects 

.EXAMPLE 
Get-DbaLogin -SqlInstance SQl2016 -SqlCredential $sqlcred -Logins dbatoolsuser,TheCaptain 
Get specific user objects from the server

.EXAMPLE 
@('sql2016', 'sql2014') |  Get-DbaLogin -SqlCredential $sqlcred 
Using Get-DbaLogin on the pipeline, you can also specify which names you would like with -Logins.  
	
#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[object[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[Object[]]$Logins,
		[Switch]$NoSystemLogins,
		[Switch]$Detailed
	)

	begin
	{        
        $sql = "SELECT MAX(login_time) AS [login_time] FROM sys.dm_exec_sessions WHERE login_name = '{0}'"			
	}
	
	process
	{
		foreach ($Instance in $sqlInstance)
		{ 
			try{ 
				$server = Connect-SqlServer -SqlServer $SqlInstance -SqlCredential $SqlCredential
				$serverLogins = $server.Logins
				$masterDatabase = $server.databases["master"]
			} catch { 
				Write-Warning "Can't connect to $instance or access denied. Skipping."
				continue
			}

			if ( $Logins -ne $null ) 
			{ 
				foreach ( $login in $serverlogins ) 
				{   					
					if ( $Logins -contains $login.name ) 
					{
						if ($Detailed) 
						{ 							
							$lastLogin = $($masterDatabase.ExecuteWithResults($sql.replace('{0}',$login.name)).Tables).login_time
							add-member -InputObject $login -NotePropertyName LastLogin -NotePropertyValue $lastLogin
						} 

						add-member -InputObject $login -NotePropertyName NetName -NotePropertyValue $server.NetName 
						add-member -InputObject $login -NotePropertyName ComputerName -NotePropertyValue $server.servicename
						add-member -InputObject $login -NotePropertyName InstanceName -NotePropertyValue $server.InstanceName 
						add-member -InputObject $login -NotePropertyName SqlInstance -NotePropertyValue $server.Name

						Select-DefaultView -InputObject $login -Property Name, LoginType, LastLogin, NetName, ComputerName, InstanceName, SqlInstance 						 
					}
				}
			} else { 
				foreach ($login in $serverLogins)
				{
					if (!$login.name.StartsWith("##") -and $login.name -ne 'sa')
					{
						if ($Detailed) 
						{ 							
							$lastLogin = $($masterDatabase.ExecuteWithResults($sql.replace('{0}',$login.name)).Tables).login_time
							add-member -InputObject $login -NotePropertyName LastLogin -NotePropertyValue $lastLogin
						}

						add-member -InputObject $login -NotePropertyName NetName -NotePropertyValue $server.NetName 
						add-member -InputObject $login -NotePropertyName ComputerName -NotePropertyValue $server.servicename
						add-member -InputObject $login -NotePropertyName InstanceName -NotePropertyValue $server.InstanceName 
						add-member -InputObject $login -NotePropertyName SqlInstance -NotePropertyValue $server.Name

						Select-DefaultView -InputObject $login -Property Name, LoginType, LastLogin, NetName, ComputerName, InstanceName, SqlInstance 
					}
				}
			}
		}

        
	}
	
}
