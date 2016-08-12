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
https://dbatools.io/Set-SqlMaxMemory

.EXAMPLE 
Set-SqlMaxMemory sqlserver1

Set max memory to the recommended MB on just one server, "sqlserver1"

.EXAMPLE 
Set-SqlMaxMemory sqlserver1 2048

Explicitly max memory to 2048 MB on just one server, "sqlserver1"

.EXAMPLE 
Get-SqlRegisteredServerName sqlserver| Get-SqlMaxMemory | Where-Object { $_.SqlMaxMB -gt $_.TotalMB } | Set-SqlMaxMemory

Find all servers in CMS that have Max SQL memory set to higher than the total memory of the server (think 2147483647), then pipe those to Set-SqlMaxMemory and use the default recommendation.

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