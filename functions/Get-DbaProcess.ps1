function Get-DbaProcess {
	<#
		.SYNOPSIS
			This command displays SQL Server processes.

		.DESCRIPTION
			This command displays processes associated with a spid, login, host, program or database.
			
			Thanks to https://sqlperformance.com/2017/07/sql-performance/find-database-connection-leaks for the
			query to get the last executed SQL statement
	
		.PARAMETER SqlInstance
			The SQL Server instance.

		.PARAMETER SqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. 

		.PARAMETER Spid
			This parameter is auto-populated from -SqlInstance. You can specify one or more Spids (including blocking spids) to be displayed.

		.PARAMETER Login
			This parameter is auto-populated from-SqlInstance and allows only login names that have active processes. You can specify one or more logins whose processes will be displayed.

		.PARAMETER Hostname
			This parameter is auto-populated from -SqlInstance and allows only host names that have active processes. You can specify one or more Hosts whose processes will be displayed.

		.PARAMETER Program
			This parameter is auto-populated from -SqlInstance and allows only program names that have active processes. You can specify one or more Programs whose processes will be displayed.

		.PARAMETER Database
			This parameter is auto-populated from -SqlInstance and allows only database names that have active processes. You can specify one or more Databases whose processes will be displayed.

		.PARAMETER ExcludeSpid
			This parameter is auto-populated from -SqlInstance. You can specify one or more Spids to exclude from being displayed (goes well with Logins).

			Exclude is the last filter to run, so even if a Spid matches, for example, Hosts, if it's listed in Exclude it wil be excluded.

		.PARAMETER NoSystemSpid
			Ignores the System Spids
			
		.PARAMETER Silent
		Use this switch to disable any kind of verbose messages
	
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
		[DbaInstanceParameter[]]$SqlInstance,
		[Alias("Credential")]
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SqlCredential,
		[int[]]$Spid,
		[int[]]$ExcludeSpid,
		[string[]]$Database,
		[string[]]$Login,
		[string[]]$Hostname,
		[string[]]$Program,
		[switch]$NoSystemSpid,
		[switch]$Silent
	)
	
	process {
		foreach ($instance in $sqlinstance) {
			
			Write-Message -Message "Attempting to connect to $instance" -Level Verbose
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
			}
			catch {
				Stop-Function -Message "Could not connect to Sql Server instance $instance : $_" -Target $instance -ErrorRecord $_ -Continue
			}
			
			$sql = "SELECT datediff(minute, s.last_request_end_time, getdate()) as MinutesAsleep, s.session_id as spid, s.host_process_id as HostProcessId, t.text as Query
					FROM sys.dm_exec_connections c join sys.dm_exec_sessions s on c.session_id = s.session_id cross apply sys.dm_exec_sql_text(c.most_recent_sql_handle) t"
			
			if ($server.VersionMajor -gt 8) {
				$results = $server.Query($sql)
			}
			else {
				$results = $null
			}
			
			$allsessions = @()
			
			$processes = $server.EnumProcesses()
			
			if ($Login) {
				$allsessions += $processes | Where-Object { $_.Login -in $Login -and $_.Spid -notin $allsessions.Spid }
			}
			
			if ($Spid) {
				$allsessions += $processes | Where-Object { ($_.Spid -in $Spid -or $_.BlockingSpid -in $Spid) -and $_.Spid -notin $allsessions.Spid }
			}
			
			if ($Hostname) {
				$allsessions += $processes | Where-Object { $_.Host -in $Hostname -and $_.Spid -notin $allsessions.Spid }
			}
			
			if ($Program) {
				$allsessions += $processes | Where-Object { $_.Program -in $Program -and $_.Spid -notin $allsessions.Spid }
			}
			
			if ($Database) {
				$allsessions += $processes | Where-Object { $Database -contains $_.Database -and $_.Spid -notin $allsessions.Spid }
			}
						
			if (Was-bound -not 'Login','Spid','ExcludeSpid','Host', 'Program','Database') {
				$allsessions = $processes
			}
			
			if ($NoSystemSpid -eq $true) {
				$allsessions = $allsessions | Where-Object { $_.Spid -gt 50 }
			}
			
			if ($Exclude) {
				$allsessions = $allsessions | Where-Object { $Exclude -notcontains $_.SPID -and $_.Spid -notin $allsessions.Spid }
			}
			
			foreach ($session in $allsessions) {
				
				if ($session.Status -eq "") {
					$status = "sleeping"
				}
				else {
					$status = $session.Status
				}
				
				if ($session.Command -eq "") {
					$command = "AWAITING COMMAND"
				}
				else {
					$command = $session.Command
				}
				
				$row = $results | Where-Object { $_.Spid -eq $session.Spid }

				Add-Member -InputObject $session -MemberType NoteProperty -Name Parent -value $server
				Add-Member -InputObject $session -MemberType NoteProperty -Name ComputerName -value $server.NetName
				Add-Member -InputObject $session -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
				Add-Member -InputObject $session -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
				Add-Member -InputObject $session -MemberType NoteProperty -Name Status -value $status -Force
				Add-Member -InputObject $session -MemberType NoteProperty -Name Command -value $command -Force
				Add-Member -InputObject $session -MemberType NoteProperty -Name LastQuery -value $row.Query -Force
				Add-Member -InputObject $session -MemberType NoteProperty -Name HostProcessId -value $row.HostProcessId -Force
				
				Select-DefaultView -InputObject $session -Property ComputerName, InstanceName, SqlInstance, Spid, Login, Host, Database, BlockingSpid, Program, Status, Command, Cpu, MemUsage, IsSystem, HostProcessId, LastQuery
			}
		}
	}
}