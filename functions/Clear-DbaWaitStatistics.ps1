function Clear-DbaWaitStatistics {
	<# 
	.SYNOPSIS 
		Clears wait statistics

	.DESCRIPTION 
		Reset the aggregated statistics - basically just executes DBCC SQLPERF (N'sys.dm_os_wait_stats', CLEAR)

	.PARAMETER SqlInstance
		Allows you to specify a comma separated list of servers to query.

	.PARAMETER SqlCredential
		Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
		$cred = Get-Credential, this pass this $cred to the param. 

		Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

	.PARAMETER Silent 
		Use this switch to disable any kind of verbose messages

	.NOTES 
		Tags: WaitStatistic
		Website: https://dbatools.io
		Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
		License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

	.LINK 
		https://dbatools.io/Clear-DbaWaitStatistics

	.EXAMPLE   
		Clear-DbaWaitStatistics -SqlInstance sql2008, sqlserver2012
		Clear wait stats on servers sql2008 and sqlserver2012.
	#>
	[CmdletBinding()]
	param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlServer", "SqlServers")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]$SqlCredential,
		[switch]$Silent
	)
	process {
		foreach ($instance in $SqlInstance) {
			Write-Message -Level Verbose -Message "Attempting to connect to $instance"
			
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}
			
			try {
				$server.Query("DBCC SQLPERF (N'sys.dm_os_wait_stats', CLEAR);")
				$status = "Success"
			}
			catch {
				$status = $_
			}
			
			[PSCustomObject]@{
				ComputerName    = $server.NetName
				InstanceName    = $server.ServiceName
				SqlInstance	    = $server.DomainInstanceName
				Status		    = $status
			}
		}
	}
}