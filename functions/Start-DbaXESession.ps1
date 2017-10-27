function Start-DbaXESession {
<#
	.SYNOPSIS
	Starts Extended Events sessions.

	.DESCRIPTION
	This script starts Extended Events sessions on a SQL Server instance.

	.PARAMETER SqlInstance
	The SQL Instances that you're connecting to.

	.PARAMETER SqlCredential
	Credential object used to connect to the SQL Server as a different user

	.PARAMETER Session
	Only start specific Extended Events sessions.

	.PARAMETER AllSessions
	Start all Extended Events sessions on an instance, ignoring the packaged sessions: AlwaysOn_health, system_health, telemetry_xevents.

	.PARAMETER Silent
	If this switch is enabled, the internal messaging functions will be silenced.

	.NOTES
	Tags: Memory
	Author: Doug Meyers
	Website: https://dbatools.io
	Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
	License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

	.LINK
	https://dbatools.io/Start-DbaXESession

	.EXAMPLE
	Start-DbaXESession -SqlInstance sqlserver2012 -AllSessions

	Starts all Extended Event Session on the sqlserver2014 instance.

	.EXAMPLE
	Start-DbaXESession -SqlInstance sqlserver2012 -Session xesession1,xesession2

	Starts the xesession1 and xesession2 Extended Event sessions.

	.EXAMPLE
	Get-DbaXESession -SqlInstance sqlserver2012 -Session xesession1 | Start-DbaXESession

	Starts the sessions returned from the Get-DbaXESession function.

#>
	[CmdletBinding(DefaultParameterSetName='Session')]  
	param (
		[parameter(Position=1, Mandatory, ParameterSetName='Session')]
		[parameter(Position=1, Mandatory, ParameterSetName='All')]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,

		[parameter(ParameterSetName='Session')]
		[parameter(ParameterSetName='All')]
		[PSCredential]$SqlCredential,

		[parameter(Mandatory, ParameterSetName='Session')]
		[Alias("Sessions")]
		[object[]]$Session,

		[parameter(Mandatory, ParameterSetName='All')]
		[switch]$AllSessions,

		[parameter(Mandatory, ValueFromPipeline, ParameterSetName='Object')]
		[object]$SessionCollection,

		[switch]$Silent
	)
	
	begin {
		if ([System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.XEvent") -eq $null) {
			Stop-Function -Message "SMO version is too old. To collect Extended Events, you must have SQL Server Management Studio 2012 or higher installed."
		}

		# Start each XESession
		function Start-XESessions {
			[CmdletBinding()]
			param ([object]$xesessions)

			foreach ($x in $xesessions) {
				$instance = $x.Parent.ServerName
				$session = $x.Name
				$running = $x.isRunning
				if (-Not $running) {
					Write-Message -Level Verbose -Message "Starting XEvent Session $session on $instance."
					$x.Start()
					$x
				} else {
					Write-Message -Level Verbose -Message "$session on $instance is already running"
				}
			}
		}
	}
	
	process {
		if (Test-FunctionInterrupt) { return }

		if ($SessionCollection.Count -gt 0) {
			Start-XESessions $SessionCollection
		} else {
			foreach ($instance in $SqlInstance) {
				try {
					Write-Message -Level Verbose -Message "Connecting to $instance"
					$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
				}
				catch {
					Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
				}

				# Start with all xesessions on the instance.
				$SqlConn = $server.ConnectionContext.SqlConnectionObject
				$SqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $SqlConn
				$XEStore = New-Object  Microsoft.SqlServer.Management.XEvent.XEStore $SqlStoreConnection
				Write-Message -Level Verbose -Message "Getting XEvents Sessions on $instance."
				$xesessions = $XEStore.sessions
				
				# Filter xesessions based on parameters
				if ($Session) {
					$xesessions = $xesessions | Where-Object { $_.Name -in $Session }
				} elseif ($AllSessions) {
					$systemSessions = @('AlwaysOn_health', 'system_health', 'telemetry_xevents')
					$xesessions = $xesessions | Where-Object { $_.Name -notin $systemSessions }
				}
				
				Start-XESessions $xesessions
			}
		}
	}
}