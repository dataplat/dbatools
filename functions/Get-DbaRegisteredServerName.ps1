function Get-DbaRegisteredServerName {
	<#
		.SYNOPSIS
			Gets list of SQL Server names stored in SQL Server Central Management Server.

		.DESCRIPTION
			Returns a simple array of server names. Be aware of the dynamic parameter 'Group', which can be used to limit results to one or more groups you have created on the CMS. See get-help for examples.

		.PARAMETER SqlInstance
			SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection to allow the function to be executed against multiple SQL Server instances.
	
		.PARAMETER SqlCredential
			SqlCredential object to connect as. If not specified, current Windows login will be used.

		.PARAMETER Group
			Auto-populated list of groups in SQL Server Central Management Server. You can specify one or more, comma separated.

		.PARAMETER NoCmsServer
			By default, the Central Management Server name is included in the list. Use -NoCmsServer to exclude the CMS itself.

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

			Gets a list of all server names from the Central Management Server on sqlserver2014a, using Windows Credentials

		.EXAMPLE
			Get-DbaRegisteredServerName -SqlInstance sqlserver2014a -SqlCredential $credential

			Gets a list of all server names from the Central Management Server on sqlserver2014a, using SQL Authentication

		.EXAMPLE
			Get-DbaRegisteredServerName -SqlInstance sqlserver2014a -Group HR, Accounting

			Gets a list of server names in the HR and Accounting groups from the Central Management Server on sqlserver2014a.

		.EXAMPLE
			Get-DbaRegisteredServerName -SqlInstance sqlserver2014a -Group HR, Accounting -IpAddress

			Gets a list of server IP addresses in the HR and Accounting groups from the Central Management Server on sqlserver2014a.

		.EXAMPLE
			Get-DbaRegisteredServerName -SqlInstance sqlserver2014a -NoCmsServer

			Gets a list of server names from the Central Management Server on sqlserver2014a, but excludes the cms server name.

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
		[switch]$Silent
	)
	process {
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
				if ( $Base -eq $null -or [string]::IsNullOrWhiteSpace($Base) ) {
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

			if ($Group -ne $null) {
				foreach ($currentGroup in $Group) {
					$cms = Find-CmsGroup -CmsGrp $cmsStore.DatabaseEngineServerGroup.ServerGroups -Stopat $currentGroup
					$servers += ($cms.GetDescendantRegisteredServers()).ServerName
				}
			}
			else {
				$cms = $cmsStore.ServerGroups["DatabaseEngineServerGroup"]
				$servers += ($cms.GetDescendantRegisteredServers()).ServerName
			}

			if ($NoCmsServer -eq $false) {
				$servers += $SqlInstance.ComputerName
			}
		}
	}
	end {
		if (Test-FunctionInterrupt) { return }
		if ($NetBiosName -or $IpAddress) {
			$ipCollection = @()
			$netBiosCollection = @()
			$processed = @()

			foreach ($server in $servers) {
				if ($server -match '\\') {
					$server = $server.Split('\')[0]
				}

				if ($processed -contains $server) { continue }
				$processed += $server

				try {
					Write-Message -Level Verbose -Message "Testing connection to $server and resolving IP address"
					$ip = ((Test-Connection $server -Count 1 -ErrorAction SilentlyContinue).Ipv4Address | Select-Object -First 1).IPAddressToString
				}
				catch {
					Stop-Function -Message "Could not resolve IP address for $server" -ErrorRecord $_ -Continue
				}

				if ($ipCollection -notcontains $ip) {
					$ipCollection += $ip
				}

				if ($NetBiosName) {
					try {
						$hostName = (Get-DbaCmObject -ClassName Win32_NetworkAdapterConfiguration -ComputerName $server -SilentlyContinue | Where-Object IPEnabled -eq $true).PSComputerName

						if ($hostname -is [array]) {
							$hostname = $hostname[0]
						}
						Write-Message -Level Verbose -Message "Hostname resolved to $hostname"
						if ($hostname -eq $null) {
							$hostname = (nbtstat -A $ipAddress | Where-Object { $_ -match '\<00\>  UNIQUE' } | ForEach-Object { $_.SubString(4, 14) }).Trim()
						}
					}
					catch {
						Stop-Function -Message "Could not resolve NetBios name for $server" -ErrorRecord $_ -Continue
					}

					if ($netBiosCollection -notcontains $hostname) {
						$netBiosCollection += $hostname
					}
				}
			}
			
			if ($NetBiosName) {
				$netBiosCollection | Select-Object -Unique
			}
			else {
				$ipCollections | Select-Object -Unique
			}
		}
		else {
			$servers | Select-Object -Unique
		}
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Get-SqlRegisteredServerName
	}
}
