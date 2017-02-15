function Get-DbaUptime
{
<#
.SYNOPSIS
Returns the uptime of the SQL Server instance, and if required the hosting windows server
	
.DESCRIPTION
By default, this command returns for each SQL Server instance passed in:
SQL Instance last startup time, Uptime as a PS TimeSpan, Uptime as a formatted string
Hosting Windows server last startup time, Uptime as a PS TimeSpan, Uptime as a formatted string
	
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
Original Author: Stuart Moore (@napalmgram), stuart-moore.com
	
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>

.LINK
https://dbatools.io/Get-DbaUptime

.EXAMPLE
Get-DbaUptime -SqlServer SqlBox1\Instance2

Returns an object with SQL Server start time, uptime as TimeSpan object, uptime as a string, and Windows host boot time, host uptime as TimeSpan objects and host uptime as a string for the sqlexpress instance on winserver

.EXAMPLE
Get-DbaUptime -SqlServer winserver\sqlexpress, sql2016

Returns an object with SQL Server start time, uptime as TimeSpan object, uptime as a string, and Windows host boot time, host uptime as TimeSpan objects and host uptime as a string for the sqlexpress instance on host winserver  and the default instance on host sql2016
	
.EXAMPLE   
Get-DbaUptime -SqlServer sqlserver2014a, sql2016 -SqlOnly

Returns an object with SQL Server start time, uptime as TimeSpan object, uptime as a string for the sqlexpress instance on host winserver  and the default instance on host sql2016

.EXAMPLE   
Get-SqlRegisteredServerName -SqlServer sql2014 | Get-DbaUptime 

Returns an object with SQL Server start time, uptime as TimeSpan object, uptime as a string, and Windows host boot time, host uptime as TimeSpan objects and host uptime as a string for every server listed in the Central Management Server on sql2014
	
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
				
				Write-Verbose "Connecting to $servername"
				try
				{
					$server = Connect-SqlServer -SqlServer $servername -SqlCredential $SqlCredential -ErrorVariable ConnectError
					
				}
				catch
				{
					Write-Warning $_
					continue
				}
								
				Write-Verbose "Getting Start times for $servername"
				#Get TempDB creation date
				$SQLStartTime = $server.Databases["TempDB"].CreateDate
				$SQLUptime = New-TimeSpan -Start $SQLStartTime -End (Get-Date)
				$SQLUptimeString = "{0} days {1} hours {2} minutes {3} seconds" -f $($SQLUptime.Days), $($SQLUptime.Hours), $($SQLUptime.Minutes), $($SQLUptime.Seconds)
			}
			
			if ($SqlOnly -ne $true)
			{
				$WindowsServerName = (Resolve-DbaNetworkName $servername -Credential $WindowsCredential).ComputerName

				try
				{
					Write-Verbose "Getting WinBootTime via CimInstance for $servername"
					$WinBootTime = (Get-CimInstance -ClassName win32_operatingsystem -ComputerName $windowsServerName -ErrorAction SilentlyContinue).lastbootuptime
					$WindowsUptime = New-TimeSpan -start $WinBootTime -end (get-date)
					$WindowsUptimeString = "{0} days {1} hours {2} minutes {3} seconds" -f $($WindowsUptime.Days), $($WindowsUptime.Hours), $($WindowsUptime.Minutes), $($WindowsUptime.Seconds)
					
				}
				catch
				{
					try
					{
						Write-Verbose "$functionname - Getting WinBootTime via CimInstance DCOM"
						$CimOption = New-CimSessionOption -Protocol DCOM
						$CimSession = New-CimSession -Credential:$WindowsCredential -ComputerName $WindowsServerName -SessionOption $CimOption
						$WinBootTime = ($CimSession | Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
						$WindowsUptime = New-TimeSpan -start $WinBootTime -end (get-date)
						$WindowsUptimeString = "{0} days {1} hours {2} minutes {3} seconds" -f $($WindowsUptime.Days), $($WindowsUptime.Hours), $($WindowsUptime.Minutes), $($WindowsUptime.Seconds)
						
					}
					catch
					{
						Write-Exception $_
					}
				}
				
				if ($null -eq $WinBootTime)
				{
					#Skip the windows results as they'll either be garbage or not there.
					$SqlOnly = $true
				}
			}
			
			if ($SqlOnly -eq $true)
			{
				[PSCustomObject]@{
					ComputerName = $server.NetName
					InstanceName = $server.ServiceName
					SqlServer = $server.Name
					SqlUptime = $SQLUptime
					SqlStartTime = $SQLStartTime
					SinceSqlStart = $SQLUptimeString
				}
			}
			elseif ($WindowsOnly -eq $true)
			{
				[PSCustomObject]@{
					ComputerName = $WindowsServerName
					WindowsUptime = $WindowsUptime
					WindowsBootTime = $WinBootTime
					SinceWindowsBoot = $WindowsUptimeString
				}
			}
			else
			{
				[PSCustomObject]@{
					ComputerName = $WindowsServerName
					InstanceName = $server.ServiceName
					SqlServer = $server.Name
					SqlUptime = $SQLUptime
					WindowsUptime = $WindowsUptime
					SqlStartTime = $SQLStartTime
					WindowsBootTime = $WinBootTime
					SinceSqlStart  = $SQLUptimeString
					SinceWindowsBoot = $WindowsUptimeString
				}
			}
		}
	}
}
