Function Get-DbaTcpPort
{
<#
.SYNOPSIS
Returns the TCP port used by the specified SQL Server.
	
.DESCRIPTION
By default, this command returns just the TCP port used by the specified SQL Server. 
	
If -Detailed is specified, server name, IPAddress (ipv4 and ipv6), port number and if the port assignment is static. 
	
.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user

.PARAMETER Detailed
Returns an object with server name, IPAddress (ipv4 and ipv6), port and static ($true/$false) for one or more SQL Servers.
	
Remote sqlwmi is used by default. If this doesn't work, then remoting is used. If neither work, it defaults to T-SQL which can provide only the port.

.PARAMETER NoIpv6
Excludes IPv6 information when -Detailed is specified.

.NOTES 
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Get-DbaTcpPort

.EXAMPLE
Get-DbaTcpPort -SqlServer sqlserver2014a

Returns just the port number for the default instance on sqlserver2014a

.EXAMPLE
Get-DbaTcpPort -SqlServer winserver\sqlexpress, sql2016

Returns an object with server name and port number for the sqlexpress on winserver and the default instance on sql2016
	
.EXAMPLE   
Get-DbaTcpPort -SqlServer sqlserver2014a, sql2016 -Detailed

Returns an object with server name, IPAddress (ipv4 and ipv6), port and static ($true/$false) for sqlserver2014a and sql2016
	
Remote sqlwmi is used by default. If this doesn't work, then remoting is used. If neither work, it defaults to T-SQL which can provide only the port.

.EXAMPLE   
Get-SqlRegisteredServerName -SqlServer sql2014 | Get-DbaTcpPort -NoIpV6 -Detailed -Verbose

Returns an object with server name, IPAddress (just ipv4), port and static ($true/$false) for every server listed in the Central Management Server on sql2014
	
#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[string[]]$SqlServer,
		[Alias("SqlCredential")]
		[PsCredential]$Credential,
		[switch]$Detailed,
		[Alias("Ipv4")]
		[switch]$NoIpv6
	)
	
	BEGIN
	{
		$collection = New-Object System.Collections.ArrayList
	}
	
	PROCESS
	{
		$servercount = ++$i
		foreach ($servername in $SqlServer)
		{
			try
			{
				$server = Connect-SqlServer -SqlServer "TCP:$servername" -SqlCredential $Credential
			}
			catch
			{
				if ($servercount -eq 1)
				{
					throw $_
				}
				else
				{
					Write-Warning "Can't connect to $servername. Moving on."
					Continue
				}
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
			
			if ($detailed -eq $true)
			{
				
				$instancename = $server.instanceName
				
				if ($instancename.length -eq 0)
				{
					$instancename = 'MSSQLSERVER'
				}
				
				try
				{
					$scriptblock = {
						$servername = $args[0]
						$instancename = $args[1]
						$allips = @()
						Add-Type -Assembly Microsoft.VisualBasic
						$wmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $servername
						$instance = $wmi.ServerInstances | Where-Object { $_.Name -eq $instancename }
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
							
							$allips += [PsCustomObject]@{
								Server = $servername
								IPAddress = $ip.Ipaddress.IPAddressToString
								Port = $port
								Static = $static
							}
						}
						return $allips
					}
					
					$allips = Invoke-ManagedComputerCommand -ComputerName $server.ComputerNamePhysicalNetBIOS -ArgumentList $servername, $instancename -ScriptBlock $scriptblock
				}
				catch
				{
					Write-Warning "Could not get detailed information for $servername"
				}
				
				$cleanedup = $allips | Sort-Object IPAddress | Select-Object Server, IPAddress, Port, Static
				
				if ($NoIpv6)
				{
					$octet = '(?:0?0?[0-9]|0?[1-9][0-9]|1[0-9]{2}|2[0-5][0-5]|2[0-4][0-9])'
					[regex]$ipv4 = "^(?:$octet\.){3}$octet$"
					$cleanedup = $cleanedup | Where-Object { $_.IPAddress -match $ipv4 }
				}
				
				if ($cleanedup.count -gt 0)
				{
					$null = $collection.Add($cleanedup)
				}
			}
			
			if ($Detailed -eq $false -or ($Detailed -eq $true -and $allips -eq $null))
			{
				# WmiComputer can be unreliable :( Use T-SQL
				$sql = "SELECT local_tcp_port FROM sys.dm_exec_connections WHERE session_id = @@SPID"
				$port = $server.ConnectionContext.ExecuteScalar($sql)
				
				$null = $collection.Add([PSCustomObject]@{
						Server = $servername
						Port = $port
					})
			}
		}
	}
	
	END
	{
		if ($Detailed -eq $true)
		{
			return $collection
		}
		
		if ($collection.count -eq 1)
		{
			return $collection.Port
		}
		else
		{
			return $collection
		}
	}
}