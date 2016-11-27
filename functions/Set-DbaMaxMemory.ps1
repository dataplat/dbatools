Function Set-DbaMaxMemory
{
<# 
.SYNOPSIS 
Sets SQL Server 'Max Server Memory' configuration setting to a new value then displays information this setting. 
Works on SQL Server 2000-2014.

.DESCRIPTION
Sets SQL Server max memory then displays information relating to SQL Server Max Memory configuration settings. 

Inspired by Jonathan Kehayias's post about SQL Server Max memory (http://bit.ly/sqlmemcalc), this uses a formula to 
determine the default optimum RAM to use, then sets the SQL max value to that number.

Jonathan notes that the formula used provides a *general recommendation* that doesn't account for everything that may 
be going on in your specific environment. 

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

.PARAMETER SqlServer
Allows you to specify a comma separated list of servers to query.

.PARAMETER MaxMb
Specifies the max megabytes

.PARAMETER SqlCredential 
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
  
$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.  
 
Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials 
	being passed as credentials. To connect as a different Windows user, run PowerShell as that user. 

.PARAMETER Collection
Results of Get-DbaMaxMemory to be passed into the command

.NOTES 
Author  : Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK 
https://dbatools.io/Set-DbaMaxMemory

.EXAMPLE 
Set-DbaMaxMemory sqlserver1

Set max memory to the recommended MB on just one server named "sqlserver1"

.EXAMPLE 
Set-DbaMaxMemory -SqlServer sqlserver1 -MaxMb 2048

Explicitly max memory to 2048 MB on just one server, "sqlserver1"

.EXAMPLE 
Get-SqlRegisteredServerName -SqlServer sqlserver| Test-DbaMaxMemory | Where-Object { $_.SqlMaxMB -gt $_.TotalMB } | Set-DbaMaxMemory

Find all servers in SQL Server Central Management server that have Max SQL memory set to higher than the total memory 
of the server (think 2147483647), then pipe those to Set-DbaMaxMemory and use the default recommendation.

#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0)]
		[Alias("ServerInstance", "SqlInstance", "SqlServers")]
		[object]$SqlServer,
		[parameter(Position = 1)]
		[int]$MaxMb,
		[Parameter(ValueFromPipeline = $True)]
		[object]$Collection,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	PROCESS
	{
		if ($SqlServer.length -eq 0 -and $collection -eq $null)
		{
			throw "You must specify a server list source using -SqlServer or you can pipe results from Test-DbaMaxMemory"
		}
		
		if ($MaxMB -eq 0)
		{
			$UseRecommended = $true
		}
		
		if ($Collection -eq $null)
		{
			$Collection = Test-DbaMaxMemory -SqlServer $SqlServer
		}
		
		$Collection | Add-Member -NotePropertyName OldMaxValue -NotePropertyValue 0
		
		foreach ($row in $Collection)
		{
			if ($row.server -eq $null)
			{
				$row = Test-DbaMaxMemory -sqlserver $row
				$row | Add-Member -NotePropertyName OldMaxValue -NotePropertyValue 0
			}
			
			Write-Verbose "Attempting to connect to $($row.server)"
			
			try
			{
				$server = Connect-SqlServer -SqlServer $row.server -SqlCredential $SqlCredential
			}
			catch
			{
				Write-Warning "Can't connect to $sqlserver or access denied. Skipping."
				continue
			}
			
			if (!(Test-SqlSa -SqlServer $server))
			{
				Write-Error "Not a sysadmin on $sqlserver. Skipping."
				continue
			}
			
			$row.OldMaxValue = $row.SqlMaxMB
			
			try
			{
				if ($UseRecommended)
				{
					Write-Verbose "Changing $($row.server) SQL Server max from $($row.SqlMaxMB) to $($row.RecommendedMB) MB"
					
					if ($row.RecommendedMB -eq 0 -or $row.RecommendedMB -eq $null)
					{
						$maxmem = (Test-DbaMaxMemory -SqlServer $server).RecommendedMB
						Write-wearning $maxmem
						$server.Configuration.MaxServerMemory.ConfigValue = $maxmem
					}
					else
					{
						
						$server.Configuration.MaxServerMemory.ConfigValue = $row.RecommendedMB
					}
					
					$row.SqlMaxMB = $row.RecommendedMB
				}
				else
				{
					Write-Verbose "Changing $($row.server) SQL Server max from $($row.SqlMaxMB) to $MaxMB MB"
					$server.Configuration.MaxServerMemory.ConfigValue = $MaxMB
					$row.SqlMaxMB = $MaxMB
				}
				$server.Configuration.Alter()
			}
			catch
			{
				Write-Warning "Could not modify Max Server Memory for $($row.server)"
			}
			
			$row | Select-Object Server, TotalMB, OldMaxValue, @{ name = "CurrentMaxValue"; expression = { $_.SqlMaxMB } }
		}
	}
}
