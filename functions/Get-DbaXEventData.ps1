function Get-DbaXEventData {
 <#
	.SYNOPSIS
	Read XEvents from a session

	.DESCRIPTION
	Read XEvents from a session. Returns a weird Microsoft.SqlServer.XEvent.Linq.QueryableXEventData enumeration object.

	.PARAMETER SqlInstance
	The SQL Instances that you're connecting to.

	.PARAMETER SqlCredential
	Credential object used to connect to the SQL Server as a different user

	.PARAMETER Session
	Only return specific sessions. This parameter is auto-populated.
		
	.PARAMETER SessionCollection
	Internal parameter for the pipeline - not supported yet
	
	.PARAMETER Silent
	If this switch is enabled, the internal messaging functions will be silenced.

	.NOTES
	Tags: Xevent
	Website: https://dbatools.io
	Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
	License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

	.LINK
	https://dbatools.io/Get-DbaXEventData

	.EXAMPLE
	Get-DbaXEventData -SqlInstance ServerA\sql987

	Returns events for all sessions

	.EXAMPLE
	#Get-DbaXEventSession -SqlInstance sql2014 -Session deadlocks | Get-DbaXEventData
	
	#Reads remote xevents by acccessing the file over the admin UNC share

#>
	[CmdletBinding()]
	param (
		[parameter(ValueFromPipeline)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]$SqlCredential,
		[string[]]$Session,
		[parameter(ValueFromPipeline)]
		[Microsoft.SqlServer.Management.XEvent.Session[]]$SessionCollection,
		[switch]$Silent
	)
	
	begin {
		if (-not $SqlInstance -and -not $SessionCollection) {
			Stop-Function -Message "You must specify a SqlInstance or pass a Session collection"
		}
	}
	
	process {
		if (Test-FunctionInterrupt) { return }
		
		foreach ($instance in $SqlInstance) {
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}
			
			if (-not $Session) {
				$SqlConn = $server.ConnectionContext.SqlConnectionObject
				$SqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $SqlConn
				$XEStore = New-Object  Microsoft.SqlServer.Management.XEvent.XEStore $SqlStoreConnection
				Write-Message -Level Verbose -Message "Getting XEvents Sessions on $instance."
				$Session = $XEStore.sessions | Where-Object IsRunning -eq $true | Select-Object -ExpandProperty Name 
			}
			
			foreach ($xesession in $Session) {
				New-Object -TypeName Microsoft.SqlServer.XEvent.Linq.QueryableXEventData(
					($server.ConnectionContext.ConnectionString),
					$xesession,
					[Microsoft.SqlServer.XEvent.Linq.EventStreamSourceOptions]::EventStream,
					[Microsoft.SqlServer.XEvent.Linq.EventStreamCacheOptions]::DoNotCache
				)
				
				#[System.Linq.Enumerable]::Count($results)
				# return $results 
				#foreach ($result in $results) {
				#	$result
				#}
			}
		}
	}
}