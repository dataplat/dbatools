Function Set-DbaPowerPlan
{
<#
.SYNOPSIS
Sets the SQL Server OS's Power Plan. 
	
.DESCRIPTION
Sets the SQL Server OS's Power Plan. It defaults to High Performance which is Best Practice.
	
If your organization uses a custom power plan that is considered best practice, specify -CustomPowerPlan.
	
References:
https://support.microsoft.com/en-us/kb/2207548
http://www.sqlskills.com/blogs/glenn/windows-power-plan-effects-on-newer-intel-processors/
	
.PARAMETER ComputerName
The SQL Server (or server in general) that you're connecting to. The -SqlServer parameter also works. This command handles named instances.
	
.PARAMETER PowerPlan
The Power Plan that you wish to use. These are validated to Windows default Power Plans (Power saver, Balanced, High Performance)
	
.PARAMETER CustomPowerPlan
If you use a custom power plan instead of Windows default, use CustomPowerPlan

.NOTES 
Requires: WMI access to servers
	
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Set-DbaPowerPlan

.EXAMPLE
Set-DbaPowerPlan -ComputerName sqlserver2014a

Sets the Power Plan to High Performance. Skips it if its already set.
	
.EXAMPLE   
Set-DbaPowerPlan -ComputerName sqlcluster -CustomPowerPlan 'Maximum Performance'
	
Sets the Power Plan to the custom power plan called "Maximum Performance". Skips it if its already set.
	
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance", "SqlServer")]
		[string[]]$ComputerName,
		[ValidateSet('High Performance', 'Balanced', 'Power saver')]
		[string]$PowerPlan = 'High Performance',
		[string]$CustomPowerPlan
	)
	
	BEGIN
	{
		if ($CustomPowerPlan.Length -gt 0) { $PowerPlan = $CustomPowerPlan }
		
		Function Set-DbaPowerPlan
		{
			try
			{
				Write-Verbose "Testing connection to $server and resolving IP address"
				$ipaddr = (Test-Connection $server -Count 1 -ErrorAction SilentlyContinue).Ipv4Address | Select-Object -First 1
				
			}
			catch
			{
				Write-Warning "Can't connect to $server"
				return
			}
			
			try
			{
				Write-Verbose "Getting Power Plan information from $server"
				$query = "Select ElementName from Win32_PowerPlan WHERE IsActive = 'true'"
				$currentplan = Get-WmiObject -Namespace Root\CIMV2\Power -ComputerName $ipaddr -Query $query -ErrorAction SilentlyContinue
				$currentplan = $currentplan.ElementName
			}
			catch
			{
				Write-Warning "Can't connect to WMI on $server"
				return
			}
			
			if ($currentplan -eq $null)
			{
				# the try/catch above isn't working, so make it silent and handle it here.
				Write-Warning "Cannot get Power Plan for $server"
				return
			}
			
			$planinfo = [PSCustomObject]@{
				Server = $server
				PreviousPowerPlan = $currentplan
				ActivePowerPlan = $PowerPlan
			}
			
			if ($PowerPlan -ne $currentplan)
			{
				If ($Pscmdlet.ShouldProcess($server, "Changing Power Plan from $CurrentPlan to $PowerPlan"))
				{
					try
					{
						Write-Verbose "Setting Power Plan to $PowerPlan"
						$null = (Get-WmiObject -Name root\cimv2\power -ComputerName $ipaddr -Class Win32_PowerPlan -Filter "ElementName='$PowerPlan'").Activate()
					}
					catch
					{
						Write-Exception $_
						Write-Warning "Couldn't set Power Plan on $server"
						return
					}
				}
			}
			else
			{
				If ($Pscmdlet.ShouldProcess($server, "Stating power plan is already set to $PowerPlan, won't change."))
				{
					Write-Warning "PowerPlan on $server is already set to $PowerPlan. Skipping."
				}
			}
			
			return $planinfo
		}
		
		
		$collection = New-Object System.Collections.ArrayList
		$processed = New-Object System.Collections.ArrayList
	}
	
	PROCESS
	{
		foreach ($server in $ComputerName)
		{
			if ($server -match 'Server\=')
			{
				Write-Verbose "Matched that value was piped from Test-DbaPowerPlan"
				# I couldn't properly unwrap the output from  Test-DbaPowerPlan so here goes.
				$lol = $server.Split("\;")[0]
				$lol = $lol.TrimEnd("\}")
				$lol = $lol.TrimStart("\@\{Server")
				# There was some kind of parsing bug here, don't clown
				$server = $lol.TrimStart("\=")
			}
			
			if ($server -match '\\')
			{
				$server = $server.Split('\\')[0]
			}
			
			if ($server -notin $processed)
			{
				$null = $processed.Add($server)
				Write-Verbose "Connecting to $server"
			}
			else
			{
				continue
			}
			
			$data = Set-DbaPowerPlan $server
			
			if ($data.Count -gt 1)
			{
				$data.GetEnumerator() | ForEach-Object { $null = $collection.Add($_) }
			}
			else
			{
				$null = $collection.Add($data)
			}
		}
	}
	
	END
	{
		If ($Pscmdlet.ShouldProcess("console", "Showing results"))
		{
			return $collection
		}
	}
}