Function Get-DbaLogin
{
<#
.SYNOPSIS 
Function to get an SMO login object of the logins for a given SQL Instance. Takes a server object from the pipe 

.DESCRIPTION
By default, all SqlLogins are returned save for those starting with ## 

.PARAMETER SqlInstance
The SQL Server instance.You must have sysadmin access and server version must be SQL Server version 2000 or higher.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. 

.PARAMETER Logins 
Dynamic Parameter that will get a list of logins that you can grab from the server, or you can add your own. 

.NOTES 
Original Author: Mitchell Hamann (@SirCaptainMitch)

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Get-DbaLogin

.EXAMPLE
Get-DbaLogin -SqlInstance SQl2016 
Gets all the logins for a given SQL Server using NT authentication and returns the SMO login objects 

.EXAMPLE   
Get-DbaLogin -SqlInstance SQl2016 -SqlCredential $sqlcred 
Gets all the logins for a given SQL Server using a passed credential object and returns the SMO login objects 

.EXAMPLE   
Get-DbaLogin -SqlServer sqlserver2014 -WhatIf
Shows what would happen if the command were executed.

.EXAMPLE 
Get-DbaLogin -SqlInstance SQl2016 -SqlCredential $sqlcred -Logins dbatoolsuser,TheCaptain 
Get specific user objects from the server

.EXAMPLE 
Get-DbaLogin -SqlInstance SQl2016 -SqlCredential $sqlcred -Logins dbatoolsuser,TheCaptain 
Pipeline example 
	
#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[object]$SqlInstance,
		[object]$SqlCredential 	
	)				

    DynamicParam { if ($SqlInstance) {  return Get-ParamSqlLogins -SqlServer $SqlInstance -SqlCredential $SqlCredential } } 

	begin
	{		
		$sourceServer = Connect-SqlServer -SqlServer $SqlInstance -SqlCredential $SqlCredential
		$serverLogins = $sourceServer.Logins
        $parameterLogins = $psboundparameters.Logins
        $masterDatabase = $sourceServer.databases["master"]
        $sql = "SELECT MAX(login_time) AS [login_time] FROM sys.dm_exec_sessions WHERE login_name = '{0}'"
		$results = @()				
	}
	
	process
	{
        if ( $parameterLogins -ne $null ) 
        { 
            foreach ( $login in $serverlogins ) 
            {            
                if ( $parameterLogins -contains $login.name ) 
                { 
					$lastLogin = $($masterDatabase.ExecuteWithResults($sql.replace('{0}',$login.name)).Tables).login_time					
					add-member -InputObject $login -NotePropertyName LastLogin $lastLogin
					$results += $login									
                }
            }
        } else { 
			foreach ($login in $serverLogins)
			{
				if (!$login.name.StartsWith("##") -and $login.name -ne 'sa')
				{
					$lastLogin = $($masterDatabase.ExecuteWithResults($sql.replace('{0}',$login.name)).Tables).login_time					
					add-member -InputObject $login -NotePropertyName LastLogin $lastLogin
					$results += $login
				}
			}
		}
	}
	
	end
	{
        return $results		
	}
}