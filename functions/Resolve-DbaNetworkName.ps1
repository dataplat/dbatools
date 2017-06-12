function Resolve-DbaNetworkName {
	<#
		.SYNOPSIS
			Returns information about the network connection of the target computer including NetBIOS name, IP Address, domain name and fully qualified domain name (FQDN).

		.DESCRIPTION
			Retrieves the IPAddress, ComputerName from one computer.
			The object can be used to take action against its name or IPAddress.

			First ICMP is used to test the connection, and get the connected IPAddress.

			Multiple protocols (e.g. WMI, CIM, etc) are attempted before giving up.

		.PARAMETER ComputerName
			The Server that you're connecting to.
			This can be the name of a computer, a SMO object, an IP address or a SQL Instance.

		.PARAMETER Credential
			Credential object used to connect to the SQL Server as a different user

		.PARAMETER Turbo
			Resolves without accessing the serer itself. Faster but may be less accurate.

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages.

		.NOTES
			Tags: Network, Resolve
			Original Author: Klaas Vandenberghe ( @PowerDBAKlaas )

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Resolve-DbaNetworkName

		.EXAMPLE
			Resolve-DbaNetworkName -ComputerName ServerA

			Returns a custom object displaying InputName, ComputerName, IPAddress, DNSHostName, Domain, FQDN for ServerA

		.EXAMPLE
			Resolve-DbaNetworkName -SqlInstance sql2016\sqlexpress

			Returns a custom object displaying InputName, ComputerName, IPAddress, DNSHostName, Domain, FQDN for the SQL instance sql2016\sqlexpress

		.EXAMPLE
			Resolve-DbaNetworkName -SqlInstance sql2016\sqlexpress, sql2014

			Returns a custom object displaying InputName, ComputerName, IPAddress, DNSHostName, Domain, FQDN for the SQL instance sql2016\sqlexpress and sql2014

			Get-SqlRegisteredServerName -SqlInstance sql2014 | Resolve-DbaNetworkName

			Returns a custom object displaying InputName, ComputerName, IPAddress, DNSHostName, Domain, FQDN for all SQL Servers returned by Get-SqlRegisteredServerName
	#>
	[CmdletBinding()]
	param (
		[parameter(ValueFromPipeline)]
		[Alias('cn', 'host', 'ServerInstance', 'Server', 'SqlInstance')]
		[DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
		[PSCredential] [System.Management.Automation.CredentialAttribute()]$Credential,
		[Alias('FastParrot')]
		[switch]$Turbo,
		[switch]$Silent
	)

	process {
		foreach ($Computer in $ComputerName) {
			$conn = $ipaddress = $null

			$OGComputer = $Computer

			if ($Computer -eq 'localhost' -or $Computer -eq '.') {
				$Computer = $env:COMPUTERNAME
			}

			if ($Turbo) {
				try {
					Write-Message -Level Verbose -Message "Resolving $Computer using .NET.Dns GetHostEntry"
					$ipaddress = ([System.Net.Dns]::GetHostEntry($Computer)).AddressList[0].IPAddressToString
					Write-Message -Level Verbose -Message "Resolving $ipaddress using .NET.Dns GetHostByAddress"
					$fqdn = [System.Net.Dns]::GetHostByAddress($ipaddress).HostName
				}
				catch {
					try {
						Write-Message -Level Verbose -Message "Resolving $Computer and IP using .NET.Dns GetHostEntry"
						$resolved = [System.Net.Dns]::GetHostEntry($Computer)
						$ipaddress = $resolved.AddressList[0].IPAddressToString
						$fqdn = $resolved.HostName
					}
					catch {
						Stop-Function -Message "DNS name not found" -Continue -InnerErrorRecord $_
					}
				}

				if ($fqdn -notmatch "\.") {
					$dnsdomain = $env:USERDNSDOMAIN.ToLower()
					$fqdn = "$fqdn.$dnsdomain"
				}

				$hostname = $fqdn.Split(".")[0]

				[PSCustomObject]@{
					InputName    = $OGComputer
					ComputerName = $hostname.ToUpper()
					IPAddress    = $ipaddress
					DNSHostname  = $hostname
					Domain       = $fqdn.Replace("$hostname.", "")
					DNSHostEntry = $fqdn
					FQDN         = $fqdn
				}
				return
			}

			Write-Message -Level Verbose -Message "Connecting to $Computer"

			try {
				$ipaddress = ((Test-Connection -ComputerName $Computer -Count 1 -ErrorAction Stop).Ipv4Address).IPAddressToString
			}
			catch {
								try {
										if ($env:USERDNSDOMAIN) {
												$ipaddress = ((Test-Connection -ComputerName "$Computer.$env:USERDNSDOMAIN" -Count 1 -ErrorAction SilentlyContinue).Ipv4Address).IPAddressToString
												$Computer = "$Computer.$env:USERDNSDOMAIN"
										}
								}
								catch {
										$Computer = $OGComputer
										$ipaddress = ([System.Net.Dns]::GetHostEntry($Computer)).AddressList[0].IPAddressToString
								}
			}

			if ($ipaddress) {
				Write-Message -Level Verbose -Message "IP Address from $Computer is $ipaddress"
			}
			else {
				Write-Message -Level Verbose -Message "No IP Address returned from $Computer"
				Write-Message -Level Verbose -Message "Using .NET.Dns to resolve IP Address"
				return (Resolve-DbaNetworkName -ComputerName $Computer -Turbo)
			}

			if ($PSVersionTable.PSVersion.Major -gt 2) {
                Write-Message -Level Verbose -Message "Your PowerShell Version is $($PSVersionTable.PSVersion.Major)"
				try {
					Write-Message -Level Verbose -Message "Getting computer information from $Computer"
					if (Was-Bound "Credential") {
						$conn = Get-DbaCmObject -ClassName win32_ComputerSystem -Computer $Computer -Credential $Credential -Silent
					}
					else {
						$conn = Get-DbaCmObject -ClassName win32_ComputerSystem -Computer $Computer -Silent
					}
				}
				catch {
					Write-Message -Level Verbose -Message "Unable to get computer information from $Computer"
				}

				if (!$conn) {
					Write-Message -Level Verbose -Message "No WMI/CIM from $Computer. Getting HostName via .NET.Dns"
					try {
						$fqdn = ([System.Net.Dns]::GetHostEntry($Computer)).HostName
						$hostname = $fqdn.Split(".")[0]

						$conn = [PSCustomObject]@{
							Name        = $Computer
							DNSHostname = $hostname
							Domain      = $fqdn.Replace("$hostname.", "")
						}
					}
					catch {
						Stop-Function -Message "No .NET.Dns information from $Computer" -InnerErrorRecord $_ -Continue
					}
				}
			}

			try {
				Write-Message -Level Verbose -Message "Resolving $($conn.DNSHostname) using .NET.Dns GetHostEntry"
				$hostentry = ([System.Net.Dns]::GetHostEntry($conn.DNSHostname)).HostName
			}
			catch {
				Stop-Function -Message ".NET.Dns GetHostEntry failed for $($conn.DNSHostname)" -InnerErrorRecord $_
			}

			$fqdn = "$($conn.DNSHostname).$($conn.Domain)"
			if ($fqdn -eq ".") {
				Write-Message -Level Verbose -Message "No full FQDN found. Setting to null"
				$fqdn = $null
			}

			[PSCustomObject]@{
				InputName    = $OGComputer
				ComputerName = $conn.Name
				IPAddress    = $ipaddress
				DNSHostName  = $conn.DNSHostname
				Domain       = $conn.Domain
				DNSHostEntry = $hostentry
				FQDN         = $fqdn
			}
		}
	}
}
