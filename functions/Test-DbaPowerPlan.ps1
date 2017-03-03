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
	Param (
		[parameter(ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance", "SqlServer")]
		[string[]]$ComputerName = $env:COMPUTERNAME,
		[PSCredential][System.Management.Automation.CredentialAttribute()]$Credential,
		[string]$CustomPowerPlan,
		[switch]$Detailed,
		[switch]$Silent
	)
	
	BEGIN
	{
		If ($Detailed)
		{
			Write-Warning "Detailed is deprecated and will be removed in dbatools 1.0"
		}
		
		$bpPowerPlan = [PSCustomObject]@{
			InstanceID = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
			ElementName = $null
		}
		
		$sessionoption = New-CimSessionOption -Protocol DCom
	}
	
	PROCESS
	{
		foreach ($computer in $ComputerName)
		{
			$Server = Resolve-DbaNetworkName -ComputerName $computer -Credential $credential
			
			$Computer = $server.ComputerName
			
			if (!$Computer)
			{
				Stop-Function -Message "Couldn't resolve hostname. Skipping."
				continue
			}
			
			Write-Message -Level Verbose -Message "Creating CimSession on $computer over WSMan"
			
			if (!$Credential)
			{
				$cimsession = New-CimSession -ComputerName $Computer -ErrorAction SilentlyContinue
			}
			else
			{
				$cimsession = New-CimSession -ComputerName $Computer -ErrorAction SilentlyContinue -Credential $Credential
			}
			
			if (!$cimsession.Protocol)
			{
				Write-Message -Level Verbose -Message "Creating CimSession on $computer over WSMan failed. Creating CimSession on $computer over DCom"
				
				if (!$Credential)
				{
					$cimsession = New-CimSession -ComputerName $Computer -SessionOption $sessionoption -ErrorAction SilentlyContinue -Credential $Credential
				}
				else
				{
					$cimsession = New-CimSession -ComputerName $Computer -SessionOption $sessionoption -ErrorAction SilentlyContinue
				}
			}
			
			if ($null -eq $cimsession.id)
			{
				Stop-Function -Message "Can't create CimSession on $computer"
			}
			
			Write-Message -Level Verbose -Message "Getting Power Plan information from $Computer"
			
			try
			{
				$powerplans = Get-CimInstance -CimSession $cimsession -classname Win32_PowerPlan -Namespace "root\cimv2\power" -ErrorAction Stop | Select-Object ElementName, InstanceID, IsActive
			}
			catch
			{
				Stop-Function -Message "This command does not support Windows 2000"
			}
			
			$powerplan = $powerplans | Where-Object { $_.IsActive -eq 'True' } | Select-Object ElementName, InstanceID
			$powerplan.InstanceID = $powerplan.InstanceID.Split('{')[1].Split('}')[0]
			
			if ($CustomPowerPlan.Length -gt 0)
			{
				$bpPowerPlan.ElementName = $CustomPowerPlan
				$bpPowerPlan.InstanceID = $($powerplans | Where-Object { $_.ElementName -eq $CustomPowerPlan }).InstanceID
			}
			else
			{
				$bpPowerPlan.ElementName = $($powerplans | Where-Object { $_.InstanceID.Split('{')[1].Split('}')[0] -eq $bpPowerPlan.InstanceID }).ElementName
				if ($null -eq $bpPowerplan.ElementName)
				{
					$bpPowerPlan.ElementName = "You do not have the high performance plan installed on this machine."
				}
			}
			
			Write-Verbose "Recommended GUID is $($bpPowerPlan.InstanceID) and you have $($powerplan.InstanceID)"
			
			if ($null -eq $powerplan.InstanceID)
			{
				$powerplan.ElementName = "Unknown"
			}
			
			if ($powerplan.InstanceID -eq $bpPowerPlan.InstanceID)
			{
				$IsBestPractice = $true
			}
			else
			{
				$IsBestPractice = $false
			}
			
			[PSCustomObject]@{
				Server = $computer
				ActivePowerPlan = $powerplan.ElementName
				RecommendedPowerPlan = $bpPowerPlan.ElementName
				IsBestPractice = $IsBestPractice
			}
		}
	}
}