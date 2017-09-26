function Get-DbaXEventsSession {
 <#
	.SYNOPSIS
	Get a list of Extended Events Sessions

	.DESCRIPTION
	Retrieves a list of Extended Events Sessions

	.PARAMETER SqlInstance
	The SQL Instances that you're connecting to.

	.PARAMETER SqlCredential
	Credential object used to connect to the SQL Server as a different user

	.PARAMETER Session
	Only return specific sessions. This parameter is auto-populated.
		
	.PARAMETER Silent
	If this switch is enabled, the internal messaging functions will be silenced.

	.NOTES
	Tags: Memory
	Author: Klaas Vandenberghe ( @PowerDBAKlaas )
	Website: https://dbatools.io
	Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
	License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

	.LINK
	https://dbatools.io/Get-DbaXEventsSession

	.EXAMPLE
	Get-DbaXEventsSession -SqlInstance ServerA\sql987

	Returns a custom object with ComputerName, SQLInstance, Session, StartTime, Status and other properties.

	.EXAMPLE
	Get-DbaXEventsSession -SqlInstance ServerA\sql987 | Format-Table ComputerName, SqlInstance, Session, Status -AutoSize

	Returns a formatted table displaying ComputerName, SqlInstance, Session, and Status.

	.EXAMPLE
	'ServerA\sql987','ServerB' | Get-DbaXEventsSession

	Returns a custom object with ComputerName, SqlInstance, Session, StartTime, Status and other properties, from multiple SQL Instances.

#>
	[CmdletBinding()]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]$SqlCredential,
		[Alias("Sessions")]
		[object[]]$Session,
		[switch]$Silent
	)
	
	begin {
		if ([System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.XEvent") -eq $null) {
			Stop-Function -Message "SMO version is too old. To collect Extended Events, you must have SQL Server Management Studio 2012 or higher installed."
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
			
			$SqlConn = $server.ConnectionContext.SqlConnectionObject
			$SqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $SqlConn
			$XEStore = New-Object  Microsoft.SqlServer.Management.XEvent.XEStore $SqlStoreConnection
			Write-Message -Level Verbose -Message "Getting XEvents Sessions on $instance."
			
			$xesessions = $XEStore.sessions
			
			if ($Session) {
				$xesessions = $xesessions | Where-Object { $_.Name -in $Session }
			}
			
			foreach ($x in $xesessions) {
				$status = switch ($x.IsRunning) { $true { "Running" } $false { "Stopped" } }
				$files = $x.Targets.TargetFields | Where-Object Name -eq Filename | select -ExpandProperty Value
				Add-Member -Force -InputObject $x -MemberType NoteProperty -Name ComputerName -Value $server.NetName
				Add-Member -Force -InputObject $x -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
				Add-Member -Force -InputObject $x -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
				Add-Member -Force -InputObject $x -MemberType NoteProperty -Name Status -Value $status
				Add-Member -Force -InputObject $x -MemberType NoteProperty -Name Session -Value $x.Name
				Add-Member -Force -InputObject $x -MemberType NoteProperty -Name TargetFiles -Value $files
				
				Select-DefaultView -InputObject $x -Property ComputerName, InstanceName, SqlInstance, Name, Status, StartTime, AutoStart, State, Targets, TargetFiles, Events, MaxMemory, MaxEventSize
			}
		}
	}
}