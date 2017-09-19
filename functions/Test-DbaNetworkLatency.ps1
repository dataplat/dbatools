function Test-DbaNetworkLatency {
	<#
		.SYNOPSIS
			Tests how long a query takes to return from SQL Server

		.DESCRIPTION
			This function is intended to help measure SQL Server network latency by establishing a connection and executing a simple query. This is a better than a simple ping because it actually creates the connection to the SQL Server and measures the time required for only the entire routine, but the duration of the query as well how long it takes for the results to be returned.

			By default, this command will execute "SELECT TOP 100 * FROM INFORMATION_SCHEMA.TABLES" three times.
		
			It will then output how long the entire connection and command took, as well as how long *only* the execution of the command took.
		
			This allows you to see if the issue is with the connection or the SQL Server itself.

        .PARAMETER SqlInstance
            The SQL Server you want to run the test on.
        
        .PARAMETER SqlCredential
 			Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

			$cred = Get-Credential, then pass $cred object to the -SqlCredential parameter.

			Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

			To connect as a different Windows user, run PowerShell as that user.
		
		.PARAMETER Query
			Specifies the query to be executed. By default, "SELECT TOP 100 * FROM INFORMATION_SCHEMA.TABLES" will be executed on master. To execute in other databases, use fully qualified object names.

		.PARAMETER Count
			Specifies how many times the query should be executed. By default, the query is executed three times.

		.PARAMETER WhatIf
			If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

		.PARAMETER Confirm
			If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

		.PARAMETER Silent
			If this switch is enabled, the internal messaging functions will be silenced.

		.NOTES
			Tags: Performance, Network
			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Test-DbaNetworkLatency

		.EXAMPLE
			Test-DbaNetworkLatency -SqlInstance sqlserver2014a, sqlcluster

			Tests the roundtrip return of "SELECT TOP 100 * FROM INFORMATION_SCHEMA.TABLES" on sqlserver2014a and sqlcluster using Windows credentials. 

		.EXAMPLE
			Test-DbaNetworkLatency -SqlInstance sqlserver2014a -SqlCredential $cred

			Tests the execution results return of "SELECT TOP 100 * FROM INFORMATION_SCHEMA.TABLES" on sqlserver2014a using SQL credentials.

		.EXAMPLE
			Test-DbaNetworkLatency -SqlInstance sqlserver2014a, sqlcluster, sqlserver -Query "select top 10 * from otherdb.dbo.table" -Count 10

			Tests the execution results return of "select top 10 * from otherdb.dbo.table" 10 times on sqlserver2014a, sqlcluster, and sqlserver using Windows credentials. 

	#>
	[CmdletBinding()]
	[OutputType([System.Object[]])]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]$SqlCredential,
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
					Write-Message -Level Verbose -Message "Connecting to $instance."
					$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
				}
				catch {
					Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
				}
				
				do {
					if (++$currentcount -eq 1) {
						$first = [System.Diagnostics.Stopwatch]::StartNew()
					}
					$null = $server.Query($query)
					if ($currentcount -eq $count) {
						$last = $first.elapsed
					}
				}
				while ($currentcount -lt $count)
				
				$end = $start.elapsed
				$totaltime = $end.TotalMilliseconds
				$average = $totaltime / $count
				
				$totalwarm = $last.TotalMilliseconds
				if ($Count -eq 1) {
					$averagewarm = $totalwarm
				}
				else {
					$averagewarm = $totalwarm / ($count - 1)
				}
				
				
				[PSCustomObject]@{
					ComputerName     = $server.NetName
					InstanceName     = $server.ServiceName
					SqlInstance      = $server.DomainInstanceName
					Count            = $count
					Total            = [prettytimespan]::FromMilliseconds($totaltime)
					Avg              = [prettytimespan]::FromMilliseconds($average)
					ExecuteOnlyTotal = [prettytimespan]::FromMilliseconds($totalwarm)
					ExecuteOnlyAvg   = [prettytimespan]::FromMilliseconds($averagewarm)
				} | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, 'Count as ExecutionCount', Total, 'Avg as Average', ExecuteOnlyTotal, 'ExecuteOnlyAvg as ExecuteOnlyAverage' #backwards compat
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
