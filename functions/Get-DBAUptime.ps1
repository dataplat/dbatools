function Get-DbaUptime {
<#
.SYNOPSIS
Returns the uptime of the SQL Server instance, and if required the hosting windows server
	
.DESCRIPTION
By default, this command returns for each SQL Server instance passed in:
SQL Instance last startup time, Uptime as a PS TimeSpan, Uptime as a formatted string
Hosting Windows server last startup time, Uptime as a PS TimeSpan, Uptime as a formatted string
	
.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER SQLCredential
Credential object used to connect to the SQL Server as a different user

.PARAMETER WindowsCredential
Credential object used to connect to the SQL Server as a different user

.PARAMETER SQLOnly
Excludes the windows server information

.NOTES 
Original Author: Stuart Moore (@napalmgram), stuart-moore.com
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>

.LINK
https://dbatools.io/Get-DBAUptime

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
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[string[]]$SqlServer,
		[Alias("SqlCredential")]
		[PsCredential]$Credential,
		[PsCredential]$WindowsCredential,
		[Switch]$SQLOnly

	)

    	BEGIN
	{
        $functionname = "Get-DBAUptime"
		$collection = New-Object System.Collections.ArrayList
	}
    	PROCESS
	{
		foreach ($servername in $SqlServer)
		{
            write-verbose "$functionname - server = $servername"
		Write-Verbose "Connecting to $SqlServer"
		try
		{
			$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $Credential -ErrorVariable ConnectError
			
		}
		catch
		{
			Write-Warning $_
			continue
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
                #Get TempDB creation date
                $SQLStartTime = $server.Databases["TempDB"].CreateDate
                $SQLUptime = New-TimeSpan  -start $SQLStartTime -end  (get-date)
				$SQLUptimeString =  "{0} days {1} hours {2} minutes {3} seconds" -f $($SQLUptime.Days), $($SQLUptime.Hours), $($SQLUptime.Minutes), $($SQLUptime.Seconds)


				if ($SQLOnly -ne $true)
				{
					$ClusterCheck = Get-DbaClusterActiveNode -SqlServer $servername
					if ($ClusterCheck -eq 'Not a clustered instance' )
					{
						$WindowsServerName = ($servername.split("\"))[0]
					}
					else
					{
						$WindowsServerName = $ClusterCheck
					}
					$CimError = 0
					try {
						Write-Verbose "$functionname - Getting WinBootTime via CimInstance"
						$WinBootTime = (Get-CimInstance -ClassName win32_operatingsystem -ComputerName $windowsServerName).lastbootuptime
						$WindowsUptime = New-TimeSpan -start $WinBootTime -end (get-date)
						$WindowsUptimeString = "{0} days {1} hours {2} minutes {3} seconds" -f $($WindowsUptime.Days), $($WindowsUptime.Hours), $($WindowsUptime.Minutes), $($WindowsUptime.Seconds)
						
					}
					catch [System.Exception] {
						Write-Exception $_
						$CimError += 1

					}
					if ($CimError -gt 0)
					{
						try {
							Write-Verbose "$functionname - Getting WinBootTime via CimInstance DCOM"
							$CimOption = New-CimSessionOption -Protocol DCOM
							$CimSession = New-CimSession -Credential:$WindowsCredential -ComputerName $WindowsServerName -SessionOption $CimOption
							$WinBootTime = ($CimSession | Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
							$WindowsUptime = New-TimeSpan -start $WinBootTime -end (get-date)
							$WindowsUptimeString = "{0} days {1} hours {2} minutes {3} seconds" -f $($WindowsUptime.Days), $($WindowsUptime.Hours), $($WindowsUptime.Minutes), $($WindowsUptime.Seconds)

						}
						catch [System.Exception] {
							Write-Exception $_
							$CimError += 1
						}
					}
					if ($WindowsUptimeString -eq '')
					{
						#Skip the windows results as they'll either be garbage or not there.
						$SqlOnly = $true
					}
				}
				if ($SQLOnly -eq $true)
				{
					$null = $collection.Add([PSCustomObject]@{
							SQLServer = $servername
							SQLStartTime = $SQLStartTime
							SQLUptimeString = $SQLUptimeString
							SQLUptime = $SQLUptime
					})
				}else{
					[PSCustomObject]@{
							SQLServer = $server.Name
							InstanceName = $server.ServiceName
							ComputerName = $server.NetName
							SQLStartTime = $SQLStartTime
							SQLUptimeString = $SQLUptimeString
							SQLUptime = $SQLUptime
							WindowsBootTime = $WinBootTime
							WindowsUptime = $WindowsUptime
							WindowsUptimeString = $WindowsUptimeString
					}
				}

        }
    }
    END 
    {
            return 
    }
}
