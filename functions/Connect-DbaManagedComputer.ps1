Function Connect-DbaManagedComputer
{
<#
.SYNOPSIS
Makes Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer more accessible.
	
.DESCRIPTION
ManagedComputer is basically .NET's interface to SQL Server Configuration Manager.
	
.PARAMETER Server
The SQL Server that you're connecting to. 
	
It can be the computer name, an SMO Computer object, or a sql server name, including the instance name. All of these formats are handled.

.PARAMETER Credential
Windows credential object used to connect to the server

.NOTES 
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Connect-DbaManagedComputer

.EXAMPLE
Connect-DbaManagedComputer -Server sqlserver2014a

Resolves sqlserver2014a to an IP address, connects to it via SMO WMI and returnsthe Smo.Wmi.ManagedComputer object.

.EXAMPLE
Connect-DbaManagedComputer -Server winserver\sqlexpress 

Resolves winserver to an IP address, connects to it via SMO WMI and returnsthe Smo.Wmi.ManagedComputer object.

.EXAMPLE
$credential = Get-Credential
Connect-DbaManagedComputer -Server winserver\sqlexpress -Credential $credential
	
Prompts for a Windows credential then connects to the Server instance with the Windows credential
	
#>	
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Server,
		[System.Management.Automation.PSCredential]$Credential
	)
	
	if ($server.GetType() -eq [Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer])
	{
		$null = $server.Initialize()
		return $server
	}
	
	if ($Server.GetType() -eq [Microsoft.SqlServer.Management.Smo.Server])
	{
		$server = $server.ComputerNamePhysicalNetBIOS
	}
	
	# Remove instance name if it as passed
	$server = ($Server.Split("\"))[0]
	$ipaddr = (Test-Connection $server -count 1 -ErrorAction Stop).Ipv4Address
	
	try
	{
		if ($credential.username -ne $null)
		{
			$username = ($Credential.username).TrimStart("\")
			$server = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $ipaddr, $username, ($Credential).GetNetworkCredential().Password
		}
		else
		{
			$server = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $ipaddr
		}
		$null = $server.Initialize()
	}
	catch
	{
		<# 	
			Wmi doesn't always work remotely, so I tried to return an object from Invoke-Command but it didn't work well at all.
		   	Maybe something with $session could work. Here was my code.
			
			$server = [System.Net.Dns]::gethostentry($ipaddr)
				$Server = Invoke-Command -ComputerName $server.hostname -ScriptBlock {
					$null = [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SqlWmiManagement')
					return (New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $env:COMPUTERNAME)
				}
		#>
		Write-Exception $_
		throw $_
	}
	
	return $server
}