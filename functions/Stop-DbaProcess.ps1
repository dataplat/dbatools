Function Stop-DbaProcess
{
<#
.SYNOPSIS
This command finds and kills SQL Server processes.

.DESCRIPTION
This command kills all spids associated with a spid, login, host, program or database.
	
If you are attempting to kill your own login sessions, the process performing the kills will be skipped.

.PARAMETER SqlServer
The SQL Server instance.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. 

.PARAMETER Spids
This parameter is auto-populated from -SqlServer. You can specify one or more Spids to be killed.

.PARAMETER Logins
This parameter is auto-populated from-SqlServer and allows only login names that have active processes. You can specify one or more logins whose processes will be killed.

.PARAMETER Hosts
This parameter is auto-populated from -SqlServer and allows only host names that have active processes. You can specify one or more Hosts whose processes will be killed.

.PARAMETER Programs
This parameter is auto-populated from -SqlServer and allows only program names that have active processes. You can specify one or more Programs whose processes will be killed.

.PARAMETER Databases
This parameter is auto-populated from -SqlServer and allows only database names that have active processes. You can specify one or more Databases whose processes will be killed.

.PARAMETER Exclude
This parameter is auto-populated from -SqlServer. You can specify one or more Spids to exclude from being killed (goes well with Logins).

Exclude is the last filter to run, so even if a Spid matches, for example, Hosts, if it's listed in Exclude it wil be excluded.

.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 
	
.PARAMETER Process 
This is the process object passed by Get-DbaProcess if using a pipeline
	
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
	
Finds processes for spid 56 and 57, then kills them. Uses alternative (SQL or Windows) credentials to login to sqlserver2014a.

.EXAMPLE   
Stop-DbaProcess -SqlServer sqlserver2014a -Programs 'Microsoft SQL Server Management Studio'
	
Finds processes that were created in Microsoft SQL Server Management Studio, then kills them.

.EXAMPLE   
Stop-DbaProcess -SqlServer sqlserver2014a -Hosts workstationx, server100
	
Finds processes that were initiated by hosts (computers/clients) workstationx and server 1000, then kills them.

.EXAMPLE   
Stop-DbaProcess -SqlServer sqlserver2014  -Databases tempdb -WhatIf
	
Shows what would happen if the command were executed.
	
.EXAMPLE   
Get-DbaProcess -SqlServer sql2016 -Programs 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess
	
Finds processes that were created with dbatools, then kills them.

#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ParameterSetName = "Server")]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[object]$SqlCredential,
		[parameter(ValueFromPipeline = $true, Mandatory = $true, ParameterSetName = "Process")]
		[object[]]$Process
	)
	
	DynamicParam { if ($sqlserver) { Get-ParamSqlAllProcessInfo -SqlServer $sqlserver -SqlCredential $SqlCredential } }
	
	BEGIN
	{
		$logins = $psboundparameters.Logins
		$spids = $psboundparameters.Spids
		$exclude = $psboundparameters.Exclude
		$hosts = $psboundparameters.Hosts
		$programs = $psboundparameters.Programs
		$databases = $psboundparameters.Databases
	}
	
	PROCESS
	{
		if ($Process)
		{
			foreach ($session in $Process)
			{
				$sourceserver = $session.SqlServer
				
				if (!$sourceserver)
				{
					Write-Warning "Only process objects can be passed through the pipeline"
					break
				}
				
				$spid = $session.spid
				
				if ($sourceserver.ConnectionContext.ProcessID -eq $spid)
				{
					Write-Warning "Skipping spid $spid because you cannot use KILL to kill your own process"
					Continue
				}
				
				If ($Pscmdlet.ShouldProcess($sourceserver, "Killing spid $spid"))
				{
					try
					{
						$sourceserver.KillProcess($spid)
						[pscustomobject]@{
							SqlInstance = $sourceserver.name
							Spid = $session.Spid
							Login = $session.Login
							Host = $session.Host
							Database = $session.Database
							Program = $session.Program
							Status = 'Killed'
						}
					}
					catch
					{
						Write-Warning "Couldn't kill spid $spid"
						Write-Exception $_
					}
				}
			}
			return
		}
		
		$sourceserver = Connect-SqlServer -SqlServer $sqlserver -SqlCredential $SqlCredential
		
		if ($logins.count -eq 0 -and $spids.count -eq 0 -and $hosts.count -eq 0 -and $programs.count -eq 0 -and $databases.count -eq 0)
		{
			Write-Warning "At least one login, spid, host, program or database must be specified."
			continue
		}
		
		$allsessions = @()
		
		$processes = $sourceserver.EnumProcesses() | Where-Object { $_.spid -gt 50 }
		
		if ($logins.count -gt 0)
		{
			$allsessions += $processes | Where-Object { $_.Login -in $Logins }
		}
		
		if ($spids.count -gt 0)
		{
			$allsessions += $processes | Where-Object { $_.Spid -in $spids }
		}
		
		if ($hosts.count -gt 0)
		{
			$allsessions += $processes | Where-Object { $_.Host -in $hosts }
		}
		
		if ($programs.count -gt 0)
		{
			$allsessions += $processes | Where-Object { $_.Program -in $programs }
		}
		
		if ($databases.count -gt 0)
		{
			$allsessions += $processes | Where-Object { $_.Database -in $databases }
		}
		
		if ($exclude.count -gt 0)
		{
			$allsessions = $allsessions | Where-Object { $exclude -notcontains $_.Spid }
		}
		
		if ($allsessions.urn.count -eq 0)
		{
			Write-Warning "No sessions found"
		}
		
		$duplicates = @()
		
		foreach ($session in $allsessions)
		{
			if ($session.spid -in $duplicates) { continue }
			$duplicates += $session.spid
			
			$spid = $session.spid
			if ($sourceserver.ConnectionContext.ProcessID -eq $spid)
			{
				Write-Warning "Skipping spid $spid because you cannot use KILL to kill your own process"
				Continue
			}
			
			If ($Pscmdlet.ShouldProcess($sqlserver, "Killing spid $spid"))
			{
				try
				{
					$sourceserver.KillProcess($spid)
					[pscustomobject]@{
						SqlInstance = $sourceserver.name
						Spid = $session.Spid
						Login = $session.Login
						Host = $session.Host
						Database = $session.Database
						Program = $session.Program
						Status = 'Killed'
					}
				}
				catch
				{
					Write-Warning "Couldn't kill spid $spid"
					Write-Exception $_
				}
			}
		}
	}
}