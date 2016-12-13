Function Resolve-DbaNetworkName
{
<#
.SYNOPSIS
Returns information about the network connection of the target computer including NetBIOS name, IP Address and domain name.

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

Returns a custom object displaying InputName, ComputerName, IPAddress, DNSHostName, Domain

#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("cn", "host", "ServerInstance", "SqlInstance","Server","SqlServer")]
		[object]$ComputerName,
		[PsCredential]$Credential
	)

    $conn = $ipaddress = $CIMsession = $null
	
    if ($ComputerName.GetType() -eq [Microsoft.SqlServer.Management.Smo.Server])
    {
        $ComputerName = $ComputerName.NetName
    }

    $ComputerName = $ComputerName.Split('\')[0]
    Write-Verbose "Connecting to server $ComputerName"
	$ipaddress = ((Test-Connection -ComputerName $ComputerName -Count 1 -ErrorAction SilentlyContinue).Ipv4Address).IPAddressToString

    if ( $ipaddress )
    {
        if ( $host.Version.Major -gt 2 )
        {
            Write-Verbose "Your PowerShell Version is $($host.Version.Major)"
            Write-Verbose "IP Address from $computername is $ipaddress"
            try
            {
                Write-Verbose "Getting computer information from server $ComputerName via CIM (WinRM)"
                $CIMsession = New-CimSession -ComputerName $ComputerName -ErrorAction SilentlyContinue -Credential $Credential
                $conn = Get-CimInstance -Query "Select Name, Caption, DNSHostName, Domain FROM Win32_computersystem" -CimSession $CIMsession
            }
            catch
            {
                Write-Warning "No WinRM connection to $computername"
            }
            if (!$conn)
            {
                try
                {
                    Write-Verbose "Getting computer information from server $ComputerName via CIM (DCOM)"
                    $sessionoption = New-CimSessionOption -Protocol DCOM
                    $CIMsession = New-CimSession -ComputerName $ComputerName -SessionOption $sessionoption -ErrorAction SilentlyContinue -Credential $Credential
                    $conn = Get-CimInstance -Query "Select Name, Caption, DNSHostName, Domain FROM Win32_computersystem" -CimSession $CIMsession
                }
                catch
                {
                    Write-Warning "No DCOM connection to $computername"
                }
            }
        }
        if (!$conn)
        {
            Write-Verbose "Getting computer information from server $ComputerName via WMI (DCOM)"
            $conn = Get-WmiObject -ComputerName $ComputerName -Query "Select Name, Caption, DNSHostName, Domain FROM Win32_computersystem" -ErrorAction SilentlyContinue -Credential $Credential
        }

        [PSCustomObject]@{
        InputName = $computername
        ComputerName = $conn.Name
        IPAddress = $ipaddress
        DNSHostName = $conn.DNSHostname
        Domain = $conn.Domain
        }
    }

    else
    {
        Write-Warning "Computer $computername not available"
    }
    
}