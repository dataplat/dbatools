function Copy-DbaAgentSharedSchedule {
    <#
		.SYNOPSIS 
			Copy-DbaAgentSharedSchedule migrates shared job schedules from one SQL Server to another. 

		.DESCRIPTION
			By default, all shared job schedules are copied. The -SharedSchedules parameter is autopopulated for command-line completion and can be used to copy only specific shared job schedules.

			If the associated credential for the account does not exist on the destination, it will be skipped. If the shared job schedule already exists on the destination, it will be skipped unless -Force is used.  

		.PARAMETER Source
			Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

		.PARAMETER SourceSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter. 

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. 	
			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Destination
			Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

		.PARAMETER DestinationSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter. 

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. 	
			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER WhatIf 
			Shows what would happen if the command were to run. No actions are actually performed. 

		.PARAMETER Confirm 
			Prompts you for confirmation before executing any changing operations within the command. 

		.PARAMETER Force
			Drops and recreates the schedule if it exists

		.PARAMETER Silent 
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: Migration, Agent
			Author: Chrissy LeMaire (@cl), netnerds.net
			Requires: sysadmin access on SQL Servers

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Copy-DbaAgentSharedSchedule

		.EXAMPLE   
			Copy-DbaAgentSharedSchedule -Source sqlserver2014a -Destination sqlcluster

			Copies all shared job schedules from sqlserver2014a to sqlcluster, using Windows credentials. If shared job schedules with the same name exist on sqlcluster, they will be skipped.

		.EXAMPLE   
			Copy-DbaAgentSharedSchedule -Source sqlserver2014a -Destination sqlcluster -SharedSchedule Weekly -SourceSqlCredential $cred -Force

			Copies a single shared job schedule, the Weekly shared job schedule from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If a shared job schedule with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

		.EXAMPLE   
			Copy-DbaAgentSharedSchedule -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

			Shows what would happen if the command were executed using force.
	#>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Source,
        [PSCredential][System.Management.Automation.CredentialAttribute()]
        $SourceSqlCredential,
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Destination,
        [PSCredential][System.Management.Automation.CredentialAttribute()]
        $DestinationSqlCredential,
        [switch]$Force,
        [switch]$Silent
    )

	
    begin {

        $sourceserver = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        $destserver = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
		
        $source = $sourceserver.DomainInstanceName
        $destination = $destserver.DomainInstanceName
		
        if ($sourceserver.versionMajor -lt 9 -or $destserver.versionMajor -lt 9) {
            throw "Server SharedSchedules are only supported in SQL Server 2005 and above. Quitting."
        }
		
        $serverschedules = $sourceserver.JobServer.SharedSchedules
        $destschedules = $destserver.JobServer.SharedSchedules
    }
    process {
        foreach ($schedule in $serverschedules) {
            $schedulename = $schedule.name
            if ($schedules.length -gt 0 -and $schedules -notcontains $schedulename) { continue }
			
            if ($destschedules.name -contains $schedulename) {
                if ($force -eq $false) {
                    Write-Warning "Shared job schedule $schedulename exists at destination. Use -Force to drop and migrate."
                    continue
                }
                else {
                    if ($destserver.JobServer.jobs.Jobschedules.name -contains $schedulename) { 
                        Write-Warning "Schedule $schedulename has associated jobs. Skipping."
                        continue
                    }
                    else {
					
                        if ($Pscmdlet.ShouldProcess($destination, "Dropping schedule $schedulename and recreating")) {
                            try {
                                Write-Verbose "Dropping schedule $schedulename"
                                $destserver.JobServer.SharedSchedules[$schedulename].Drop()
                            }
                            catch { 
                                Write-Exception $_ 
                                continue
                            }
                        }
                    }
                }
            }

            If ($Pscmdlet.ShouldProcess($destination, "Creating schedule $schedulename")) {
                try {
                    Write-Output "Copying schedule $schedulename"
                    $sql = $schedule.Script() | Out-String
                    $sql = $sql -replace [Regex]::Escape("'$source'"), "'$destination'"
                    Write-Verbose $sql
                    $destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
                }
                catch {
                    Write-Exception $_
                }
            }
        }
    }
	
    end {
        $sourceserver.ConnectionContext.Disconnect()
        $destserver.ConnectionContext.Disconnect()
        If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "Job schedule migration finished" }
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlSharedSchedule
    }
}
