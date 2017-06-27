function Get-DbaProcess {
	<#
		.SYNOPSIS
			This command displays SQL Server processes.

		.DESCRIPTION
			This command displays processes associated with a spid, login, host, program or database.

		.PARAMETER SqlInstance
			The SQL Server instance.

		.PARAMETER SqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. 

		.PARAMETER Spids
			This parameter is auto-populated from -SqlInstance. You can specify one or more Spids (including blocking spids) to be displayed.

		.PARAMETER Logins
			This parameter is auto-populated from-SqlInstance and allows only login names that have active processes. You can specify one or more logins whose processes will be displayed.

		.PARAMETER Hosts
			This parameter is auto-populated from -SqlInstance and allows only host names that have active processes. You can specify one or more Hosts whose processes will be displayed.

		.PARAMETER Programs
			This parameter is auto-populated from -SqlInstance and allows only program names that have active processes. You can specify one or more Programs whose processes will be displayed.

		.PARAMETER Databases
			This parameter is auto-populated from -SqlInstance and allows only database names that have active processes. You can specify one or more Databases whose processes will be displayed.

		.PARAMETER Exclude
			This parameter is auto-populated from -SqlInstance. You can specify one or more Spids to exclude from being displayed (goes well with Logins).

			Exclude is the last filter to run, so even if a Spid matches, for example, Hosts, if it's listed in Exclude it wil be excluded.
			
		.PARAMETER Detailed
			Provides Detailed information

		.PARAMETER NoSystemSpids
			Ignores the System Spids

		.NOTES 
			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Get-DbaProcess

		.EXAMPLE
			Get-DbaProcess -SqlInstance sqlserver2014a -Login base\ctrlb, sa

			Shows information about the processes for base\ctrlb and sa on sqlserver2014a. Uses Windows Authentication to login to sqlserver2014a.

		.EXAMPLE   
			Get-DbaProcess -SqlInstance sqlserver2014a -SqlCredential $credential -Spid 56, 77
				
			Shows information about the processes for spid 56 and 57. Uses alternative (SQL or Windows) credentials to login to sqlserver2014a.

		.EXAMPLE   
			Get-DbaProcess -SqlInstance sqlserver2014a -Program 'Microsoft SQL Server Management Studio'
				
			Shows information about the processes that were created in Microsoft SQL Server Management Studio.

		.EXAMPLE   
			Get-DbaProcess -SqlInstance sqlserver2014a -Host workstationx, server100
				
			Shows information about the processes that were initiated by hosts (computers/clients) workstationx and server 1000.
	#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter]$SqlInstance,
		[object]$SqlCredential,
		[switch]$NoSystemSpids,
		[switch]$Detailed
	)

	begin {
		$sourceserver = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
	}

	process {

		$allsessions = @()
		
		$processes = $sourceserver.EnumProcesses()
		$servercolumn = $processes.Columns.Add("SqlServer", [object])
		$servercolumn.SetOrdinal(0)
		
		foreach ($row in $processes) {
			$row["SqlServer"] = $sourceserver
		}
		
		if ($Login.count -gt 0) {
			$allsessions += $processes | Where-Object { $_.Login -in $Login -and $_.Spid -notin $allsessions.Spid }
		}
		
		if ($Spid.count -gt 0) {
			$allsessions += $processes | Where-Object { ($_.Spid -in $Spid -or $_.BlockingSpid -in $Spid) -and $_.Spid -notin $allsessions.Spid }
		}
		
		if ($Host.count -gt 0) {
			$allsessions += $processes | Where-Object { $_.Host -in $Host -and $_.Spid -notin $allsessions.Spid }
		}
		
		if ($Program.count -gt 0) {
			$allsessions += $processes | Where-Object { $_.Program -in $Program -and $_.Spid -notin $allsessions.Spid }
		}
		
		if ($Database.count -gt 0) {
			$allsessions += $processes | Where-Object { $Database -contains $_.Database -and $_.Spid -notin $allsessions.Spid }
		}
		
		# feel like I'm doing this wrong but it's 2am ;)
		if ($Login -eq $null -and $Spid -eq $null -and $Spid -eq $Exclude -and $Host -eq $null -and $Program -eq $null -and $Program -eq $Database) {
			$allsessions = $processes
		}
		
		if ($nosystemspids -eq $true) {
			$allsessions = $allsessions | Where-Object { $_.Spid -gt 50 }
		}
		
		if ($Exclude.count -gt 0) {
			$allsessions = $allsessions | Where-Object { $Exclude -notcontains $_.SPID -and $_.Spid -notin $allsessions.Spid }
		}
		
		if ($Detailed) {
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
		else {
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
