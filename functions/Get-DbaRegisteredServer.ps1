function Get-DbaRegisteredServer {
	<#
		.SYNOPSIS
			Gets list of SQL Server objects stored in SQL Server Central Management Server (CMS).

		.DESCRIPTION
			Returns an array of servers found in the CMS. By default, the command returns the ServerName property
			of the servers. You can specify -FullObject to return the full SMO object, -IpAddress for only the
			IPv4 Addresses of the server, and -NetBiosName for only the ComputerName.

		.PARAMETER SqlInstance
			SQL Server name or SMO object representing the SQL Server to connect to.
			This can be a collection to allow the function to be executed against multiple SQL Server instances.

		.PARAMETER SqlCredential
			SqlCredential object to connect as. If not specified, current Windows login will be used.

		.PARAMETER Group
			List of groups to filter to in SQL Server Central Management Server. You can specify one or more, comma separated.

		.PARAMETER ExcludeGroup
			List of groups to filter out. You can specify one or more, comma separated.

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Original Author (from Get-DbaRegsiteredServerName): Chrissy LeMaire (@cl)
			Author: Bryan Hamby (@galador)
			Tags: RegisteredServer,CMS

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Get-DbaRegisteredServer

		.EXAMPLE
			Get-DbaRegisteredServer -SqlInstance sqlserver2014a

			Gets a list of servers from the CMS on sqlserver2014a, using Windows Credentials

		.EXAMPLE
			Get-DbaRegisteredServer -SqlInstance sqlserver2014a -SqlCredential $credential

			Gets a list of servers from the CMS on sqlserver2014a, using SQL Authentication

		.EXAMPLE
			Get-DbaRegisteredServer -SqlInstance sqlserver2014a -Group HR, Accounting

			Gets a list of servers in the HR and Accounting groups from the CMS on sqlserver2014a.

		.EXAMPLE
			Get-DbaRegisteredServer -SqlInstance sqlserver2014a -Group HR\Development

			Returns a list of servers in the HR and sub-group Development from the CMS on sqlserver2014a
	#>
	[CmdletBinding(DefaultParameterSetName = "Default")]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]$SqlCredential,
		[Alias("Groups")]
		[object[]]$Group,
		[object[]]$ExcludeGroup,
		[switch]$NoCmsServer,
		[switch]$Silent
	)
	begin {
		function Find-CmsGroup {
			[cmdletbinding()]
			param(
				$CmsGrp,
				$Base = $null,
				$Stopat
			)
			$results = @()
			foreach ($el in $CmsGrp) {
				if ($null -eq $Base -or [string]::IsNullOrWhiteSpace($Base) ) {
					$partial = $el.name
				}
				else {
					$partial = "$Base\$($el.name)"
				}
				if ($partial -eq $Stopat) {
					return $el
				}
				else {
					foreach ($elg in $el.ServerGroups) {
						$results += Find-CmsGroup -CmsGrp $elg -Base $partial -Stopat $Stopat
					}
				}
			}
			return $results
		}
	}

	process {
		if (Test-FunctionInterrupt) { return }

		$servers = @()
		foreach ($instance in $SqlInstance) {
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
				$sqlConnection = $server.ConnectionContext.SqlConnectionObject
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}

			try {
				$cmsStore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($sqlConnection)
			}
			catch {
				Stop-Function -Message "Cannot access Central Management Server" -ErrorRecord $_ -Continue
				return
			}

			if (Test-Bound -ParameterName ExcludeGroup) {
				$Group = ($cmsStore.DatabaseEngineServerGroup.ServerGroups | Where-Object Name -notin $ExcludeGroup).Name
			}

			if ($Group) {
				foreach ($currentGroup in $Group) {
					$cms = Find-CmsGroup -CmsGrp $cmsStore.DatabaseEngineServerGroup.ServerGroups -Stopat $currentGroup
					if ($null -eq $cms) {
						Write-Message -Level Output -Message "No groups found matching that name"
						continue
					}
					$servers += ($cms.GetDescendantRegisteredServers())
				}
			}
			else {
				$cms = $cmsStore.ServerGroups["DatabaseEngineServerGroup"]
				$servers += ($cms.GetDescendantRegisteredServers())
			}
		}
	}

	end {
		return $servers
	}
}
