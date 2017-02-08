Function Resolve-DbaNetworkName
{
<#
.SYNOPSIS
Returns information about the network connection of the target computer including NetBIOS name, IP Address, domain name and fully qualified domain name (FQDN).

.DESCRIPTION
Retrieves the IPAddress, ComputerName from one computer.
The object can be used to take action against its name or IPAddress.

First ICMP is used to test the connection, and get the connected IPAddress.

If your local Powershell version is not higher than 2, WMI is tried to get the computername.
If not, CIM is used, first via WinRM, and if not successful, via DCOM.

.PARAMETER ComputerName
The Server that you're connecting to.
This can be the name of a computer, a SMO object, an IP address or a SQL Instance.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user

.PARAMETER Turbo
Resolves without accessing the serer itself. Faster but may be less accurate.

.NOTES
Author: Klaas Vandenberghe ( @PowerDBAKlaas )

dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

.LINK
 https://dbatools.io/Resolve-DbaNetworkName

.EXAMPLE
Resolve-DbaNetworkName -ComputerName ServerA

Returns a custom object displaying InputName, ComputerName, IPAddress, DNSHostName, Domain, FQDN for ServerA
	
.EXAMPLE
Resolve-DbaNetworkName -SqlServer sql2016\sqlexpress

Returns a custom object displaying InputName, ComputerName, IPAddress, DNSHostName, Domain, FQDN for the SQL instance sql2016\sqlexpress
	
.EXAMPLE
Resolve-DbaNetworkName -SqlServer sql2016\sqlexpress, sql2014

Returns a custom object displaying InputName, ComputerName, IPAddress, DNSHostName, Domain, FQDN for the SQL instance sql2016\sqlexpress and sql2014

Get-SqlRegisteredServerName -SqlServer sql2014 | Resolve-DbaNetworkName
	
Returns a custom object displaying InputName, ComputerName, IPAddress, DNSHostName, Domain, FQDN for all SQL Servers returned by Get-SqlRegisteredServerName
#>
	[CmdletBinding()]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("cn", "host", "ServerInstance", "Server", "SqlServer")]
		[object]$ComputerName,
		[PsCredential]$Credential,
		[Alias("FastParrot")]
		[switch]$Turbo
	)
	
	PROCESS
	{
		foreach ( $Computer in $ComputerName )
		{
			$conn = $ipaddress = $CIMsession = $null
			
			if ( $Computer.GetType() -eq [Microsoft.SqlServer.Management.Smo.Server] )
			{
				$Computer = $Computer.NetName
			}
			
			$OGComputer = $Computer
			
			if ($Computer -eq "localhost" -or $Computer -eq ".")
			{
				$Computer = $env:COMPUTERNAME
			}
			
			$Computer = $Computer.Split('\')[0]
			Write-Verbose "Connecting to server $Computer"
			
			try
			{
				$ipaddress = ((Test-Connection -ComputerName $Computer -Count 1 -ErrorAction Stop).Ipv4Address).IPAddressToString
			}
			catch
			{
				try
				{
					$ipaddress = ((Test-Connection -ComputerName "$Computer.$env:USERDNSDOMAIN" -Count 1 -ErrorAction SilentlyContinue).Ipv4Address).IPAddressToString
					$Computer = "$Computer.$env:USERDNSDOMAIN"
				}
				catch
				{
					$Computer = $OGComputer
				}
			}
			
			if ($Turbo)
			{
				try
				{
					$fqdn = [System.Net.Dns]::GetHostByAddress($ipaddress).HostName
				}
				catch
				{
					try
					{
						$fqdn = ([System.Net.Dns]::GetHostEntry($Computer)).HostName
					}
					catch
					{
						throw "DNS name does not exist"
					}
				}
				
				if ($fqdn -notmatch "\.")
				{
					$dnsdomain = $env:USERDNSDOMAIN.ToLower()
					$fqdn = "$fqdn.$dnsdomain"
				}
				
				$hostname = $fqdn.Split(".")[0]
				
				[PSCustomObject]@{
					InputName = $OGComputer
					ComputerName = $hostname.ToUpper()
					DNSHostname = $hostname
					IPAddress = $ipaddress
					Domain = $fqdn.Replace("$hostname.", "")
					FQDN = $fqdn
				}
				return
			}
			
			if ( $ipaddress )
			{
			    Write-Verbose "IP Address from $Computer is $ipaddress"
			}
			else
			{
				Write-Warning "No IP Address returned from Computer $Computer"
			}
			if ( $host.Version.Major -gt 2 )
			{
				Write-Verbose "Your PowerShell Version is $($host.Version.Major)"
				try
				{
					Write-Verbose "Getting computer information from server $Computer via CIM (WSMan)"
					if ($Credential)
					{
						$CIMsession = New-CimSession -ComputerName $Computer -ErrorAction SilentlyContinue -Credential $Credential
					}
					else
					{
						$CIMsession = New-CimSession -ComputerName $Computer -ErrorAction SilentlyContinue
					}
					
					$conn = Get-CimInstance -Query "Select Name, Caption, DNSHostName, Domain FROM Win32_computersystem" -CimSession $CIMsession
				}
				catch
				{
					Write-Verbose "No WSMan connection to $Computer"
				}
				if ( !$conn )
				{
					try
					{
						Write-Verbose "Getting computer information from server $Computer via CIM (DCOM)"
						$sessionoption = New-CimSessionOption -Protocol DCOM
						if ($Credential)
						{
							$CIMsession = New-CimSession -ComputerName $Computer -SessionOption $sessionoption -ErrorAction SilentlyContinue -Credential $Credential
							
						}
						else
						{
							$CIMsession = New-CimSession -ComputerName $Computer -SessionOption $sessionoption -ErrorAction SilentlyContinue
						}
						
						$conn = Get-CimInstance -Query "Select Name, Caption, DNSHostName, Domain FROM Win32_computersystem" -CimSession $CIMsession
					}
					catch
					{
						Write-Warning "No DCOM connection for CIM to $Computer"
					}
				}
			    if ( !$conn )
			    {
				    Write-Verbose "Getting computer information from server $Computer via WMI (DCOM)"
					
					if ($Credential)
					{
						$conn = Get-WmiObject -ComputerName $Computer -Query "Select Name, Caption, DNSHostName, Domain FROM Win32_computersystem" -ErrorAction SilentlyContinue -Credential $Credential
					}
					else
					{
						$conn = Get-WmiObject -ComputerName $Computer -Query "Select Name, Caption, DNSHostName, Domain FROM Win32_computersystem" -ErrorAction SilentlyContinue
					}
				}
				
				if (!$conn)
				{
					Write-Verbose "Cim and Wmi both failed. Defaulting to .NET"
					try
					{
						$fqdn = ([System.Net.Dns]::GetHostEntry($Computer)).HostName
						$hostname = $fqdn.Split(".")[0]
						
						$conn = [PSCustomObject]@{
							Name = $Computer
							DNSHostname = $hostname
							Domain = $fqdn.Replace("$hostname.", "")
						}
					}
					catch
					{
						# ouch, no dice
					}
				}
			}
			
			
			try
			{
				Write-Verbose "Resolving $($conn.DNSHostname) using GetHostEntry"
				$hostentry = ([System.Net.Dns]::GetHostEntry($conn.DNSHostname)).HostName
			}
			catch
			{
				Write-Verbose "GetHostEntry failed"
			}
			
			$fqdn = "$($conn.DNSHostname).$($conn.Domain)"
			if ($fqdn -eq ".")
			{
				Write-Verbose "No full FQDN found. Setting to null"
				$fqdn = $null
			}
			
			[PSCustomObject]@{
				InputName = $OGComputer
				ComputerName = $conn.Name
				IPAddress = $ipaddress
				DNSHostName = $conn.DNSHostname
				Domain = $conn.Domain
				DNSHostEntry = $hostentry
				FQDN = $fqdn
			}
		}
	}
}
