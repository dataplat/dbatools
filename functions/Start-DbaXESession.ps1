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

	.PARAMETER EnableException
	By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
	This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
	Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

	.NOTES
	Tags: Xevent
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
		[Microsoft.SqlServer.Management.XEvent.Session[]]$SessionCollection,
		[switch]$EnableException
	)
	
	begin {
		# Start each XESession
		function Start-XESessions {
			[CmdletBinding()]
			param ([Microsoft.SqlServer.Management.XEvent.Session[]]$xesessions)

			foreach ($x in $xesessions) {
				$instance = $x.Parent.Name
				$session = $x.Name
				if (-Not $x.isRunning) {
					Write-Message -Level Verbose -Message "Starting XEvent Session $session on $instance."
					$x.Start()
					Get-DbaXESession -SqlInstance $x.Parent -Session $session
				} else {
					Write-Message -Level Warning -Message "$session on $instance is already running"
				}
			}
		}
	}
	
	process {
		if ($SessionCollection) {
			Start-XESessions $SessionCollection
		} else {
			foreach ($instance in $SqlInstance) {
				$xesessions = Get-DbaXESession -SqlInstance $instance -SqlCredential $SqlCredential
				
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