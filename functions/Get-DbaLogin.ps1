Function Get-DbaLogin
{
<#
.SYNOPSIS 
Function to get an SMO login object of the logins for a given SQL Instance. Takes a server object from the pipe 

.DESCRIPTION
The Get-DbaLogin function returns an SMO Login object for the logins passed, if there are no users passed it will return all logins.  

.PARAMETER SqlInstance
The SQL Server instance, or instances.You must have sysadmin access and server version must be SQL Server version 2000 or higher.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. 

.PARAMETER Login
Pass a single login, or a list of them. Comma delimited. 

.PARAMETER Locked 
Filters on the SMO property to return locked Logins. 

.PARAMETER Disabled 
Filters on the SMO property to return disabled Logins. 

.PARAMETER HasAccess 
Filters on the SMO property to return Logins that has access to the instance of SQL Server. 

.PARAMETER Detailed 
Adds extra information by executing a TSQL Script against the server to get more information about the specified User. 
Right now, this only adds LastLogin information

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
Get-DbaLogin -SqlInstance SQl2016 -SqlCredential $sqlcred -Login dbatoolsuser,TheCaptain 
Get specific user objects from the server

.EXAMPLE 
'sql2016', 'sql2014' | Get-DbaLogin -SqlCredential $sqlcred 
Using Get-DbaLogin on the pipeline, you can also specify which names you would like with -Logins.

.EXAMPLE 
'sql2016', 'sql2014' | Get-DbaLogin -SqlCredential $sqlcred -detailed 
Using Get-DbaLogin on the pipeline to get detailed information, like Last Login

.EXAMPLE 
'sql2016', 'sql2014' | Get-DbaLogin -SqlCredential $sqlcred -Locked
Using Get-DbaLogin on the pipeline to get all locked Logins 

.EXAMPLE 
'sql2016', 'sql2014' | Get-DbaLogin -SqlCredential $sqlcred -HasAccess
Using Get-DbaLogin on the pipeline to get all logins that have access to that instance 

.EXAMPLE 
'sql2016', 'sql2014' | Get-DbaLogin -SqlCredential $sqlcred -Disabled
Using Get-DbaLogin on the pipeline to get all Disabled Logins 
	
#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[object[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[Object[]]$Login,
		[Switch]$Detailed,
		[Switch]$HasAccess,
		[Switch]$Locked,
		[Switch]$Disabled 
	)

	begin
	{        
        $sql = "SELECT MAX(login_time) AS [login_time] FROM sys.dm_exec_sessions WHERE login_name = '{0}'"
	}
	
	process
	{
		foreach ($Instance in $sqlInstance)
		{ 
			try { 
				$server = Connect-SqlServer -SqlServer $SqlInstance -SqlCredential $SqlCredential
				$masterDatabase = $server.databases["master"]
				
				
				if ($Login -ne $null )
				{ 
					$serverLogins = $server.Logins | where-object { $Login -contains $_.name }
				} elseif ( $HasAccess ) { 
					$serverLogins = $server.Logins | where-object { $_.HasAccess -eq $true}
				} elseif ( $Locked ) { 
					$serverLogins = $server.Logins | where-object { $_.IsLocked -eq $true}
				} elseIf ( $Disabled ) { 
					$serverLogins = $server.Logins | where-object { $_.IsDisabled -eq $true}
				} else {
					$serverLogins = $server.Logins
				}
			} catch { 
				Write-Warning "Can't connect to $instance or access denied. Skipping."
				continue
			}			
			
			foreach ( $serverLogin in $serverlogins ) 
			{   					
				if ($Detailed) 
				{ 							
					$lastLogin = $($masterDatabase.ExecuteWithResults($sql.replace('{0}',$serverLogin.name)).Tables).login_time
					add-member -InputObject $serverLogin -NotePropertyName LastLogin -NotePropertyValue $lastLogin
				}

				add-member -InputObject $serverLogin -NotePropertyName NetName -NotePropertyValue $server.NetName 
				add-member -InputObject $serverLogin -NotePropertyName ComputerName -NotePropertyValue $server.servicename
				add-member -InputObject $serverLogin -NotePropertyName InstanceName -NotePropertyValue $server.InstanceName 
				add-member -InputObject $serverLogin -NotePropertyName SqlInstance -NotePropertyValue $server.Name				

				if ($Detailed)
				{ 
					Select-DefaultView -InputObject $serverLogin -Property Name, LoginType, LastLogin, NetName, ComputerName, InstanceName, SqlInstance
				} elseif ( $HasAccess ) { 
					Select-DefaultView -InputObject $serverLogin -Property Name, LoginType, HasAccess, NetName, ComputerName, InstanceName, SqlInstance
				} elseif ( $Locked ) { 
					Select-DefaultView -InputObject $serverLogin -Property Name, LoginType, IsLocked, NetName, ComputerName, InstanceName, SqlInstance
				} elseIf ( $Disabled ) { 
					Select-DefaultView -InputObject $serverLogin -Property Name, LoginType, IsDisabled, NetName, ComputerName, InstanceName, SqlInstance
				} else {
					Select-DefaultView -InputObject $serverLogin -Property Name, LoginType, NetName, ComputerName, InstanceName, SqlInstance
				}
			}
		}
	}
	
}
