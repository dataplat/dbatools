function Enable-DbaTraceFlag {
	<# 
	.SYNOPSIS 
		Enable a Global Trace Flag 
	.DESCRIPTION
		The function will set one or multiple trace flags on the SQL Server instance(s) listed
	
	.PARAMETER SqlInstance
		Allows you to specify a comma separated list of servers to query.

	.PARAMETER SqlCredential
		Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
		$cred = Get-Credential, this pass this $cred to the param. 

		Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	
	
	.PARAMETER TraceFlag
		Trace flag number to enable globally
	
	.PARAMETER Silent 
		Use this switch to disable any kind of verbose messages (this is required)

	.NOTES 
		Tags: TraceFlag
		Author: Garry Bargsley (@gbargsley), http://blog.garrybargsley.com
		
		Website: https://dbatools.io
		Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
		License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

	.LINK 
		https://dbatools.io/Enable-DbaTraceFlag

	.EXAMPLE   
		Enable-DbaTraceFlag -SqlInstance sql2016 -TraceFlag 3226
		Enable the trace flag 32266 on SQL Server instance sql2016

	.EXAMPLE
		Enable-DbaTraceFlag -SqlInstance sql2016 -TraceFlag 1117, 1118
		Enable multiple trace flags on SQL Server instance sql2016
#>
	[CmdletBinding()]
	param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlServer", "SqlServers")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]$SqlCredential,
		[parameter(Mandatory)]
		[int[]]$TraceFlag,
		[switch]$Silent
	)
	
	process {
		foreach ($instance in $SqlInstance) {
			Write-Message -Level Verbose -Message "Attempting to connect to $instance"
			
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}
			
			$CurrentRunningTraceFlags = Get-DbaTraceFlag -SqlInstance $server
			
			# We could combine all trace flags but the granularity is worth it
			foreach ($tf in $TraceFlag) {
				If ($CurrentRunningTraceFlags.TraceFlag -contains $tf) {
					Write-Message -Level Warning -Message "The Trace flag $tf is already running globally."
					continue
				}
				
				try {
					$query = "DBCC TRACEON ($tf, -1)"
					$server.Query($query)
					$server.Refresh()
					Get-DbaTraceFlag -SqlInstance $server -TraceFlag $TraceFlag
				}
				catch {
					Stop-Function -Message "Failure" -ErrorRecord $_ -Target $server -Continue
				}
			}
		}
	}
}