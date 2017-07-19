Function Get-DbaMaxMemory
{
<# 
.SYNOPSIS 
Gets the 'Max Server Memory' configuration setting and the memory of the server.  Works on SQL Server 2000-2014.

.DESCRIPTION 
This command retrieves the SQL Server 'Max Server Memory' configuration setting as well as the total  physical installed on the server.

.PARAMETER SqlInstance
Allows you to specify a comma separated list of servers to query.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$cred = Get-Credential, then pass $cred variable to this parameter. 

Windows Authentication will be used when SqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.NOTES
Tags: Memory
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK 
https://dbatools.io/Get-DbaMaxMemory

.EXAMPLE   
Get-DbaMaxMemory -SqlInstance sqlcluster,sqlserver2012

Get memory settings for all servers within the SQL Server Central Management Server "sqlcluster".

.EXAMPLE 
Get-DbaMaxMemory -SqlInstance sqlcluster | Where-Object { $_.SqlMaxMB -gt $_.TotalMB }

Find all servers in Server Central Management Server that have 'Max Server Memory' set to higher than the total memory of the server (think 2147483647)

#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlServer", "SqlServers")]
		[DbaInstanceParameter]$SqlInstance,
		[PSCredential]$SqlCredential
	)
	
	PROCESS
	{
		foreach ($servername in $SqlInstance)
        {	
			Write-Verbose "Attempting to connect to $servername"
			try
			{
				$server = Connect-SqlInstance -SqlInstance $servername -SqlCredential $SqlCredential
			}
			catch
			{
				Write-Warning "Can't connect to $servername or access denied. Skipping."
				continue
			}

			$totalmemory = $server.PhysicalMemory
			
			# Some servers under-report by 1MB.
			if (($totalmemory % 1024) -ne 0) { $totalmemory = $totalmemory + 1 }

			[pscustomobject]@{
				Server = $server.name
				TotalMB = $totalmemory
				SqlMaxMB = $server.Configuration.MaxServerMemory.ConfigValue
			}
		}
	}
}
