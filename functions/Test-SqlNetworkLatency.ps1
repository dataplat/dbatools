Function Test-SqlNetworkLatency
{
<#
.SYNOPSIS
Tests how long a query takes to return from SQL Server

.DESCRIPTION
This function is intended to help measure SQL Server network latency by establishing a connection and making a simple query. This is a better alternative
than ping because it actually creates the connection to the SQL Server, and times not ony the entire routine, but also how long the actual queries take vs
how long it takes to get the results.
	
Server
Count
TotalMs
AvgMs
ExecuteOnlyTotalMS
ExecuteOnlyAvgMS
	
.PARAMETER SqlServer
The SQL Server instance.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 

Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

.PARAMETER Query
Specifies the query to be executed. By default, "SELECT TOP 100 * FROM sys.objects" will be executed on master. To execute in other databases, use fully qualified table names.

.PARAMETER Count
Specifies how many times the query should be executed. By default, the query is executed three times.
	
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
https://dbatools.io/Test-SqlNetworkLatency

.EXAMPLE
Test-SqlNetworkLatency -SqlServer sqlserver2014a, sqlcluster

Times the roundtrip return of "SELECT TOP 100 * FROM sys.objects" on sqlserver2014a and sqlcluster using Windows credentials. 

.EXAMPLE   
Test-SqlNetworkLatency -SqlServer sqlserver2014a -SqlCredential $cred
	
Times the execution results return of "SELECT TOP 100 * FROM sys.objects" on sqlserver2014a using SQL credentials. 
	
.EXAMPLE   
Test-SqlNetworkLatency -SqlServer sqlserver2014a, sqlcluster, sqlserver -Query "select top 10 * from otherdb.dbo.table" -Count 10

Times the execution results return of "select top 10 * from otherdb.dbo.table" 10 times on sqlserver2014a, sqlcluster, and sqlserver using Windows credentials. 
	
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object[]]$SqlServer,
		[object]$SqlCredential,
		[string]$Query = "SELECT TOP 100 * FROM sys.objects",
		[int]$Count = 3
	)
	
	BEGIN
	{
		$allresults = @()
	}
	
	PROCESS
	{
		foreach ($server in $SqlServer)
		{
			try
			{
				$start = [System.Diagnostics.Stopwatch]::StartNew()
				$currentcount = 0
				$sourceserver = Connect-SqlServer -SqlServer $server -SqlCredential $SqlCredential
				$singleresult = $sourceserver.ConnectionContext.ExecuteWithResults($query)
				
				do
				{
					if (++$currentcount -eq 1)
					{
						$first = [System.Diagnostics.Stopwatch]::StartNew()
					}
					if ($currentcount -eq $count)
					{
						$last = $first.elapsed
					}
				}
				while ($currentcount -lt $count)
				
				$end = $start.elapsed
				
				$totaltime = $end.TotalMilliseconds
				$avg = $totaltime / $count
				
				$totalwarm = $last.TotalMilliseconds
				$avgwarm = $totalwarm / ($count - 1)
				
				$allresults += [PSCustomObject]@{
					Server = $server
					Count = $count
					TotalMs = $totaltime
					AvgMs = $avg
					ExecuteOnlyTotalMs = $totalwarm
					ExecuteOnlyAvgMs = $avgwarm
				}
			}
			catch
			{
				throw $_
			}
		}
	}
	
	END
	{
		return $allresults
		$sourceserver.ConnectionContext.Disconnect()
	}
}