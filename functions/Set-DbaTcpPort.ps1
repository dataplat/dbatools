Function Set-DbaTcpPort
{
<#
.SYNOPSIS
Changes the TCP port used by the specified SQL Server.
	
.DESCRIPTION
This function changes the TCP port used by the specified SQL Server. 
		
.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user

.PARAMETER IPAddress
Wich IPAddress should the portchange , if omitted allip (0.0.0.0) will be changed with the new portnumber. 

.PARAMETER Port
TCPPort that SQLService should listen on.
	
Remote sqlwmi is used by default. 


.NOTES 
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Set-DbaTcpPort

.EXAMPLE
Set-DbaTcpPort -SqlServer sqlserver2014a -Port 1433

Sets the port number 1433 for allips on the default instance on sqlserver2014a

.EXAMPLE
Set-DbaTcpPort -SqlServer winserver\sqlexpress -IpAddress 192.168.1.22 -Port 1433

Sets the port number 1433 for IP 192.168.1.22 on the sqlexpress instance on sqlserver2014a	

.EXAMPLE
Set-DbaTcpPort -sqlserver 'SQLDB2014A' ,'SQLDB2016B' -port 1337

Sets the port number 1337 for ALLIP's on sqlserver SQLDB2016B and SQLDB2014A
#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[string[]]$SqlServer,
		[Alias("SqlCredential")]
		[PsCredential]$Credential,
		[parameter(Mandatory = $true)]
		[ValidateRange(1, 65535)]
		[int]$Port,
		[string[]]$IpAddress
	)
	BEGIN
	{
		$collection = New-Object System.Collections.ArrayList
		if ($Port -eq 0 )
		{
			throw 'Please specify a specific port using -Port'
		}

		if ($ipaddress.Length -eq 0)
		{
			$ipaddress = '0.0.0.0'
		}
        else
        {
            if ($SqlServer.count -gt 1)
            {
                throw '-IpAddress switch cannot be used with a collection of serveraddresses'
            }
        }
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
					throw 'SQL Server 2000 not supported.'
				}
				else
				{
					Write-Warning "SQL Server 2000 not supported. Skipping $servername."
					Continue
				}
			}

        			$instancename = $server.instanceName
				if ($instancename.length -eq 0)
				{
					$instancename = 'MSSQLSERVER'
				}
                if ($server.IsClustered)
                {
                    write-verbose "Instance is clustered fetching nodes..."
                    $clusterquery = "select nodename from sys.dm_os_cluster_nodes where not nodename = '$($server.ComputerNamePhysicalNetBIOS)'"
                    $clusterresult = $server.ConnectionContext.ExecuteWithResults("$clusterquery")	
                    foreach ($row in $clusterresult.tables[0].rows) {$ClusterNodes +=  $row.Item(0) + " "}
                    Write-Warning "$servername is a clustered instance, portchanges will be reflected on other nodes ( $clusternodes) after a failover..."
                }
                $scriptblock = {
				$servername = $args[0]
                $instancename = $args[1]
                $port = $args[2]						
                $ipaddress = $args[3]
				$wmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $servername
				$instance = $wmi.ServerInstances | Where-Object { $_.Name -eq $instancename }
				$tcp= $instance.ServerProtocols | Where-Object { $_.DisplayName -eq 'TCP/IP' }
				$ipaddress = $tcp.IPAddresses | where-object {$_.IPAddress -eq $ipaddress }
				$tcpport = $ipaddress.IPAddressProperties | Where-Object { $_.Name -eq 'TcpPort' }
                $tcpport.value = $port
				$tcp.Alter()
				}
				try
				{
				    write-verbose "Writing TCPPort $port for $servername\$instancename to $($server.ComputerNamePhysicalNetBIOS)..."
                    $setip = Invoke-ManagedComputerCommand -ComputerName $server.ComputerNamePhysicalNetBIOS -ScriptBlock $scriptblock -ArgumentList $servername, $instancename, $port, $ipaddress  
                    if ($ipaddress -eq '0.0.0.0') 
                    {
                        Write-Host "SQLSERVER: $servername\$instancename IPADDRESS: ALLIP's PORT: $port"
                    }
                    else
                    {
                        Write-Host "SQLSERVER: $servername\$instancename IPADDRESS: $ipaddress PORT: $port"
                    }
                }   
				catch
				{
					Write-Warning "Could not write new TCPPort for $servername"
                    Continue
				}
 		}
	}
	END
	{
	        return 
	}
}