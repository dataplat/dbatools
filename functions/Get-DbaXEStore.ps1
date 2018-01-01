function Get-DbaXEStore {
 <#
	.SYNOPSIS
	Get a Extended Events store

	.DESCRIPTION
	Get a Extended Events store

	.PARAMETER SqlInstance
	The SQL Instances that you're connecting to.

	.PARAMETER SqlCredential
	Credential object used to connect to the SQL Server as a different user

	.PARAMETER EnableException
	By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
	This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
	Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
	
	.NOTES
	Website: https://dbatools.io
	Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
	License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

	.LINK
	https://dbatools.io/Get-DbaXEStore

	.EXAMPLE
	Get-DbaXEStore -SqlInstance ServerA\sql987

	Returns a XEvent Store

#>
	[CmdletBinding()]
	param (
		[parameter(Mandatory, ValueFromPipeline)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]$SqlCredential,
		[switch]$EnableException
	)

	process {
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
			$store = New-Object  Microsoft.SqlServer.Management.XEvent.XEStore $SqlStoreConnection
			
			Add-Member -Force -InputObject $store -MemberType NoteProperty -Name ComputerName -Value $server.NetName
			Add-Member -Force -InputObject $store -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
			Add-Member -Force -InputObject $store -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
			$store
			#Select-DefaultView -InputObject $x -Property ComputerName, InstanceName, SqlInstance, Name, Status, StartTime, AutoStart, State, Targets, TargetFile, Events, MaxMemory, MaxEventSize
		}
	}
}