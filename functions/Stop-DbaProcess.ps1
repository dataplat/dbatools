function Stop-DbaProcess {
    <#
		.SYNOPSIS
			This command finds and kills SQL Server processes.

		.DESCRIPTION
			This command kills all spids associated with a spid, login, host, program or database.
				
			if you are attempting to kill your own login sessions, the process performing the kills will be skipped.

		.PARAMETER SqlInstance
			The SQL Server instance.

		.PARAMETER SqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. 

		.PARAMETER Spid
			This parameter is auto-populated from -SqlInstance. You can specify one or more Spids to be killed.

		.PARAMETER Login
			This parameter is auto-populated from-SqlInstance and allows only login names that have active processes. You can specify one or more logins whose processes will be killed.

		.PARAMETER Hostname
			This parameter is auto-populated from -SqlInstance and allows only host names that have active processes. You can specify one or more Hosts whose processes will be killed.

		.PARAMETER Program
			This parameter is auto-populated from -SqlInstance and allows only program names that have active processes. You can specify one or more Programs whose processes will be killed.

		.PARAMETER Database
			This parameter is auto-populated from -SqlInstance and allows only database names that have active processes. You can specify one or more Databases whose processes will be killed.

		.PARAMETER ExcludeSpid
			This parameter is auto-populated from -SqlInstance. You can specify one or more Spids to exclude from being killed (goes well with Logins).

			Exclude is the last filter to run, so even if a Spid matches, for example, Hosts, if it's listed in Exclude it wil be excluded.

		.PARAMETER Whatif 
			Shows what would happen if the command were to run. No actions are actually performed. 

		.PARAMETER Confirm 
			Prompts you for confirmation before executing any changing operations within the command. 
			
		.PARAMETER ProcessCollection 
			This is the process object passed by Get-DbaProcess if using a pipeline
	
		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages
			
		.NOTES 
			Tags: Processes
			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Stop-DbaProcess

		.EXAMPLE
			Stop-DbaProcess -SqlInstance sqlserver2014a -Login base\ctrlb, sa

			Finds all processes for base\ctrlb and sa on sqlserver2014a, then kills them. Uses Windows Authentication to login to sqlserver2014a.

		.EXAMPLE   
			Stop-DbaProcess -SqlInstance sqlserver2014a -SqlCredential $credential -Spids 56, 77
				
			Finds processes for spid 56 and 57, then kills them. Uses alternative (SQL or Windows) credentials to login to sqlserver2014a.

		.EXAMPLE   
			Stop-DbaProcess -SqlInstance sqlserver2014a -Programs 'Microsoft SQL Server Management Studio'
				
			Finds processes that were created in Microsoft SQL Server Management Studio, then kills them.

		.EXAMPLE   
			Stop-DbaProcess -SqlInstance sqlserver2014a -Hosts workstationx, server100
				
			Finds processes that were initiated by hosts (computers/clients) workstationx and server 1000, then kills them.

		.EXAMPLE   
			Stop-DbaProcess -SqlInstance sqlserver2014  -Database tempdb -WhatIf
				
			Shows what would happen if the command were executed.
			
		.EXAMPLE   
			Get-DbaProcess -SqlInstance sql2016 -Programs 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess
				
			Finds processes that were created with dbatools, then kills them.

	#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess)]
	Param (
		[parameter(Mandatory, ParameterSetName = "Server")]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter]
		$SqlInstance,
		
		[Alias("Credential")]
		[PSCredential]
		[System.Management.Automation.CredentialAttribute()]
		$SqlCredential = [System.Management.Automation.PSCredential]::Empty,
		
		[int[]]
		$Spid,
		
		[int[]]
		$ExcludeSpid,
		
		[string[]]
		$Database,
		
		[string[]]
		$Login,
		
		[string[]]
		$Hostname,
		
		[string[]]
		$Program,
		
		[parameter(ValueFromPipeline = $true, Mandatory = $true, ParameterSetName = "Process")]
		[object[]]
		$ProcessCollection,
		
		[switch]
		$Silent
	)
	
	process {
		if (Test-FunctionInterrupt) { return }
		
		if (!$ProcessCollection) {
			$ProcessCollection = Get-DbaProcess @PSBoundParameters
		}
		
		foreach ($session in $ProcessCollection) {
			$sourceserver = $session.Parent
			
			if (!$sourceserver) {
				Stop-Function -Message "Only process objects can be passed through the pipeline" -Category InvalidData -Target $session
				return
			}
			
			$currentspid = $session.spid
			
			if ($sourceserver.ConnectionContext.ProcessID -eq $currentspid) {
				Write-Message -Level Warning -Message "Skipping spid $currentspid because you cannot use KILL to kill your own process" -Target $session
				Continue
			}
			
			if ($Pscmdlet.ShouldProcess($sourceserver, "Killing spid $currentspid")) {
				try {
					$sourceserver.KillProcess($currentspid)
					[pscustomobject]@{
						SqlInstance = $sourceserver.name
						Spid	    = $session.Spid
						Login	    = $session.Login
						Host	    = $session.Host
						Database    = $session.Database
						Program	    = $session.Program
						Status	    = 'Killed'
					}
				}
				catch {
					Stop-Function -Message "Couldn't kill spid $currentspid" -Target $session -ErrorRecord $_ -Continue
				}
			}
		}
	}
}