function Copy-DbaAgentJob {
	<#
		.SYNOPSIS
			Copy-DbaAgentJob migrates jobs from one SQL Server to another.

		.DESCRIPTION
			By default, all jobs are copied. The -Job parameter is autopopulated for command-line completion and can be used to copy only specific jobs.

			If the job already exists on the destination, it will be skipped unless -Force is used.

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

		.PARAMETER Job
			The job(s) to process - this list is auto populated from the server. If unspecified, all jobs will be processed.

		.PARAMETER ExcludeJob
			The job(s) to exclude - this list is auto populated from the server

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
			Tags: Migration, Agent, Job
			Author: Chrissy LeMaire (@cl), netnerds.net

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

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
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SourceSqlCredential,
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Destination,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$DestinationSqlCredential,
		[object[]]$Job,
		[object[]]$ExcludeJob,
		[switch]$DisableOnSource,
		[switch]$DisableOnDestination,
		[switch]$Force,
		[switch]$Silent
	)

	begin {

		$sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
		$destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

		$source = $sourceServer.DomainInstanceName
		$destination = $destServer.DomainInstanceName

	}
	process {

		if (Test-FunctionInterrupt) { return }

		$serverJobs = $sourceServer.JobServer.Jobs
		$destJobs = $destServer.JobServer.Jobs

		foreach ($serverJob in $serverJobs) {
			$jobName = $serverJob.name
            $jobId = $serverJob.JobId

            $copyJobStatus = [pscustomobject]@{
                SourceServer        = $sourceServer.Name
                DestinationServer   = $destServer.Name
                Name                = $jobName
                Status              = $null
                DateTime            = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
            }

            if ($Job -and $jobName -notin $Job -or $jobName -in $ExcludeJob) { 
                $copyJobStatus.Status = "Skipped"
				$copyJobStatus
				Write-Message -Level Verbose -Message "Job [$jobName] filtered. Skipping."
				continue
			}
			Write-Message -Message "Working on job: $jobName" -Level Verbose
			$sql = "
				SELECT sp.[name] AS MaintenancePlanName
				FROM msdb.dbo.sysmaintplan_plans AS sp
				INNER JOIN msdb.dbo.sysmaintplan_subplans AS sps
					ON sps.plan_id = sp.id
				WHERE job_id = '$($jobId)'"
			Write-Message -Message $sql -Level Debug

			$MaintenancePlanName = $sourceServer.Query($sql).MaintenancePlanName

            if ($MaintenancePlanName) {
				$copyJobStatus.Status = "Skipped"
				$copyJobStatus
                Write-Message -Level Warning -Message "Job [$jobname] is associated with Maintennace Plan: $MaintenancePlanName"
				continue
			}

			$dbNames = $serverJob.JobSteps.DatabaseName | Where-Object { $_.Length -gt 0 }
			$missingDb = $dbNames | Where-Object { $destServer.Databases.Name -notcontains $_ }

			if ($missingDb.Count -gt 0 -and $dbNames.Count -gt 0) {
                $missingDb = ($missingDb | Sort-Object | Get-Unique) -join ", "
                $copyJobStatus.Status = "Skipped"
				$copyJobStatus
                Write-Message -Level Warning -Message "Database(s) $missingDb doesn't exist on destination. Skipping job [$jobname]."
				continue
			}

			$missingLogin = $serverJob.OwnerLoginName | Where-Object { $destServer.Logins.Name -notcontains $_ }

			if ($missingLogin.Count -gt 0) {
                $missingLogin = ($missingLogin | Sort-Object | Get-Unique) -join ", "
                $copyJobStatus.Status = "Skipped"
				$copyJobStatus
                Write-Message -Level Warning -Message "Login(s) $missingLogin doesn't exist on destination. Skipping job [$jobname]."
				continue
			}

			$proxyNames = $serverJob.JobSteps.ProxyName | Where-Object { $_.Length -gt 0 }
			$missingProxy = $proxyNames | Where-Object { $destServer.JobServer.ProxyAccounts.Name -notcontains $_ }

			if ($missingProxy.Count -gt 0 -and $proxyNames.Count -gt 0) {
                $missingProxy = ($missingProxy | Sort-Object | Get-Unique) -join ", "
                $copyJobStatus.Status = "Skipped"
				$copyJobStatus
                Write-Message -Level Warning -Message "Proxy Account(s) $($proxyNames[0]) doesn't exist on destination. Skipping job [$jobname]."
				continue
			}

			$operators = $serverJob.OperatorToEmail, $serverJob.OperatorToNetSend, $serverJob.OperatorToPage | Where-Object { $_.Length -gt 0 }
			$missingOperators = $operators | Where-Object {$destServer.JobServer.Operators.Name -notcontains $_}

			if ($missingOperators.Count -gt 0 -and $operators.Count -gt 0) {
                $missingOperator = ($operators | Sort-Object | Get-Unique) -join ", "
                $copyJobStatus.Status = "Skipped"
				$copyJobStatus
				Write-Message -Level Warning -Message "Operator(s) $($missingOperator) doesn't exist on destination. Skipping job [$jobname]"
				continue
			}

			if ($destJobs.name -contains $serverJob.name) {
                if ($force -eq $false) {
                    $copyJobStatus.Status = "Skipped"
					$copyJobStatus
                    Write-Message -Level Warning -Message "Job $jobName exists at destination. Use -Force to drop and migrate."
					continue
				}
				else {
					if ($Pscmdlet.ShouldProcess($destination, "Dropping job $jobName and recreating")) {
                        try {
                            Write-Message -Message "Dropping Job $jobName" -Level Verbose
                            $destServer.JobServer.Jobs[$jobName].Drop()
                        }
                        catch {
                            $copyJobStatus.Status = "Failed"
							$copyJobStatus
                            Stop-Function -Message "Issue dropping job. See error log under $((Get-DbaConfig -Name dbatoolslogpath).Value) for more details." -Target $jobName -InnerErrorRecord $_ -Continue
                        }
					}
				}
			}

			if ($Pscmdlet.ShouldProcess($destination, "Creating Job $jobName")) {
                try {
                    Write-Message -Message "Copying Job $jobName" -Level Verbose
                    $sql = $serverJob.Script() | Out-String
                    Write-Message -Message $sql -Level Debug
                    $destServer.Query($sql)
                }
                catch {
                    $copyJobStatus.Status = "Failed"
					$copyJobStatus
                    Stop-Function -Message "Issue copying job." -Target $jobName -InnerErrorRecord $_ -Continue
                }
			}

			if ($DisableOnDestination) {
				if ($Pscmdlet.ShouldProcess($destination, "Disabling $jobName")) {
					Write-Message -Message "Disabling $jobName on $destination" -Level Verbose
					$destServer.JobServer.Jobs.Refresh()
					$destServer.JobServer.Jobs[$job.name].IsEnabled = $False
					$destServer.JobServer.Jobs[$job.name].Alter()
				}
			}

            if ($DisableOnSource) {
                if ($Pscmdlet.ShouldProcess($source, "Disabling $jobName")) {
                    Write-Message -Message "Disabling $jobName on $source" -Level Verbose
                    $job.IsEnabled = $false
                    $job.Alter()
                }
            }
            $copyJobStatus.Status = "Successful"
            $copyJobStatus
		}
	}
	end {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlJob
	}
}
