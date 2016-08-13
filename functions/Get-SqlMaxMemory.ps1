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
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

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
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlInstance", "SqlServers")]
		[string[]]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	PROCESS
	{
		$collection = @()
		foreach ($servername in $sqlserver)
		{
			try
			{
				# Get number of instances running
				$ipaddr = Resolve-SqlIpAddress $servername
				$sqls = Get-Service -ComputerName $ipaddr | Where-Object { $_.DisplayName -like 'SQL Server (*' -and $_.Status -eq 'Running' }
				$sqlcount = $sqls.count
			}
			catch
			{
				Write-Warning "Couldn't get accurate SQL Server instance count. Defaulting to 1."
				$sqlcount = 1
			}
			
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
			else
			{
				$recommendedMax = $totalMemory * .5
			}
			
			$recommendedMax = $recommendedMax/$sqlcount
			
			$object = New-Object PSObject -Property @{
				Server = $server.name
				TotalMB = $totalMemory
				SqlMaxMB = $maxmem
				InstanceCount = $sqlcount
				RecommendedMB = $recommendedMax
			}
			$server.ConnectionContext.Disconnect()
			$collection += $object
		}
		return ($collection | Sort-Object Server | Select-Object Server, TotalMB, SqlMaxMB, InstanceCount, RecommendedMB)
	}
}


