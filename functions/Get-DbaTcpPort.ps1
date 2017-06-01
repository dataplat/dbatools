Function Get-DbaTcpPort
{
<#
.SYNOPSIS
Returns the TCP port used by the specified SQL Server.
	
.DESCRIPTION
By default, this command returns just the TCP port used by the specified SQL Server. 
	
If -Detailed is specified, server name, IPAddress (ipv4 and ipv6), port number and if the port assignment is static. 
	
.PARAMETER SqlInstance
The SQL Server that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user

.PARAMETER Detailed
Returns an object with server name, IPAddress (ipv4 and ipv6), port and static ($true/$false) for one or more SQL Servers.
	
Remote sqlwmi is used by default. If this doesn't work, then remoting is used. If neither work, it defaults to T-SQL which can provide only the port.

.PARAMETER NoIpv6
Excludes IPv6 information when -Detailed is specified.

.NOTES
Tags: SQLWMI
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Get-DbaTcpPort

.EXAMPLE
Get-DbaTcpPort -SqlInstance sqlserver2014a

Returns just the port number for the default instance on sqlserver2014a

.EXAMPLE
Get-DbaTcpPort -SqlInstance winserver\sqlexpress, sql2016

Returns an object with server name and port number for the sqlexpress on winserver and the default instance on sql2016
	
.EXAMPLE   
Get-DbaTcpPort -SqlInstance sqlserver2014a, sql2016 -Detailed

Returns an object with server name, IPAddress (ipv4 and ipv6), port and static ($true/$false) for sqlserver2014a and sql2016
	
Remote sqlwmi is used by default. If this doesn't work, then remoting is used. If neither work, it defaults to T-SQL which can provide only the port.

.EXAMPLE   
Get-SqlRegisteredServerName -SqlInstance sql2014 | Get-DbaTcpPort -NoIpV6 -Detailed -Verbose

Returns an object with server name, IPAddress (just ipv4), port and static ($true/$false) for every server listed in the Central Management Server on sql2014
	
#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[Alias("SqlCredential")]
		[PsCredential]$Credential,
		[switch]$Detailed,
		[Alias("Ipv4")]
		[switch]$NoIpv6
	)
	
	PROCESS
	{
		foreach ($servername in $SqlInstance)
		{
			if ($detailed -eq $true)
			{
				try
				{
					$scriptblock = {
						$servername = $args[0]
						
						Add-Type -AssemblyName Microsoft.VisualBasic
						$wmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $servername
						
						foreach ($instance in $wmi.ServerInstances)
						{
							$allips = @()
							$instancename = $instance.name
							
							$tcp = $instance.ServerProtocols | Where-Object { $_.DisplayName -eq "TCP/IP" }
							$ips = $tcp.IPAddresses
							
							Write-Verbose "Parsing information for $($ips.count) IP addresses"
							foreach ($ip in $ips)
							{
								$props = $ip.IPAddressProperties | Where-Object { $_.Name -eq "TcpPort" -or $_.Name -eq "TcpDynamicPorts" }
								
								foreach ($prop in $props)
								{
									if ([Microsoft.VisualBasic.Information]::IsNumeric($prop.value))
									{
										$port = $prop.value
										if ($prop.name -eq 'TcpPort')
										{
											$static = $true
										}
										else
										{
											$static = $false
										}
										break
									}
								}
								
								[PsCustomObject]@{
									ComputerName = $servername
									InstanceName = $instancename
									IPAddress = $ip.Ipaddress.IPAddressToString
									Port = $port
									Static = $static
								}
							}
						}
					}
					
					$resolved = Resolve-DbaNetworkName -ComputerName $servername -Verbose:$false
					$fqdn = $resolved.FQDN
					$computername = $resolved.ComputerName
					try
					{
						Write-Verbose "Trying with ComputerName ($computername)"
						$someips = Invoke-ManagedComputerCommand -ComputerName $computername -ArgumentList $computername -ScriptBlock $scriptblock
					}
					catch
					{
						Write-Verbose "Trying with FQDN because ComputerName failed"
						$someips = Invoke-ManagedComputerCommand -ComputerName $fqdn -ArgumentList $fqdn -ScriptBlock $scriptblock
					}
				}
				catch
				{
					Write-Warning "Could not get detailed information for $servername"
					Write-Warning $_.Exception.Message
				}
				
				$cleanedup = $someips | Sort-Object IPAddress
				
				if ($NoIpv6)
				{
					$octet = '(?:0?0?[0-9]|0?[1-9][0-9]|1[0-9]{2}|2[0-5][0-5]|2[0-4][0-9])'
					[regex]$ipv4 = "^(?:$octet\.){3}$octet$"
					$cleanedup = $cleanedup | Where-Object { $_.IPAddress -match $ipv4 }
				}
				
				$cleanedup
			}
			
			if ($Detailed -eq $false -or ($Detailed -eq $true -and $someips -eq $null))
			{
				try
				{
					$server = Connect-SqlInstance -SqlInstance $servername -SqlCredential $Credential
				}
				catch
				{
					Write-Warning "Can't connect to $servername. Moving on."
					Continue
				}
				
				if ($server.VersionMajor -lt 9)
				{
					if ($servercount -eq 1)
					{
						throw "SQL Server 2000 not supported."
					}
					else
					{
						Write-Warning "SQL Server 2000 not supported. Skipping $servername."
						Continue
					}
				}
				
				# WmiComputer can be unreliable :( Use T-SQL
				$sql = "SELECT local_tcp_port FROM sys.dm_exec_connections WHERE session_id = @@SPID"
				$port = $server.ConnectionContext.ExecuteScalar($sql)
				
				[PSCustomObject]@{
					Server = $servername
					Port = $port
				}
			}
		}
	}
}
