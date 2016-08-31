Function Stop-DbaProcess
{
<#
.SYNOPSIS 
This command kills all spids associated with a spid or login.

.DESCRIPTION
This command finds and kills spids. If you are killing your own login sessions, the process performing the kills will be skipped.

.PARAMETER SqlServer
The SQL Server instance.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. 

.PARAMETER Spids
This parameter is auto-populated from -SqlServer. You can specify one or more Spids.

.PARAMETER Logins
This parameter is auto-populated from-SqlServer. You can specify one or more logins.

.PARAMETER Exclude
This parameter is auto-populated from -SqlServer. You can specify one or more Spids to exclude from being killed (goes well with Logins).

.NOTES 
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Stop-DbaProcess

.EXAMPLE
Stop-DbaProcess -SqlServer sqlserver2014a -Logins base\ctrlb, sa

Finds all processes for base\ctrlb and sa on sqlserver2014a, then kills them. Uses Windows Authentication to login to sqlserver2014a.

.EXAMPLE   
Stop-DbaProcess -SqlServer sqlserver2014a -SqlCredential $credential -Spids 56, 77
	
Finds processes for spid 56 and 57, then kills them. Uses alternative credentials to login to sqlserver2014a.

.EXAMPLE   
Stop-DbaProcess -SqlServer sqlserver2014  -Logins ad\dba -Spids 56, 77 -WhatIf
	
Shows what would happen if the command were executed.
	
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[object]$SqlCredential
	)
	
	
	DynamicParam
	{
		if ($sqlserver)
		{
			$loginparams = Get-ParamSqlLogins -SqlServer $sqlserver -SqlCredential $SqlCredential
			$allparams = Get-ParamSqlSpids -SqlServer $sqlserver -SqlCredential $SqlCredential
			$null = $allparams.Add("Logins", $loginparams.Logins)
			return $allparams
		}
	}
	
	BEGIN
	{
		$sourceserver = Connect-SqlServer -SqlServer $sqlserver -SqlCredential $SqlCredential
		$source = $sourceserver.DomainInstanceName
		
		$logins = $psboundparameters.Logins
		$spids = $psboundparameters.Spids
		$exclude = $psboundparameters.Exclude
		
		if ($logins.count -eq 0 -and $spids.count -eq 0)
		{
			throw "At least one login or spid must be specified."
		}
	}
	
	PROCESS
	{
		foreach ($spid in $spids)
		{
			$sessions = $sourceserver.EnumProcesses() | Where-Object { $_.Spid -eq $spid }
			
			if ($exclude.count -gt 0)
			{
				foreach ($spid in $exclude)
				{
					$sessions = $sessions | Where-Object { $_.Spid -ne $spid }
				}
			}
			
			if ($sessions.count -eq 0)
			{
				Write-Warning "No sessions found for spid $spid"
			}
			
			foreach ($session in $sessions)
			{
				$spid = $session.spid
				if ($sourceserver.ConnectionContext.ProcessID -eq $spid)
				{
					Write-Output "Skipping spid $spid because it's this process"
					Continue
				}
				
				If ($Pscmdlet.ShouldProcess($sqlserver, "Killing spid $spid"))
				{
					try
					{
						$sourceserver.KillProcess($spid)
						Write-Output "Killed spid $spid"
					}
					catch
					{
						Write-Warning "Couldn't kill spid $spid"
						Write-Exception $_
					}
				}
			}
		}
		
		foreach ($login in $logins)
		{
			$sessions = $sourceserver.EnumProcesses() | Where-Object { $_.Login -eq $login }
			
			if ($exclude.count -gt 0)
			{
				foreach ($spid in $exclude)
				{
					$sessions = $sessions | Where-Object { $_.Spid -ne $spid }
				}
			}
			
			if ($sessions.count -eq 0)
			{
				Write-Warning "No sessions found for $login"
			}
			
			foreach ($session in $sessions)
			{
				$spid = $session.spid
				if ($sourceserver.ConnectionContext.ProcessID -eq $spid)
				{
					Write-Output "Skipping spid $spid because it's this process"
					Continue
				}
				
				If ($Pscmdlet.ShouldProcess($sqlserver, "Killing spid $spid for login $login"))
				{
					try
					{
						$sourceserver.KillProcess($spid)
						Write-Output "Killed spid $spid for login $login"
					}
					catch
					{
						Write-Warning "Couldn't kill spid $spid for login $login"
						Write-Exception $_
					}
				}
			}
		}
	}
	
	END
	{
		$sourceserver.ConnectionContext.Disconnect()
	}
}