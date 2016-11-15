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
	
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[object]$SqlCredential
	)
	
	DynamicParam { if ($sqlserver) { Get-ParamSqlAllProcessInfo -SqlServer $sqlserver -SqlCredential $SqlCredential } }
	
	BEGIN
	{
		$sourceserver = Connect-SqlServer -SqlServer $sqlserver -SqlCredential $SqlCredential
		$source = $sourceserver.DomainInstanceName
		
		$logins = $psboundparameters.Logins
		$spids = $psboundparameters.Spids
		$exclude = $psboundparameters.Exclude
		$hosts = $psboundparameters.Hosts
		$programs = $psboundparameters.Programs
		$databases = $psboundparameters.Databases
		
		if ($logins.count -eq 0 -and $spids.count -eq 0 -and $hosts.count -eq 0 -and $programs.count -eq 0 -and $databases.count -eq 0)
		{
			throw "At least one login, spid, host, program or database must be specified."
		}
	}
	
	PROCESS
	{
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
			$login = $session.login
			$database = $session.database
			$program = $session.program
			$host = $session.host
			
			$info = @()
			
			if ($login.length -gt 1)
			{
				$info += "Login: $login"
			}
			
			if ($database.length -gt 1)
			{
				$info += "Database: $database"
			}
			
			if ($program.length -gt 1)
			{
				$info += "Program: $program"
			}
			
			if ($host.length -gt 1)
			{
				$info += "Host: $host"
			}
			
			$info = $info -join ", "
			
			if ($sourceserver.ConnectionContext.ProcessID -eq $spid)
			{
				Write-Output "Skipping spid $spid because it's this process"
				Continue
			}
			
			If ($Pscmdlet.ShouldProcess($sqlserver, "Killing spid $spid ($info)"))
			{
				try
				{
					$sourceserver.KillProcess($spid)
					Write-Output "Killed spid $spid ($info)"
				}
				catch
				{
					Write-Warning "Couldn't kill spid $spid ($info)"
					Write-Exception $_
				}
			}
		}
	}
	
	END
	{
		$sourceserver.ConnectionContext.Disconnect()
	}
}