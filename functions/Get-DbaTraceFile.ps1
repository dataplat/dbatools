function Get-DbaTraceFile {
	<#
.SYNOPSIS
Gets a list of trace file(s) from specied SQL Server Instance

.DESCRIPTION
This function returns a list of Trace Files on a SQL Server Instance and identify the default Trace File

.PARAMETER SqlInstance
A SQL Server instance to connect to

.PARAMETER SqlCredential
A credeial to use to conect to the SQL Instance rather than using Windows Authentication

.PARAMETER IsDefault
Switch that will only return the information for the default system trace

.PARAMETER Silent
Use this switch to disable any kind of verbose messages
	
.NOTES
Tags: Security, Trace
Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.EXAMPLE
Get-DbaTraceFile -SqlInstance sql2016 

Lists the tracefiles on the sql2016 SQL Server.
	
.EXAMPLE
Get-DbaTraceFile -SqlInstance sql2016 -IsDefault

Lists the default trace information on the sql2016 SQL Server. 
	
#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory, ValueFromPipeline)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$IsDefault,
		[switch]$Silent
	)
	
	process {
		
		foreach ($instance in $sqlinstance) {
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
				return
			}
			
				try {
					$server
				}
				catch {
					Stop-Function -Message "Error returned from SQL Server: $_" -Target $server -InnerErrorRecord $_
				}
			}
        }
}
