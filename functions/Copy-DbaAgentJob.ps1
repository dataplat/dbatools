function Copy-DbaAgentJob {
    <#
.SYNOPSIS
Copy-DbaAgentJob migrates jobs from one SQL Server to another.

.DESCRIPTION
By default, all jobs are copied. The -Jobs parameter is autopopulated for command-line completion and can be used to copy only specific jobs.

If the job already exists on the destination, it will be skipped unless -Force is used.

.PARAMETER Source
Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER Destination
Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SourceSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter.

Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER DestinationSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter.

Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

To connect as a different Windows user, run PowerShell as that user.

.PARAMETER DisableOnSource
Disable the job on the source server

.PARAMETER DisableOnDestination
Disable the newly migrated job on the destination server

.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 

.PARAMETER Force
Drops and recreates the Job if it exists

.PARAMETER Silent
Replaces user friendly yellow warnings with bloody red exceptions of doom!

.NOTES
Tags: Migration, Agent
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Copy-DbaAgentJob

.EXAMPLE
Copy-DbaAgentJob -Source sqlserver2014a -Destination sqlcluster

Copies all jobs from sqlserver2014a to sqlcluster, using Windows credentials. If jobs with the same name exist on sqlcluster, they will be skipped.

.EXAMPLE
Copy-DbaAgentJob -Source sqlserver2014a -Destination sqlcluster -Job PSJob -SourceSqlCredential $cred -Force

Copies a single job, the PSJob job from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If a job with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

.EXAMPLE
Copy-DbaAgentJob -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

Shows what would happen if the command were executed using force.
#>
    [cmdletbinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Source,
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Destination,
        [System.Management.Automation.PSCredential]$SourceSqlCredential,
        [System.Management.Automation.PSCredential]$DestinationSqlCredential,
        [switch]$DisableOnSource,
        [switch]$DisableOnDestination,
        [switch]$Force,
        [switch]$Silent
    )


    BEGIN {
        $jobs = $psboundparameters.Jobs
        $exclude = $psboundparameters.Exclude

        $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        $destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

        $source = $sourceServer.DomainInstanceName
        $destination = $destServer.DomainInstanceName

    }
    PROCESS {

        if (Test-FunctionInterrupt) { return }

        $serverJobs = $sourceServer.JobServer.Jobs
        $destJobs = $destServer.JobServer.Jobs

        foreach ($job in $serverJobs) {
            $jobName = $job.name
            $jobId = $job.JobId

            if ($jobs.count -gt 0 -and $jobs -notcontains $jobName -or $exclude -contains $jobName) { continue }
            Write-Message -Message "Working on job: $jobName" -Level Verbose -Silent $Silent
            $sql = "
				SELECT sp.[name] AS MaintenancePlanName
				FROM msdb.dbo.sysmaintplan_plans AS sp
				INNER JOIN msdb.dbo.sysmaintplan_subplans AS sps
					ON sps.plan_id = sp.id
				WHERE job_id = '$($jobId)'"
            Write-Message -Message $sql -Level Debug -Silent $Silent

            $MaintenancePlan = $sourceServer.ConnectionContext.ExecuteWithResults($sql).Tables.Rows
            $MaintPlanName = $MaintenancePlan.MaintenancePlanName

            if ($MaintenancePlan) {
                Stop-Function -Message "Job [$jobname] is associated with Maintennace Plan: $MaintPlanName" -Target $jobName -Continue -Silent $Silent
            }

            $dbNames = $job.JobSteps.Databasename | Where-Object { $_.length -gt 0 }
            $missingDb = $dbNames | Where-Object { $destServer.Databases.Name -notcontains $_ }

            if ($missingDb.count -gt 0 -and $dbNames.count -gt 0) {
                $missingDb = ($missingDb | Sort-Object | Get-Unique) -join ", "
                Stop-Function -Message "Database(s) $missingDb doesn't exist on destination. Skipping job [$jobname]." -Target $jobName -Continue -Silent $Silent
            }

            $missingLogin = $job.OwnerLoginName | Where-Object { $destServer.Logins.Name -notcontains $_ }

            if ($missingLogin.count -gt 0) {
                $missingLogin = ($missingLogin | Sort-Object | Get-Unique) -join ", "
                Stop-Function -Message "Login(s) $missingLogin doesn't exist on destination. Skipping job [$jobname]." -Target $jobName -Continue -Silent $Silent
            }

            $proxyNames = $job.JobSteps.ProxyName | Where-Object { $_.length -gt 0 }
            $missingProxy = $proxyNames | Where-Object { $destServer.JobServer.ProxyAccounts.Name -notcontains $_ }

            if ($missingProxy.count -gt 0 -and $proxyNames.count -gt 0) {
                $missingProxy = ($missingProxy | Sort-Object | Get-Unique) -join ", "
                Stop-Function -Message "Proxy Account(s) $($proxyNames[0]) doesn't exist on destination. Skipping job [$jobname]." -Target $jobName -Continue -Silent $Silent
            }

            $operators = $job.OperatorToEmail, $job.OperatorToNedSend, $job.OperatorToPage | Where-Object { $_.Length -gt 0 }
            $missingOperators = $operators | Where-Object {$destServer.JobServer.Operators.Name -notcontains $_}

            if ($missingOperators.Count -gt 0 -and $operators.Count -gt 0) {
                $missingOperator = ($operators | Sort-Object | Get-Unique) -join ", "
                Stop-Function -Message "Operator(s) $($missingOperator) doesn't exist on destination. Skipping job [$jobname]" -Target $jobName -Continue -Silent $Silent
            }

            if ($destJobs.name -contains $job.name) {
                if ($force -eq $false) {
                    Stop-Function -Message "Job $jobName exists at destination. Use -Force to drop and migrate." -Target $jobName -Continue -Silent $Silent
                }
                else {
                    if ($Pscmdlet.ShouldProcess($destination, "Dropping job $jobName and recreating")) {
                        try {
                            Write-Message -Message "Dropping Job $jobName" -Level Verbose
                            $destServer.JobServer.Jobs[$job.name].Drop()
                        }
                        catch {
                            Stop-Function -Message "Issue dropping job. See error log under $((Get-DbaConfig -Name dbatoolslogpath).Value) for more details." -Target $jobName -InnerErrorRecord $_ -Continue -Silent $Silent
                        }
                    }
                }
            }

            if ($Pscmdlet.ShouldProcess($destination, "Creating Job $jobName")) {
                try {
                    Write-Message -Message "Copying Job $jobName" -Level Output -Silent $Silent
                    $sql = $job.Script() | Out-String
                    $sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
                    Write-Message -Message $sql -Level Debug -Silent $Silent
                    $destServer.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
                }
                catch {
                    Stop-Function -Message "Issue copying job. See error log under $((Get-DbaConfig -Name dbatoolslogpath).Value) for more details." -Target $jobName -InnerErrorRecord $_ -Continue -Silent $Silent
                }
            }
			
            if ($DisableOnDestination) {
                if ($Pscmdlet.ShouldProcess($destination, "Disabling $jobName")) {
                    Write-Message -Message "Disabling $jobName on $destination" -Level Output -Silent $Silent
                    $destServer.JobServer.Jobs.Refresh()
                    $destServer.JobServer.Jobs[$job.name].IsEnabled = $False
                    $destServer.JobServer.Jobs[$job.name].Alter()
                }
            }

            if ($DisableOnSource) {
                if ($Pscmdlet.ShouldProcess($source, "Disabling $jobName")) {
                    Write-Message -Message "Disabling $jobName on $source" -Level Output -Silent $Silent
                    $job.IsEnabled = $false
                    $job.Alter()
                }
            }
        }
    }

    END {
        $sourceServer.ConnectionContext.Disconnect()
        $destServer.ConnectionContext.Disconnect()
        if ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "Job migration finished" }
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlAlert
    }
}
