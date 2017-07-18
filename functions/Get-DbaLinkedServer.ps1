function Get-DbaLinkedServer {
	<#
		.SYNOPSIS
			Gets all linked servers and summary of information from the sql servers listed

		.DESCRIPTION
			Retrieves information about each linked server on the instance

		.PARAMETER SqlInstance
			SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and recieve pipeline input to allow the function
			to be executed against multiple SQL Server instances.

		.PARAMETER SqlCredential
			SqlCredential object to connect as. If not specified, current Windows login will be used.

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Author: Stephen Bennett ( https://sqlnotesfromtheunderground.wordpress.com/ )

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Get-DbaLinkedServer

		.EXAMPLE
			Get-DbaLinkedServer -SqlInstance DEV01

			Returns all Linked Servers for the SQL Server instance DEV01
	#>
	[CmdletBinding(DefaultParameterSetName = 'Default')]
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential][System.Management.Automation.CredentialAttribute()]$SqlCredential = [System.Management.Automation.PSCredential]::Empty,
		[switch]$Silent
	)
	foreach ($Instance in $SqlInstance) {
		try {
			Write-Message -Level Verbose -Message "Connecting to $instance"
			$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
		}
		catch {
			Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
		}

		$lservers = $server.LinkedServers

		if ($LinkedServer) {
			$lservers = $lservers | Where-Object { $_.Name -in $LinkedServer }
		}

		foreach ($ls in $lservers) {
			Add-Member -Force -InputObject $ls -MemberType NoteProperty -Name ComputerName -value $server.NetName
			Add-Member -Force -InputObject $ls -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
			Add-Member -Force -InputObject $ls -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
			Add-Member -Force -InputObject $ls -MemberType NoteProperty -Name Impersonate -value $ls.LinkedServerLogins.Impersonate
			Add-Member -Force -InputObject $ls -MemberType NoteProperty -Name RemoteUser -value $ls.LinkedServerLogins.RemoteUser

			Select-DefaultView -InputObject $ls -Property ComputerName, InstanceName, SqlInstance, Name, 'DataSource as RemoteServer', ProductName, Impersonate, RemoteUser, 'DistPublisher as Publisher', Distributor, DateLastModified
		}
	}
}