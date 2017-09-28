function Disable-DbaTraceFlag {
	<# 
	.SYNOPSIS 
		Disable a Global Trace Flag that is currently running

	.DESCRIPTION
		The function will disable a Trace Flag that is currently running globally on the SQL Server instance(s) listed
	
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
		Tags: Trace, Flag
		Author: Garry Bargsley (@gbargsley), http://blog.garrybargsley.com
		
		Website: https://dbatools.io
		Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
		License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

	.LINK 
		https://dbatools.io/Disable-DbaTraceFlag

	.EXAMPLE   
		Disable-DbaTraceFlag -SqlInstance sql2016 -TraceFlag 3226
		Disable the globally running trace flag 3226 on SQL Server instance sql2016
#>
	[CmdletBinding()]
	param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlServer", "SqlServers")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]$SqlCredential,
		[string[]]$TraceFlag,
		[switch]$Silent
	)
	
	process {
		foreach ($instance in $SqlInstance) {
			Write-Message -Level Verbose -Message "Attempting to connect to $instance"
			
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}

			foreach ($flag in $TraceFlag) {
				If ($TraceFlag.Count -gt 1) { 
					$combineParam += $flag + ","
				}
				else {
					$combineParam = $flag + ","
				}
			}

			$query = "DBCC TRACEOFF ($combineParam -1)"

			if ($TraceFlag) {
				try {
					$server.Query($query)
				}
				catch {
					Stop-Function -Message "Failure" -ErrorRecord $_ -Target $server -Continue
				}
			}
		}
	}
}
