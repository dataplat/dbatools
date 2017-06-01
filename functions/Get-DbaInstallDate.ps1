function Get-DbaInstallDate
{
<#
.SYNOPSIS
Returns the install date of SqlServer and Windows Server, depending on what is passed. 
	
.DESCRIPTION
By default, this command returns for each SQL Server instance passed in:
SQL Instance install date, formatted as a string
Hosting Windows server install date, formatted as a string
	
.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER SqlCredential
Credential object used to connect to the SQL Server as a different user

.PARAMETER WindowsCredential
Credential object used to connect to the SQL Server as a different user

.PARAMETER SqlOnly
Excludes the Windows server information

.PARAMETER WindowsOnly
Excludes the SQL server information

.NOTES
Tags: CIM 
Original Author: Mitchell Hamann (@SirCaptainMitch), mitchellhamann.com
	
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>

.LINK
https://dbatools.io/Get-DbaInstallDate

.EXAMPLE
Get-DbaInstallDate -SqlServer SqlBox1\Instance2

Returns an object with SQL Server Install date as a string and the Windows install date as string. 

.EXAMPLE
Get-DbaInstallDate -SqlServer winserver\sqlexpress, sql2016

Returns an object with SQL Server Install date as a string and the Windows install date as a string for both SQLInstances that are passed to the cmdlet.  
	
.EXAMPLE   
Get-DbaInstallDate -SqlServer sqlserver2014a, sql2016 -SqlOnly

Returns an object with only the SQL Server Install date as a string. 

.EXAMPLE   
Get-DbaInstallDate -SqlServer sqlserver2014a, sql2016 -WindowsOnly

Returns an object with only the Windows Install date as a string. 

.EXAMPLE   
Get-SqlRegisteredServerName -SqlServer sql2014 | Get-DbaInstallDate

Returns an object with SQL Server Install date as a string and the Windows install date as string for every server listed in the Central Management Server on sql2014
	
#>
	[CmdletBinding(DefaultParameterSetName = "Default")]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance", "ComputerName")]
		[object[]]$SqlServer,
		[parameter(ParameterSetName = "Sql")]
		[Switch]$SqlOnly,
		[parameter(ParameterSetName = "Windows")]
		[Switch]$WindowsOnly,
		[Alias("Credential")]
		[PsCredential]$SqlCredential,
		[PsCredential]$WindowsCredential
	)
	
	PROCESS
	{
		foreach ($instance in $SqlServer)
		{
			if ($instance.Gettype().FullName -eq [System.Management.Automation.PSCustomObject] )
			{
				$servername = $instance.SqlInstance
			}
			elseif ($instance.Gettype().FullName -eq [Microsoft.SqlServer.Management.Smo.Server])
			{
				$servername = $instance.NetName
			}
			else
			{
				$servername = $instance
			}
						
			if ($WindowsOnly -ne $true)
			{ 
				try 
				{
					Write-Message -Level Verbose -Message "Connecting to $instance" -Silent $false 
                    if ($SqlCredential)
                    { 
                        $server = Connect-SqlInstance -SqlInstance $servername -SqlCredential $SqlCredential #-ErrorVariable ConnectError
                    } else 
                    { 
                        $server = Connect-SqlInstance -SqlInstance $servername 
                    }					
				}
				catch 
				{
					Stop-Function -Message "Failed to connect to: $instance" -Continue -Target $instance					
				}

				if ( $server.VersionMajor -ge 9 )
				{ 
					Write-Message -Level Verbose -Message "Getting Install Date for: $instance" -Silent $false 
					$sql = "SELECT create_date FROM sys.server_principals WHERE sid = 0x010100000000000512000000"
					$sqlInstallDate = $server.databases['master'].ExecuteWithResults($sql).tables
					$sqlInstallDate = ($sqlInstallDate.rows).create_date.toString('MM-dd-yyyy') 

				} else { 
					Write-Message -Level Verbose -Message "Getting Install Date for: $instance" -Silent $false 
					$sql = "SELECT schemadate FROM sysservers"
					$sqlInstallDate = $server.databases['master'].ExecuteWithResults($sql).tables					
					$sqlInstallDate = ($sqlInstallDate.rows).create_date.toString('MM-dd-yyyy') 
				}											

			} 

			if ($SqlOnly -ne $true)			
			{ 
				Write-Message -Level Verbose -Message "Getting Windows Server Name for: $servername" -Silent $false 
				$WindowsServerName = (Resolve-DbaNetworkName $servername -Credential $WindowsCredential).ComputerName
				
				try
				{
					Write-Message -Level Verbose -Message "Getting Windows Install date via CIM for: $WindowsServerName" -Silent $false 
					$windowsInstallDate = (Get-CimInstance -ClassName win32_operatingsystem -ComputerName $windowsServerName -ErrorAction SilentlyContinue).InstallDate	
					$windowsInstallDate = $windowsInstallDate.toString('MM-dd-yyyy')				
				}
				catch
				{
					try
					{	
						Write-Message -Level Verbose -Message "Getting Windows Install date via DCOM for: $WindowsServerName" -Silent $false 
						$CimOption = New-CimSessionOption -Protocol DCOM
						$CimSession = New-CimSession -Credential:$WindowsCredential -ComputerName $WindowsServerName -SessionOption $CimOption
						$windowsInstallDate = ($CimSession | Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime

						$windowsInstallDate = $windowsInstallDate.toString('MM-dd-yyyy')						
					}
					catch
					{
						Stop-Function -Message "Failed to connect to: $WindowsServerName" -Continue -Target $instance						
					}
				}
			}

			if ($sqlOnly -eq $true)
			{ 
				[PSCustomObject]@{
					ComputerName = $server.NetName
					InstanceName = $server.ServiceName
					SqlServer = $server.Name
					SqlInstallDate = $sqlInstallDate
				}

			} elseif ($WindowsOnly -eq $true)
			{ 
				[PSCustomObject]@{
					ComputerName = $WindowsServerName										
					WindowsInstallDate = $windowsInstallDate
				}
			} else 
			{ 
				[PSCustomObject]@{
					ComputerName = $server.NetName
					InstanceName = $server.ServiceName
					SqlServer = $server.InstanceName
					SqlInstallDate = $sqlInstallDate
					WindowsInstallDate = $windowsInstallDate
				}
			}

        } 
    }
}