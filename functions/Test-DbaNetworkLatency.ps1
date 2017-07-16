Function Test-DbaNetworkLatency {
<#
	.SYNOPSIS
	Tests how long a query takes to return from SQL Server

	.DESCRIPTION
	This function is intended to help measure SQL Server network latency by establishing a connection and making a simple query. This is a better alternative
	than ping because it actually creates the connection to the SQL Server, and times not ony the entire routine, but also how long the actual queries take vs
	how long it takes to get the results.

	Server
	Count
	Total
	Avg
	ExecuteOnlyTotal
	ExecuteOnlyAvg

	.PARAMETER SqlInstance
	The SQL Server instance.

	.PARAMETER SqlCredential
	Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

	$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

	Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

	.PARAMETER Query
	Specifies the query to be executed. By default, "SELECT TOP 100 * FROM INFORMATION_SCHEMA.TABLES" will be executed on master. To execute in other databases, use fully qualified table names.

	.PARAMETER Count
	Specifies how many times the query should be executed. By default, the query is executed three times.

	.PARAMETER WhatIf
	Shows what would happen if the command were to run. No actions are actually performed.

	.PARAMETER Confirm
	Prompts you for confirmation before executing any changing operations within the command.

	.PARAMETER Silent
	Use this switch to disable any kind of verbose messages

	.NOTES
	Tags: Performance, Network
	Website: https://dbatools.io
	Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
	License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

	.LINK
	https://dbatools.io/Test-DbaNetworkLatency

	.EXAMPLE
	Test-DbaNetworkLatency -SqlInstance sqlserver2014a, sqlcluster

	Times the roundtrip return of "SELECT TOP 100 * FROM INFORMATION_SCHEMA.TABLES" on sqlserver2014a and sqlcluster using Windows credentials. 

	.EXAMPLE
	Test-DbaNetworkLatency -SqlInstance sqlserver2014a -SqlCredential $cred

	Times the execution results return of "SELECT TOP 100 * FROM INFORMATION_SCHEMA.TABLES" on sqlserver2014a using SQL credentials.

	.EXAMPLE
	Test-DbaNetworkLatency -SqlInstance sqlserver2014a, sqlcluster, sqlserver -Query "select top 10 * from otherdb.dbo.table" -Count 10

	Times the execution results return of "select top 10 * from otherdb.dbo.table" 10 times on sqlserver2014a, sqlcluster, and sqlserver using Windows credentials. 

#>
	[CmdletBinding()]
	[OutputType([System.Object[]])]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential][System.Management.Automation.CredentialAttribute()]$SqlCredential,
		[string]$Query = "select top 100 * from INFORMATION_SCHEMA.TABLES",
		[int]$Count = 3,
		[switch]$Silent
	)
	process {
		foreach ($instance in $SqlInstance) {
			try {
				$start = [System.Diagnostics.Stopwatch]::StartNew()
				$currentcount = 0
				try {
					Write-Message -Level Verbose -Message "Connecting to $instance"
					$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
				}
				catch {
					Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
				}
				
				do {
					
					if (++$currentcount -eq 1) {
						$first = [System.Diagnostics.Stopwatch]::StartNew()
					}
					$server.ConnectionContext.ExecuteWithResults($query) | Out-Null
					if ($currentcount -eq $count) {
						$last = $first.elapsed
					}
				}
				while ($currentcount -lt $count)
				
				$end = $start.elapsed
				
				$totaltime = $end.TotalMilliseconds
				$avg = $totaltime / $count
				
				$totalwarm = $last.TotalMilliseconds
				$avgwarm = $totalwarm / ($count - 1)
				
				[PSCustomObject]@{
					ComputerName = $server.NetName
					InstanceName = $server.ServiceName
					SqlInstance = $server.DomainInstanceName
					Count = $count
					Total = [prettytimespan]::FromMilliseconds($totaltime)
					Avg = [prettytimespan]::FromMilliseconds($avg)
					ExecuteOnlyTotal = [prettytimespan]::FromMilliseconds($totalwarm)
					ExecuteOnlyAvg = [prettytimespan]::FromMilliseconds($avgwarm)
				}
			}
			catch {
				Stop-Function -Message "Error occurred: $_" -InnerErrorRecord $_ -Continue
			}
		}
	}
	
	end {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Test-SqlNetworkLatency
	}
}
