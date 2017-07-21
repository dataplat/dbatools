function Get-DbaRegisteredServerName {
	<#
		.SYNOPSIS
			Gets list of SQL Server names stored in SQL Server Central Management Server.

		.DESCRIPTION
			Returns a simple array of server names. Be aware of the dynamic parameter 'Group', which can be used to limit results to one or more groups you have created on the CMS. See get-help for examples.

		.PARAMETER SqlInstance
			The SQL Server instance.

		.PARAMETER SqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted.

			To use:
			$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

			Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Group
			Auto-populated list of groups in SQL Server Central Management Server. You can specify one or more, comma separated.

		.PARAMETER NoCmsServer
			By default, the Central Management Server name is included in the list. Use -NoCmsServer to exclude the CMS itself.

		.PARAMETER NetBiosName
			Returns just the NetBios names of each server.

		.PARAMETER IpAddr
			Returns just the ip addresses of each server.

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
			Get-DbaRegisteredServerName -SqlInstance sqlserver2014a -Group HR, Accounting -IpAddr

			Gets a list of server IP addresses in the HR and Accounting groups from the Central Management Server on sqlserver2014a.
	#>
	[CmdletBinding(DefaultParameterSetName = "Default")]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter]$SqlInstance,
		[PSCredential]$SqlCredential,
		[Alias("Groups")]
		[object[]]$Group,
		[switch]$NoCmsServer,
		[parameter(ParameterSetName = "NetBios")]
		[switch]$NetBiosName,
		[parameter(ParameterSetName = "IP")]
		[switch]$IpAddr,
		[switch]$Silent
	)

	begin {
		try {
			$server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
		}
		catch {
			Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
		}

		$sqlconnection = $server.ConnectionContext.SqlConnectionObject

		try {
			$cmstore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($sqlconnection)
		}
		catch {
			Stop-Function -Message "Cannot access Central Management Server"
			return
		}
	}

	process {
		if (Test-FunctionInterrupt) { return }

		# see notes at Get-ParamSqlCmsGroups
		function Find-CmsGroup($CmsGrp, $base = '', $stopat) {
			$results = @()
			foreach ($el in $CmsGrp) {
				if ($base -eq '') {
					$partial = $el.name
				}
				else {
					$partial = "$base\$($el.name)"
				}
				if ($partial -eq $stopat) {
					return $el
				}
				else {
					foreach ($group in $el.ServerGroups) {
						$results += Find-CmsGroup $group $partial $stopat
					}
				}
			}
			return $results
		}

		$servers = @()
		if ($Group -ne $null) {
			foreach ($currentGroup in $Group) {
				$cms = Find-CmsGroup $cmstore.DatabaseEngineServerGroup.ServerGroups '' $currentGroup
				$servers += ($cms.GetDescendantRegisteredServers()).ServerName
			}
		}
		else {
			$cms = $cmstore.ServerGroups["DatabaseEngineServerGroup"]
			$servers = ($cms.GetDescendantRegisteredServers()).ServerName
		}

		if ($NoCmsServer -eq $false) {
			$servers += $SqlInstance.ComputerName
		}
	}
	end {
		if ($NetBiosName -or $IpAddr) {
			$ipcollection = @()
			$netbioscollection = @()
			$processed = @()

			foreach ($server in $servers) {
				if ($server -match '\\') {
					$server = $server.Split('\')[0]
				}

				if ($processed -contains $server) { continue }
				$processed += $server

				try {
					Write-Message -Level Verbose -Message "Testing connection to $server and resolving IP address"
					$ipaddress = ((Test-Connection $server -Count 1 -ErrorAction SilentlyContinue).Ipv4Address | Select-Object -First 1).IPAddressToString
				}
				catch {
					Stop-Function -Message "Could not resolve IP address for $server" -ErrorRecord $_ -Continue
				}

				if ($ipcollection -notcontains $ipaddress) {
					$ipcollection += $ipaddress
				}

				if ($NetBiosName) {
					try {
						$hostName = (Get-DbaCmObject -ClassName Win32_NetworkAdapterConfiguration -ComputerName $ipaddress -SilentlyContinue | Where-Object IPEnabled -eq $true).PSComputerName

						if ($hostname -is [array]) {
							$hostname = $hostname[0]
						}
						Write-Message -Level Verbose -Message "Hostname resolved to $hostname"
						if ($hostname -eq $null) {
							$hostname = (nbtstat -A $ipaddress | Where-Object { $_ -match '\<00\>  UNIQUE' } | ForEach-Object { $_.SubString(4, 14) }).Trim()
						}
					}
					catch {
						Stop-Function -Message "Could not resolve NetBios name for $server" -ErrorRecord $_ -Continue
					}

					if ($netbioscollection -notcontains $hostname) {
						$netbioscollection += $hostname
					}
				}
			}

			if ($NetBiosName) {
				return $netbioscollection
			}
			else {
				return $ipcollection
			}
		}
		else {
			return $servers
		}
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Get-SqlRegisteredServerName
	}
}