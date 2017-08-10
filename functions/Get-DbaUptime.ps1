function Get-DbaUptime
{
<#
.SYNOPSIS
Returns the uptime of the SQL Server instance, and if required the hosting windows server
	
.DESCRIPTION
By default, this command returns for each SQL Server instance passed in:
SQL Instance last startup time, Uptime as a PS TimeSpan, Uptime as a formatted string
Hosting Windows server last startup time, Uptime as a PS TimeSpan, Uptime as a formatted string
	
.PARAMETER SqlInstance
The SQL Server that you're connecting to.

.PARAMETER SqlCredential
Credential object used to connect to the SQL Server as a different user

.PARAMETER WindowsCredential
Credential object used to connect to the SQL Server as a different user

.PARAMETER SqlOnly
Excludes the Windows server information

.PARAMETER WindowsOnly
Excludes the SQL server information

.PARAMETER Silent
Use this switch to disable any kind of verbose messages

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
Get-DbaUptime -SqlInstance SqlBox1\Instance2

Returns an object with SQL Server start time, uptime as TimeSpan object, uptime as a string, and Windows host boot time, host uptime as TimeSpan objects and host uptime as a string for the sqlexpress instance on winserver

.EXAMPLE
Get-DbaUptime -SqlInstance winserver\sqlexpress, sql2016

Returns an object with SQL Server start time, uptime as TimeSpan object, uptime as a string, and Windows host boot time, host uptime as TimeSpan objects and host uptime as a string for the sqlexpress instance on host winserver  and the default instance on host sql2016
	
.EXAMPLE   
Get-DbaUptime -SqlInstance sqlserver2014a, sql2016 -SqlOnly

Returns an object with SQL Server start time, uptime as TimeSpan object, uptime as a string for the sqlexpress instance on host winserver  and the default instance on host sql2016

.EXAMPLE   
Get-DbaRegisteredServerName -SqlInstance sql2014 | Get-DbaUptime 

Returns an object with SQL Server start time, uptime as TimeSpan object, uptime as a string, and Windows host boot time, host uptime as TimeSpan objects and host uptime as a string for every server listed in the Central Management Server on sql2014
	
#>
	[CmdletBinding(DefaultParameterSetName = "Default")]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer", "ComputerName")]
		[DbaInstanceParameter[]]$SqlInstance,
		[parameter(ParameterSetName = "Sql")]
		[Switch]$SqlOnly,
		[parameter(ParameterSetName = "Windows")]
		[Switch]$WindowsOnly,
		[Alias("Credential")]
		[PSCredential]$SqlCredential,
		[PSCredential]$WindowsCredential,
		[switch]$Silent
	)
	
	begin {
		$nowutc = (Get-Date).ToUniversalTime()
	}
	process
	{
		foreach ($instance in $SqlInstance)
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
				try {
					Write-Message -Level Verbose -Message "Connecting to $instance"
					$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
				}
				catch {
					Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
				}
				Write-Message -Level Verbose -Message "Getting Start times for $servername"
				#Get tempdb creation date
				$SQLStartTime = $server.Databases["tempdb"].CreateDate
				$SQLUptime = New-TimeSpan -Start $SQLStartTime.ToUniversalTime() -End $nowutc
				$SQLUptimeString = "{0} days {1} hours {2} minutes {3} seconds" -f $($SQLUptime.Days), $($SQLUptime.Hours), $($SQLUptime.Minutes), $($SQLUptime.Seconds)
			}
			
			if ($SqlOnly -ne $true)
			{
				$WindowsServerName = (Resolve-DbaNetworkName $servername -Credential $WindowsCredential).FullComputerName

				try
				{
					Write-Message -Level Verbose -Message "Getting WinBootTime via CimInstance for $servername"
					$WinBootTime = (Get-DbaOperatingSystem -ComputerName $windowsServerName -Credential $WindowsCredential -ErrorAction SilentlyContinue).LastBootUpTime
					$WindowsUptime = New-TimeSpan -start $WinBootTime.ToUniversalTime() -end $nowutc
					$WindowsUptimeString = "{0} days {1} hours {2} minutes {3} seconds" -f $($WindowsUptime.Days), $($WindowsUptime.Hours), $($WindowsUptime.Minutes), $($WindowsUptime.Seconds)
				}
				catch
				{
					try
					{
						Write-Message -Level Verbose -Message "Getting WinBootTime via CimInstance DCOM"
						$CimOption = New-CimSessionOption -Protocol DCOM
						$CimSession = New-CimSession -Credential:$WindowsCredential -ComputerName $WindowsServerName -SessionOption $CimOption
						$WinBootTime = ($CimSession | Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
						$WindowsUptime = New-TimeSpan -start $WinBootTime.ToUniversalTime() -end $nowutc
						$WindowsUptimeString = "{0} days {1} hours {2} minutes {3} seconds" -f $($WindowsUptime.Days), $($WindowsUptime.Hours), $($WindowsUptime.Minutes), $($WindowsUptime.Seconds)
					}
					catch
					{
						Stop-Function -Message "Failure getting WinBootTime" -ErrorRecord $_ -Target $instance -Continue
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
