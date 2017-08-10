function Get-DbaRegisteredServerName {
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

		.PARAMETER NoCmsServer
			Excludes the CMS itself from returning in the output, if pulling NetBiosName, IpAddress, or ServerName.

		.PARAMETER FullObject
			Returns the full SMO RegisteredServer object for each server. This will not return an object for the CMS Server.

		.PARAMETER NetBiosName
			Returns just the NetBios names of each server.

		.PARAMETER IpAddress
			Returns just the IP addresses of each server.

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: RegisteredServer,CMS

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Get-DbaRegisteredServerName

		.EXAMPLE
			Get-DbaRegisteredServerName -SqlInstance sqlserver2014a

			Gets a list of server names from the CMS on sqlserver2014a, using Windows Credentials

		.EXAMPLE
			Get-DbaRegisteredServerName -SqlInstance sqlserver2014a -SqlCredential $credential

			Gets a list of server names from the CMS on sqlserver2014a, using SQL Authentication

		.EXAMPLE
			Get-DbaRegisteredServerName -SqlInstance sqlserver2014a -Group HR, Accounting

			Gets a list of servers in the HR and Accounting groups from the CMS on sqlserver2014a.

		.EXAMPLE
			Get-DbaRegisteredServerName -SqlInstance sqlserver2014a -NoCmsServer

			Gets a list of server names from the CMS on sqlserver2014a, but excludes the CMS server name.

		.EXAMPLE
			Get-DbaRegisteredServerName -SqlInstance sqlserver2014a -Group HR\Development

			Returns a list of server names in the HR and sub-group Development from the CMS on sqlserver2014a

		.EXAMPLE
			Get-DbaRegisteredServerName -SqlInstance sqlserver2014a -IpAddress

			Gets a list of the IP Addresses for servers in the CMS on sqlserver2014a, using Windows Credentials

		.EXAMPLE
			Get-DbaRegisteredServerName -SqlInstance sqlserver2014a -NetBiosName

			Gets a list of the NetBIOS names of the servers in the CMS on sqlserver2014a, using Windows Credentials

		.EXAMPLE
			Get-DbaRegisteredServerName -SqlInstance sqlserver2014a -FullObject

			Returns the full SMO RegisteredServer object for servers in the CMS on sqlserver2014a, using Windows Credentials
	#>
	[CmdletBinding(DefaultParameterSetName = "Default")]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]$SqlCredential,
		[Alias("Groups")]
		[object[]]$Group,
		[switch]$NoCmsServer,
		[parameter(ParameterSetName = "NetBios")]
		[switch]$NetBiosName,
		[parameter(ParameterSetName = "IP")]
		[switch]$IpAddress,
		[parameter(ParameterSetName = "FullObject")]
		[switch]$FullObject,
		[switch]$Silent
	)
	process {
		if ($NoCmsServer -and $FullObject) {
			Write-Message -Level Verbose -Message ("-NoCmsServer is not valid in combination with -FullObject, ignoring. " + `
					"-FullObject does not return an entry for the CMS itself.")
		}

		if (Test-FunctionInterrupt) { return }

		# see notes at Get-ParamSqlCmsGroups
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

		$servers = @()
		$cmsServers = @()
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

			if ($null -ne $Group) {
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

			#Store some information about the CMS's for later use
			try {
				$ip = (Resolve-DbaNetworkName $server.Name -Turbo -Silent).IpAddress
			}
			catch {
				$ip = $null
			}
			$fakeCms = [PSCustomObject]@{
				ComputerName = $server.ComputerNamePhysicalNetBIOS
				ServerName   = $server.Name
				IPAddress    = $ip
			}
			$cmsServers += $fakeCms
		}
	}

	end {
		# Use Resolve-DbaNetworkName to get IP / ComputerName
		foreach ($server in $servers) {
			try {
				$lookup = Resolve-DbaNetworkName $server.ServerName -Turbo -Silent
				Add-Member -Force -InputObject $server -MemberType NoteProperty -Name ComputerName -Value $lookup.ComputerName
				Add-Member -Force -InputObject $server -MemberType NoteProperty -Name IPAddress -Value $lookup.IPAddress
			}
			catch {
				Add-Member -Force -InputObject $server -MemberType NoteProperty -Name ComputerName -Value $null
				Add-Member -Force -InputObject $server -MemberType NoteProperty -Name IPAddress -Value $null
			}
		}

		if ($IpAddress) {
			$ret = @($servers | Select-Object IPAddress)

			if (!$NoCmsServer) {
				$ret += @($cmsServers | Select-Object IPAddress)
			}

			$ret | Select-Object -Unique -ExpandProperty IPAddress
		}

		elseif ($NetBiosName) {
			$ret = @($servers | Select-Object ComputerName)

			if (!$NoCmsServer) {
				$ret += @($cmsServers | Select-Object ComputerName)
			}

			$ret | Select-Object -Unique -ExpandProperty ComputerName
		}

		# #If -FullObject is specified, return everything, no distinct
		elseif ($FullObject) {
			return $servers
		}

		#By default, return only the server name for backwards compatibility
		else {
			$ret = @($servers | Select-Object ServerName)

			if (!$NoCmsServer) {
				$ret += @($cmsServers | Select-Object ServerName)
			}

			$ret | Select-Object -Unique -ExpandProperty ServerName
		}

		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Get-SqlRegisteredServerName
	}
}
