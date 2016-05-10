Function Get-SqlMaxMemory
{
<# 
.SYNOPSIS 
Displays information relating to SQL Server Max Memory configuration settings.  Works on SQL Server 2000-2014.

.DESCRIPTION 
Inspired by Jonathan Kehayias's post about SQL Server Max memory (http://bit.ly/sqlmemcalc), this script displays a SQL Server's: 
total memory, currently configured SQL max memory, and the calculated recommendation.

Jonathan notes that the formula used provides a *general recommendation* that doesn't account for everything that may be going on in your specific environment. 

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

.PARAMETER SqlServers
Allows you to specify a comma separated list of servers to query.

.PARAMETER ServersFromFile
Allows you to specify a list that's been populated by a list of servers to query. The format is as follows
server1
server2
server3

.PARAMETER SqlCms
Reports on a list of servers populated by the specified SQL Server Central Management Server.

.PARAMETER SqlCmsGroups
This is a parameter that appears when SqlCms has been specified. It is populated by Server Groups within the given Central Management Server.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$cred = Get-Credential, this pass this $cred to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (http://git.io/b3oo, clemaire@gmail.com)
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
https://gallery.technet.microsoft.com/scriptcenter/Get-Set-SQL-Max-Memory-19147057

.EXAMPLE   
Get-SqlMaxMemory -SqlCms sqlcluster

Get Memory Settings for all servers within the SQL Server Central Management Server "sqlcluster"

.EXAMPLE 
Get-SqlMaxMemory -SqlCms sqlcluster | Where-Object { $_.SqlMaxMB -gt $_.TotalMB } | Set-SqlMaxMemory -UseRecommended

Find all servers in CMS that have Max SQL memory set to higher than the total memory of the server (think 2147483647)

#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0)]
		[string[]]$SqlServers,
		# File with one server per line

		[string]$SqlServersFromFile,
		# Central Management Server

		[string]$SqlCms,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	DynamicParam { if ($SqlCms) { return (Get-ParamSqlCmsGroups -SqlServer $SqlCms -SqlCredential $SqlCredential) } }
	
	PROCESS
	{
		
		if ([string]::IsNullOrEmpty($SqlCms) -and [string]::IsNullOrEmpty($SqlServersFromFile) -and [string]::IsNullOrEmpty($SqlServers))
		{ throw "You must specify a server list source using -SqlServers or -SqlCms or -SqlServersFromFile" }
		
		$SqlCmsGroups = $psboundparameters.SqlCmsGroups
		if ($SqlCms) { $SqlServers = Get-SqlCmsRegServers -SqlServer $SqlCms -SqlCredential $SqlCredential -groups $SqlCmsGroups }
		If ($SqlServersFromFile) { $SqlServers = Get-Content $SqlServersFromFile }
		
		$collection = @()
		foreach ($SqlServer in $SqlServers)
		{
			Write-Verbose "Attempting to connect to $sqlserver"
			try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential }
			catch { Write-Warning "Can't connect to $sqlserver or access denied. Skipping."; continue }
			
			$maxmem = $server.Configuration.MaxServerMemory.ConfigValue
			
			$reserve = 1
			$totalMemory = $server.PhysicalMemory
			
			
			# Some servers underreport by 1MB.
			if (($totalmemory % 1024) -ne 0) { $totalMemory = $totalMemory + 1 }
			
			
			if ($totalMemory -ge 4096)
			{
				$currentCount = $totalMemory
				while ($currentCount/4096 -gt 0)
				{
					if ($currentCount -gt 16384)
					{
						$reserve += 1
						$currentCount += -8192
					}
					else
					{
						$reserve += 1
						$currentCount += -4096
					}
				}
				$recommendedMax = [int]($totalMemory - ($reserve * 1024))
			}
			else { $recommendedMax = $totalMemory * .5 }
			
			
			$object = New-Object PSObject -Property @{
				Server = $server.name
				TotalMB = $totalMemory
				SqlMaxMB = $maxmem
				RecommendedMB = $recommendedMax
			}
			$server.ConnectionContext.Disconnect()
			$collection += $object
		}
		return ($collection | Sort-Object Server | Select Server, TotalMB, SqlMaxMB, RecommendedMB)
	}
}

Function Set-SqlMaxMemory
{
<# 
.SYNOPSIS 
Sets SQL Server max memory then displays information relating to SQL Server Max Memory configuration settings. Works on SQL Server 2000-2014.

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

.PARAMETER SqlServers
Allows you to specify a comma separated list of servers to query.

.PARAMETER ServersFromFile
Allows you to specify a list that's been populated by a list of servers to query. The format is as follows
server1
server2
server3

.PARAMETER SqlCms
Reports on a list of servers populated by the specified SQL Server Central Management Server.

.PARAMETER SqlCmsGroups
This is a parameter that appears when SqlCms has been specified. It is populated by Server Groups within the given Central Management Server.

.PARAMETER MaxMB
Specifies the max megabytes

.PARAMETER UseRecommended
Inspired by Jonathan Kehayias's post about SQL Server Max memory (http://bit.ly/sqlmemcalc), this uses a formula to determine the default optimum RAM to use, then sets the SQL max value to that number.

Jonathan notes that the formula used provides a *general recommendation* that doesn't account for everything that may be going on in your specific environment. 

.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

.LINK 
https://gallery.technet.microsoft.com/scriptcenter/Get-Set-SQL-Max-Memory-19147057

.EXAMPLE 
Set-SqlMaxMemory sqlserver1 2048

Set max memory to 2048 MB on just one server, "sqlserver1"

.EXAMPLE 
Get-SqlMaxMemory -SqlCms sqlcluster | Where-Object { $_.SqlMaxMB -gt $_.TotalMB } | Set-SqlMaxMemory -UseRecommended

Find all servers in CMS that have Max SQL memory set to higher than the total memory of the server (think 2147483647),
then pipe those to Set-SqlMaxMemory and use the default recommendation

.EXAMPLE 
Set-SqlMaxMemory -SqlCms sqlcluster -SqlCmsGroups Express -MaxMB 512 -Verbose
Specifically set memory to 512 MB for all servers within the "Express" server group on CMS "sqlcluster"

#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0)]
		[string[]]$SqlServers,
		[parameter(Position = 1)]
		[int]$MaxMB,
		[string]$SqlServersFromFile,
		[string]$SqlCms,
		[switch]$UseRecommended,
		[Parameter(ValueFromPipeline = $True)]
		[object]$collection,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	DynamicParam { if ($SqlCms) { return (Get-ParamSqlCmsGroups -SqlServer $SqlCms -SqlCredential $SqlCredential) } }
	
	PROCESS
	{
		
		if ([string]::IsNullOrEmpty($SqlCms) -and [string]::IsNullOrEmpty($SqlServersFromFile) -and [string]::IsNullOrEmpty($SqlServers) -and $collection -eq $null)
		{ throw "You must specify a server list source using -SqlServers or -SqlCms or -SqlServersFromFile or you can pipe results from Get-SqlMaxMemory" }
		
		if ($MaxMB -eq 0 -and $UseRecommended -eq $false -and $collection -eq $null) { throw "You must specify -MaxMB or -UseRecommended" }
		
		if ($collection -eq $null)
		{
			$SqlCmsGroups = $psboundparameters.SqlCmsGroups
			if ($SqlCmsGroups -ne $null)
			{
				$collection = Get-SqlMaxMemory -SqlServers $SqlServers -SqlCms $SqlCms -SqlServersFromFile $SqlServersFromFile -SqlCmsGroups $SqlCmsGroups
			}
			else { $collection = Get-SqlMaxMemory -SqlServers $SqlServers -SqlCms $SqlCms -SqlServersFromFile $SqlServersFromFile }
		}
		
		$collection | Add-Member -NotePropertyName OldMaxValue -NotePropertyValue 0
		
		foreach ($row in $collection)
		{
			
			Write-Verbose "Attempting to connect to $sqlserver"
			try { $server = Connect-SqlServer -SqlServer $row.server -SqlCredential $SqlCredential }
			catch { Write-Warning "Can't connect to $sqlserver or access denied. Skipping."; continue }
			
			if (!(Test-SqlSa -SqlServer $server))
			{
				Write-Error "Not a sysadmin on $servername. Skipping."
				$server.ConnectionContext.Disconnect()
				continue
			}
			
			$row.OldMaxValue = $row.SqlMaxMB
			
			try
			{
				if ($UseRecommended)
				{
					Write-Verbose "Changing $($row.server) SQL Server max from $($row.SqlMaxMB) to $($row.RecommendedMB) MB"
					$server.Configuration.MaxServerMemory.ConfigValue = $row.RecommendedMB
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
			catch { Write-Error "Could not modify Max Server Memory for $($row.server)" }
			
			$server.ConnectionContext.Disconnect()
		}
		
		return $collection | Select Server, TotalMB, OldMaxValue, @{ name = "CurrentMaxValue"; expression = { $_.SqlMaxMB } }
	}
}
