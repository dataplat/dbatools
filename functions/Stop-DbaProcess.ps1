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

		.PARAMETER Spids
			This parameter is auto-populated from -SqlInstance. You can specify one or more Spids to be killed.

		.PARAMETER Logins
			This parameter is auto-populated from-SqlInstance and allows only login names that have active processes. You can specify one or more logins whose processes will be killed.

		.PARAMETER Hosts
			This parameter is auto-populated from -SqlInstance and allows only host names that have active processes. You can specify one or more Hosts whose processes will be killed.

		.PARAMETER Programs
			This parameter is auto-populated from -SqlInstance and allows only program names that have active processes. You can specify one or more Programs whose processes will be killed.

		.PARAMETER Databases
			This parameter is auto-populated from -SqlInstance and allows only database names that have active processes. You can specify one or more Databases whose processes will be killed.

		.PARAMETER Exclude
			This parameter is auto-populated from -SqlInstance. You can specify one or more Spids to exclude from being killed (goes well with Logins).

			Exclude is the last filter to run, so even if a Spid matches, for example, Hosts, if it's listed in Exclude it wil be excluded.

		.PARAMETER Whatif 
			Shows what would happen if the command were to run. No actions are actually performed. 

		.PARAMETER Confirm 
			Prompts you for confirmation before executing any changing operations within the command. 
			
		.PARAMETER Process 
			This is the process object passed by Get-DbaProcess if using a pipeline
			
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
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
    Param (
        [parameter(Mandatory = $true, ParameterSetName = "Server")]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]$SqlInstance,
        [object]$SqlCredential,
        [parameter(ValueFromPipeline = $true, Mandatory = $true, ParameterSetName = "Process")]
        [object[]]$Process
    )

    process {
        if ($Process) {
            foreach ($session in $Process) {
                $sourceserver = $session.SqlServer
				
                if (!$sourceserver) {
                    Write-Warning "Only process objects can be passed through the pipeline"
                    break
                }
				
                $spid = $session.spid
				
                if ($sourceserver.ConnectionContext.ProcessID -eq $spid) {
                    Write-Warning "Skipping spid $spid because you cannot use KILL to kill your own process"
                    Continue
                }
				
                if ($Pscmdlet.ShouldProcess($sourceserver, "Killing spid $spid")) {
                    try {
                        $sourceserver.KillProcess($spid)
                        [pscustomobject]@{
                            SqlInstance = $sourceserver.name
                            Spid        = $session.Spid
                            Login       = $session.Login
                            Host        = $session.Host
                            Database    = $session.Database
                            Program     = $session.Program
                            Status      = 'Killed'
                        }
                    }
                    catch {
                        Write-Warning "Couldn't kill spid $spid"
                        Write-Exception $_
                    }
                }
            }
            return
        }
		
        $sourceserver = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
		
        if ($Login.count -eq 0 -and $Spid.count -eq 0 -and $Host.count -eq 0 -and $Program.count -eq 0 -and $Database.count -eq 0) {
            Write-Warning "At least one login, spid, host, program or database must be specified."
            continue
        }
		
        $allsessions = @()
		
        $processes = $sourceserver.EnumProcesses() | Where-Object { $_.spid -gt 50 }
		
        if ($Login) {
            $allsessions += $processes | Where-Object { $_.Login -in $Login }
        }
		
        if ($Spid) {
            $allsessions += $processes | Where-Object { $_.Spid -in $Spid }
        }
		
        if ($Host) {
            $allsessions += $processes | Where-Object { $_.Host -in $Host }
        }
		
        if ($Program) {
            $allsessions += $processes | Where-Object { $_.Program -in $Program }
        }
		
        if ($Database) {
            $allsessions += $processes | Where-Object { $_.Database -in $Database }
        }
		
        if ($Exclude) {
            $allsessions = $allsessions | Where-Object { $Exclude -notcontains $_.Spid }
        }
		
        if ($allsessions.urn) {
            Write-Warning "No sessions found"
        }
		
        $duplicates = @()
		
        foreach ($session in $allsessions) {
            if ($session.spid -in $duplicates) { continue }
            $duplicates += $session.spid
			
            $spid = $session.spid
            if ($sourceserver.ConnectionContext.ProcessID -eq $spid) {
                Write-Warning "Skipping spid $spid because you cannot use KILL to kill your own process"
                Continue
            }
			
            if ($Pscmdlet.ShouldProcess($SqlInstance, "Killing spid $spid")) {
                try {
                    $sourceserver.KillProcess($spid)
                    [pscustomobject]@{
                        SqlInstance = $sourceserver.name
                        Spid        = $session.Spid
                        Login       = $session.Login
                        Host        = $session.Host
                        Database    = $session.Database
                        Program     = $session.Program
                        Status      = 'Killed'
                    }
                }
                catch {
                    Write-Warning "Couldn't kill spid $spid"
                    Write-Exception $_
                }
            }
        }
    }
}
