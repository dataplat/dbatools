Function Test-DbaPowerPlan
{
<#
.SYNOPSIS
Checks SQL Server Power Plan, which Best Practices recommends should be set to High Performance
	
.DESCRIPTION
Returns $true or $false by default for one server. Returns Server name and IsBestPractice for more than one server.
	
Specify -Detailed for details.
	
References:
https://support.microsoft.com/en-us/kb/2207548
http://www.sqlskills.com/blogs/glenn/windows-power-plan-effects-on-newer-intel-processors/
	
.PARAMETER ComputerName
The SQL Server (or server in general) that you're connecting to. The -SqlServer parameter also works.
	
.PARAMETER CustomPowerPlan
If your organization uses a custom power plan that's considered best practice, specify it here.
	
.PARAMETER Detailed
Show a detailed list.

.NOTES 
Requires: WMI access to servers
	
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Test-DbaPowerPlan

.EXAMPLE
Test-DbaPowerPlan -ComputerName sqlserver2014a

To return true or false for Power Plan being set to High Performance

.EXAMPLE   
Test-DbaPowerPlan -ComputerName sqlserver2014a -CustomPowerPlan 'Maximum Performance'
	
To return true or false for Power Plan being set to the custom power plan called Maximum Performance
	
.EXAMPLE   
Test-DbaPowerPlan -ComputerName sqlserver2014a -Detailed
	
To return detailed information Power Plans
	
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance", "SqlServer")]
		[string[]]$ComputerName,
		[string]$CustomPowerPlan,
		[switch]$Detailed
	)
	
	BEGIN
	{
		$bpPowerPlan = 'High Performance'
		
		if ($CustomPowerPlan.Length -gt 0)
		{
			$bpPowerPlan = $CustomPowerPlan
		}
		
		Function Get-PowerPlan
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
				$powerplan = Get-WmiObject -Namespace Root\CIMV2\Power -ComputerName $ipaddr -Query $query -ErrorAction SilentlyContinue
				$powerplan = $powerplan.ElementName
			}
			catch 
			{
				Write-Warning "Can't connect to WMI on $server"
				return
			}
			
			if ($powerplan -eq $null)
			{
				# the try/catch above isn't working, so make it silent and handle it here.
				$powerplan = "Unknown"
			}
			
			if ($powerplan -eq $bpPowerPlan)
			{
				$IsBestPractice = $true
			}
			else
			{
				$IsBestPractice = $false
			}
			
			$planinfo = [PSCustomObject]@{
				Server = $server
				ActivePowerPlan = $powerplan
				RecommendedPowerPlan = $bpPowerPlan
				IsBestPractice = $IsBestPractice
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
			if ($server -match '\\')
			{
				Write-Verbose "SQL Server naming convention detected. Getting hostname."
				$server = $server.Split('\')[0]
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
			
			$data = Get-PowerPlan $server
			
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
		if ($Detailed -eq $true)
		{
			return $collection
		}
		elseif ($processed.Count -gt 1)
		{
			$newcollection = @()
			foreach ($computer in $collection)
			{
				if ($newcollection.Server -contains $computer.Server) { continue }
								
				$newcollection += [PSCustomObject]@{
					Server = $computer.Server
					IsBestPractice = $computer.IsBestPractice
				}
			}
			return $newcollection
		}
		else
		{
			foreach ($computer in $collection)
			{
				return $computer.IsBestPractice
			}
		}
	}
}