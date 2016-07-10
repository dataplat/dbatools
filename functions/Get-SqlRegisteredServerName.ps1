Function Get-SqlRegisteredServerName
{
<#
.SYNOPSIS
Gets list of SQL Server names stored in SQL Server Central Management Server

.DESCRIPTION
Returns a simple array of server namess

.PARAMETER SqlServer
The SQL Server instance.You must have sysadmin access and server version must be SQL Server version 2000 or higher.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 
Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

.PARAMETER Group
Auto-populated list of groups in SQL Server Central Management Server. You can specify one or more, comma separated.
		
		
.NOTES 
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Get-SqlRegisteredServerName

.EXAMPLE 
Get-SqlRegisteredServerName -SqlServer sqlserver2014a

Gets a list of server names from the Central Management Server on sqlserver2014a, using Windows Credentials

.EXAMPLE 
Get-SqlRegisteredServerName -SqlServer sqlserver2014a -SqlCredential $credential

Copies all policies and conditions from sqlserver2014a to sqlcluster, using Windows credentials. 

.EXAMPLE 
Get-SqlRegisteredServerName -SqlServer sqlserver2014a -SqlCredential $credential

Copies all policies and conditions from sqlserver2014a to sqlcluster, using Windows credentials. 
		

.EXAMPLE 
Get-SqlRegisteredServerName -SqlServer sqlserver2014a -SqlCredential $credential

Copies all policies and conditions from sqlserver2014a to sqlcluster, using Windows credentials. 
	
#>
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[object]$SqlCredential
	)
	
	DynamicParam { if ($sqlserver) { return Get-ParamSqlCmsGroups -SqlServer $sqlserver -SqlCredential $SqlCredential } }
	
	BEGIN
	{
		$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
		$sqlconnection = $server.ConnectionContext.SqlConnectionObject
		
		try
		{
			$cmstore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($sqlconnection)
		}
		catch
		{
			throw "Cannot access Central Management Server"
		}
		
		$groups = $psboundparameters.Groups
	}
	
	PROCESS
	{
		
		
		$servers = @()
		if ($groups -ne $null)
		{
			foreach ($group in $groups)
			{
				$cms = $cmstore.ServerGroups["DatabaseEngineServerGroup"].ServerGroups[$group]
				$servers += ($cms.GetDescendantRegisteredServers()).servername
			}
		}
		else
		{
			$cms = $cmstore.ServerGroups["DatabaseEngineServerGroup"]
			$servers = ($cms.GetDescendantRegisteredServers()).servername
		}
		
		return $servers
	}
	
	END
	{
		$sourceserver.ConnectionContext.Disconnect()
	}
}