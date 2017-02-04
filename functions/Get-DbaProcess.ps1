Function Get-DbaProcess
{
<#
.SYNOPSIS
This command displays SQL Server processes.

.DESCRIPTION
This command displays processes associated with a spid, login, host, program or database.

.PARAMETER SqlServer
The SQL Server instance.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. 

.PARAMETER Spids
This parameter is auto-populated from -SqlServer. You can specify one or more Spids (including blocking spids) to be displayed.

.PARAMETER Logins
This parameter is auto-populated from-SqlServer and allows only login names that have active processes. You can specify one or more logins whose processes will be displayed.

.PARAMETER Hosts
This parameter is auto-populated from -SqlServer and allows only host names that have active processes. You can specify one or more Hosts whose processes will be displayed.

.PARAMETER Programs
This parameter is auto-populated from -SqlServer and allows only program names that have active processes. You can specify one or more Programs whose processes will be displayed.

.PARAMETER Databases
This parameter is auto-populated from -SqlServer and allows only database names that have active processes. You can specify one or more Databases whose processes will be displayed.

.PARAMETER Exclude
This parameter is auto-populated from -SqlServer. You can specify one or more Spids to exclude from being displayed (goes well with Logins).

Exclude is the last filter to run, so even if a Spid matches, for example, Hosts, if it's listed in Exclude it wil be excluded.
	
.PARAMETER Detailed
Provides Detailed information

.PARAMETER NoSystemSpids
Ignores the System Spids
.NOTES 
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Get-DbaProcess

.EXAMPLE
Get-DbaProcess -SqlServer sqlserver2014a -Logins base\ctrlb, sa

Shows information about the processes for base\ctrlb and sa on sqlserver2014a. Uses Windows Authentication to login to sqlserver2014a.

.EXAMPLE   
Get-DbaProcess -SqlServer sqlserver2014a -SqlCredential $credential -Spids 56, 77
	
Shows information about the processes for spid 56 and 57. Uses alternative (SQL or Windows) credentials to login to sqlserver2014a.

.EXAMPLE   
Get-DbaProcess -SqlServer sqlserver2014a -Programs 'Microsoft SQL Server Management Studio'
	
Shows information about the processes that were created in Microsoft SQL Server Management Studio.

.EXAMPLE   
Get-DbaProcess -SqlServer sqlserver2014a -Hosts workstationx, server100
	
Shows information about the processes that were initiated by hosts (computers/clients) workstationx and server 1000.
	
#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[object]$SqlCredential,
		[switch]$NoSystemSpids,
		[switch]$Detailed
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
	}
	
	PROCESS
	{
		$allsessions = @()
		
		$processes = $sourceserver.EnumProcesses()
		$servercolumn = $processes.Columns.Add("SqlServer", [object])
		$servercolumn.SetOrdinal(0)
		
		foreach ($row in $processes)
		{
			$row["SqlServer"] = $sourceserver
		}
		
		if ($logins.count -gt 0)
		{
			$allsessions += $processes | Where-Object { $_.Login -in $Logins -and $_.Spid -notin $allsessions.Spid }
		}
		
		if ($spids.count -gt 0)
		{
			$allsessions += $processes | Where-Object { ($_.Spid -in $spids -or $_.BlockingSpid -in $spids) -and $_.Spid -notin $allsessions.Spid }
		}
		
		if ($hosts.count -gt 0)
		{
			$allsessions += $processes | Where-Object { $_.Host -in $hosts -and $_.Spid -notin $allsessions.Spid }
		}
		
		if ($programs.count -gt 0)
		{
			$allsessions += $processes | Where-Object { $_.Program -in $programs -and $_.Spid -notin $allsessions.Spid }
		}
		
		if ($databases.count -gt 0)
		{
			$allsessions += $processes | Where-Object { $databases -contains $_.Database -and $_.Spid -notin $allsessions.Spid }
		}
		
		# feel like I'm doing this wrong but it's 2am ;)
		if ($logins -eq $null -and $spids -eq $null -and $spids -eq $exclude -and $hosts -eq $null -and $programs -eq $null -and $programs -eq $databases)
		{
			$allsessions = $processes
		}
		
		if ($nosystemspids -eq $true)
		{
			$allsessions = $allsessions | Where-Object { $_.Spid -gt 50 }
		}
		
		if ($exclude.count -gt 0)
		{
			$allsessions = $allsessions | Where-Object { $exclude -notcontains $_.SPID -and $_.Spid -notin $allsessions.Spid }
		}
		
		if ($Detailed)
		{
			$object = ($allsessions | Select-Object SqlServer, Spid, Login, Host, Database, BlockingSpid, Program, @{
					name = "Status"; expression = {
						if ($_.Status -eq "") { "sleeping" }
						else { $_.Status }
					}
				}, @{
					name = "Command"; expression = {
						if ($_.Command -eq "") { "AWAITING COMMAND" }
						else { $_.Command }
					}
				}, Cpu, MemUsage, IsSystem)
			
			Select-DefaultView -InputObject $object -Property Spid, Login, Host, Database, BlockingSpid, Program, Status, Command, Cpu, MemUsage, IsSystem
		}
		else
		{
			$object = ($allsessions | Select-Object SqlServer, Spid, Login, Host, Database, BlockingSpid, Program, @{
					name = "Status"; expression = {
						if ($_.Status -eq "") { "sleeping" }
						else { $_.Status }
					}
				}, @{
					name = "Command"; expression = {
						if ($_.Command -eq "") { "AWAITING COMMAND" }
						else { $_.Command }
					}
				})
			
			Select-DefaultView -InputObject $object -Property Spid, Login, Host, Database, BlockingSpid, Program, Status, Command
		}
	}
}