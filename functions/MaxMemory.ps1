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

.PARAMETER SqlServer
Allows you to specify a comma separated list of servers to query.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$cred = Get-Credential, this pass this $cred to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.NOTES 
Author  : Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2105 Chrissy LeMaire

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
https://dbatools.io/Get-SqlMaxMemory

.EXAMPLE   
Get-SqlMaxMemory -SqlServer sqlcluster,sqlserver2012

Get Memory Settings for all servers within the SQL Server Central Management Server "sqlcluster"

.EXAMPLE 
Get-SqlMaxMemory -SqlServer sqlcluster | Where-Object { $_.SqlMaxMB -gt $_.TotalMB } | Set-SqlMaxMemory 

Find all servers in CMS that have Max SQL memory set to higher than the total memory of the server (think 2147483647)

#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory=$true)]
		[Alias("ServerInstance", "SqlInstance", "SqlServers")]
		[string[]]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	PROCESS
	{
		$collection = @()
		foreach ($servername in $sqlserver)
		{
			Write-Verbose "Attempting to connect to $servername"
			try
			{
				$server = Connect-SqlServer -SqlServer $servername -SqlCredential $SqlCredential
			}
			catch
			{
				Write-Warning "Can't connect to $servername or access denied. Skipping."
				continue
			}
			
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

Inspired by Jonathan Kehayias's post about SQL Server Max memory (http://bit.ly/sqlmemcalc), this uses a formula to determine the default optimum RAM to use, then sets the SQL max value to that number.

Jonathan notes that the formula used provides a *general recommendation* that doesn't account for everything that may be going on in your specific environment. 

.PARAMETER SqlServer
Allows you to specify a comma separated list of servers to query.

.PARAMETER MaxMb
Specifies the max megabytes

.NOTES 
Author  : Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

.LINK 
https://gallery.technet.microsoft.com/scriptcenter/Get-Set-SQL-Max-Memory-19147057

.EXAMPLE 
Set-SqlMaxMemory sqlserver1 2048

Set max memory to 2048 MB on just one server, "sqlserver1"

.EXAMPLE 
Get-SqlMaxMemory -SqlServer sqlserver2014 | Where-Object { $_.SqlMaxMB -gt $_.TotalMB } | Set-SqlMaxMemory

Find all servers in CMS that have Max SQL memory set to higher than the total memory of the server (think 2147483647),
then pipe those to Set-SqlMaxMemory and use the default recommendation

.EXAMPLE 
Set-SqlMaxMemory -SqlCms sqlcluster -SqlCmsGroups Express -MaxMB 512 -Verbose
Specifically set memory to 512 MB for all servers within the "Express" server group on CMS "sqlcluster"

#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0)]
		[Alias("ServerInstance", "SqlInstance", "SqlServers")]
		[string[]]$SqlServer,
		[parameter(Position = 1)]
		[int]$MaxMb,
		[Parameter(ValueFromPipeline = $True)]
		[object]$collection,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	PROCESS
	{
		
		if ($SqlServer.length -eq 0 -and $collection -eq $null)
		{
			throw "You must specify a server list source using -SqlServer or you can pipe results from Get-SqlMaxMemory"
		}
		
		if ($MaxMB -eq 0)
		{
			$UseRecommended = $true
		}
		
		if ($collection -eq $null)
		{
			$collection = Get-SqlMaxMemory -SqlServer $SqlServer
		}
		
		$collection | Add-Member -NotePropertyName OldMaxValue -NotePropertyValue 0
		
		foreach ($row in $collection)
		{
			
			Write-Verbose "Attempting to connect to $sqlserver"
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
