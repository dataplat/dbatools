function Copy-DbaAgentJob {
    <#
    .SYNOPSIS
        Copy-DbaAgentJob migrates jobs from one SQL Server to another.

    .DESCRIPTION
        By default, all jobs are copied. The -Job parameter is auto-populated for command-line completion and can be used to copy only specific jobs.

        If the job already exists on the destination, it will be skipped unless -Force is used.

    .PARAMETER Source
        Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Job
        The job(s) to process. This list is auto-populated from the server. If unspecified, all jobs will be processed.

    .PARAMETER ExcludeJob
        The job(s) to exclude. This list is auto-populated from the server.

    .PARAMETER DisableOnSource
        If this switch is enabled, the job will be disabled on the source server.

    .PARAMETER DisableOnDestination
        If this switch is enabled, the newly migrated job will be disabled on the destination server.

     .PARAMETER InputObject
        Piped in jobs from Get-DbaAgentJob

        .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER Force
        If this switch is enabled, the Job will be dropped and recreated on Destination.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration, Agent, Job
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Copy-DbaAgentJob

    .EXAMPLE
        PS C:\> Copy-DbaAgentJob -Source sqlserver2014a -Destination sqlcluster

        Copies all jobs from sqlserver2014a to sqlcluster, using Windows credentials. If jobs with the same name exist on sqlcluster, they will be skipped.

    .EXAMPLE
        PS C:\> Copy-DbaAgentJob -Source sqlserver2014a -Destination sqlcluster -Job PSJob -SourceSqlCredential $cred -Force

        Copies a single job, the PSJob job from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If a job with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

    .EXAMPLE
        PS C:\> Copy-DbaAgentJob -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

        Shows what would happen if the command were executed using force.

    .EXAMPLE
        PS C:\> Get-DbaAgentJob -SqlInstance sqlserver2014a | Where-Object Category -eq "Report Server" | Copy-DbaAgentJob -Destination sqlserver2014b

        Copies all SSRS jobs (subscriptions) from AlwaysOn Primary SQL instance sqlserver2014a to AlwaysOn Secondary SQL instance sqlserver2014b
    #>
    [cmdletbinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [object[]]$Job,
        [object[]]$ExcludeJob,
        [switch]$DisableOnSource,
        [switch]$DisableOnDestination,
        [switch]$Force,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Agent.Job[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        if ($Source) {
            try {
                $InputObject = Get-DbaAgentJob -SqlInstance $Source -SqlCredential $SourceSqlCredential -Job $Job -ExcludeJob $ExcludeJob
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $Source" -Category ConnectionError -ErrorRecord $_ -Target $Source
                return
            }
        }
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-SqlInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $destinstance" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }
            $destJobs = $destServer.JobServer.Jobs

            foreach ($serverJob in $InputObject) {
                $jobName = $serverJob.Name
                $jobId = $serverJob.JobId
                $sourceserver = $serverJob.Parent.Parent

                $copyJobStatus = [pscustomobject]@{
                    SourceServer      = $sourceserver.Name
                    DestinationServer = $destServer.Name
                    Name              = $jobName
                    Type              = "Agent Job"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [DbaDateTime](Get-Date)
                }

                if ($Job -and $jobName -notin $Job -or $jobName -in $ExcludeJob) {
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
                    if ($Pscmdlet.ShouldProcess($destinstance, "Job [$jobName] is associated with Maintenance Plan: $MaintenancePlanNam")) {
                        $copyJobStatus.Status = "Skipped"
                        $copyJobStatus.Notes = "Job is associated with maintenance plan"
                        $copyJobStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Job [$jobName] is associated with Maintenance Plan: $MaintenancePlanName"
                    }
                    continue
                }

                $dbNames = ($serverJob.JobSteps | Where-Object { $_.SubSystem -ne 'ActiveScripting' }).DatabaseName | Where-Object { $_.Length -gt 0 }
                $missingDb = $dbNames | Where-Object { $destServer.Databases.Name -notcontains $_ }

                if ($missingDb.Count -gt 0 -and $dbNames.Count -gt 0) {
                    if ($Pscmdlet.ShouldProcess($destinstance, "Database(s) $missingDb doesn't exist on destination. Skipping job [$jobName].")) {
                        $missingDb = ($missingDb | Sort-Object | Get-Unique) -join ", "
                        $copyJobStatus.Status = "Skipped"
                        $copyJobStatus.Notes = "Job is dependent on database: $missingDb"
                        $copyJobStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Database(s) $missingDb doesn't exist on destination. Skipping job [$jobName]."
                    }
                    continue
                }

                $missingLogin = $serverJob.OwnerLoginName | Where-Object { $destServer.Logins.Name -notcontains $_ }

                if ($missingLogin.Count -gt 0) {
                    if ($force -eq $false) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Login(s) $missingLogin doesn't exist on destination. Use -Force to set owner to [sa]. Skipping job [$jobName].")) {
                            $missingLogin = ($missingLogin | Sort-Object | Get-Unique) -join ", "
                            $copyJobStatus.Status = "Skipped"
                            $copyJobStatus.Notes = "Job is dependent on login $missingLogin"
                            $copyJobStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Login(s) $missingLogin doesn't exist on destination. Use -Force to set owner to [sa]. Skipping job [$jobName]."
                        }
                        continue
                    }
                }

                $proxyNames = ($serverJob.JobSteps | Where-Object ProxyName).ProxyName
                $missingProxy = $proxyNames | Where-Object { $destServer.JobServer.ProxyAccounts.Name -notcontains $_ }

                if ($missingProxy -and $proxyNames) {
                    if ($Pscmdlet.ShouldProcess($destinstance, "Proxy Account(s) $missingProxy doesn't exist on destination. Skipping job [$jobName].")) {
                        $missingProxy = ($missingProxy | Sort-Object | Get-Unique) -join ", "
                        $copyJobStatus.Status = "Skipped"
                        $copyJobStatus.Notes = "Job is dependent on proxy $missingProxy"
                        $copyJobStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Proxy Account(s) $missingProxy doesn't exist on destination. Skipping job [$jobName]."
                    }
                    continue
                }

                $operators = $serverJob.OperatorToEmail, $serverJob.OperatorToNetSend, $serverJob.OperatorToPage | Where-Object { $_.Length -gt 0 }
                $missingOperators = $operators | Where-Object { $destServer.JobServer.Operators.Name -notcontains $_ }

                if ($missingOperators.Count -gt 0 -and $operators.Count -gt 0) {
                    if ($Pscmdlet.ShouldProcess($destinstance, "Operator(s) $($missingOperator) doesn't exist on destination. Skipping job [$jobName]")) {
                        $missingOperator = ($operators | Sort-Object | Get-Unique) -join ", "
                        $copyJobStatus.Status = "Skipped"
                        $copyJobStatus.Notes = "Job is dependent on operator $missingOperator"
                        $copyJobStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Operator(s) $($missingOperator) doesn't exist on destination. Skipping job [$jobName]"
                    }
                    continue
                }

                if ($destJobs.name -contains $serverJob.name) {
                    if ($force -eq $false) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Job $jobName exists at destination. Use -Force to drop and migrate.")) {
                            $copyJobStatus.Status = "Skipped"
                            $copyJobStatus.Notes = "Already exists on destination"
                            $copyJobStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Job $jobName exists at destination. Use -Force to drop and migrate."
                        }
                        continue
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Dropping job $jobName and recreating")) {
                            try {
                                Write-Message -Message "Dropping Job $jobName" -Level Verbose
                                $destServer.JobServer.Jobs[$jobName].Drop()
                            } catch {
                                $copyJobStatus.Status = "Failed"
                                $copyJobStatus.Notes = (Get-ErrorMessage -Record $_).Message
                                $copyJobStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Stop-Function -Message "Issue dropping job" -Target $jobName -ErrorRecord $_ -Continue
                            }
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Creating Job $jobName")) {
                    try {
                        Write-Message -Message "Copying Job $jobName" -Level Verbose
                        $sql = $serverJob.Script() | Out-String

                        if ($missingLogin.Count -gt 0 -and $force) {
                            $saLogin = Get-SqlSaLogin -SqlInstance $destServer
                            $sql = $sql -replace [Regex]::Escape("@owner_login_name=N'$missingLogin'"), [Regex]::Escape("@owner_login_name=N'$saLogin'")
                        }

                        $sql = $sql -replace [Regex]::Escape("@server=N'$($sourceserver.DomainInstanceName)'"), [Regex]::Escape("@server=N'$($destServer.DomainInstanceName)'")

                        Write-Message -Message $sql -Level Debug
                        $destServer.Query($sql)

                        $destServer.JobServer.Jobs.Refresh()
                        $destServer.JobServer.Jobs[$serverJob.name].IsEnabled = $sourceServer.JobServer.Jobs[$serverJob.name].IsEnabled
                        $destServer.JobServer.Jobs[$serverJob.name].Alter()
                    } catch {
                        $copyJobStatus.Status = "Failed"
                        $copyJobStatus.Notes = (Get-ErrorMessage -Record $_)
                        $copyJobStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Stop-Function -Message "Issue copying job" -Target $jobName -ErrorRecord $_ -Continue
                    }
                }

                if ($DisableOnDestination) {
                    if ($Pscmdlet.ShouldProcess($destinstance, "Disabling $jobName")) {
                        Write-Message -Message "Disabling $jobName on $destinstance" -Level Verbose
                        $destServer.JobServer.Jobs[$serverJob.name].IsEnabled = $False
                        $destServer.JobServer.Jobs[$serverJob.name].Alter()
                    }
                }

                if ($DisableOnSource) {
                    if ($Pscmdlet.ShouldProcess($source, "Disabling $jobName")) {
                        Write-Message -Message "Disabling $jobName on $source" -Level Verbose
                        $serverJob.IsEnabled = $false
                        $serverJob.Alter()
                    }
                }
                if ($Pscmdlet.ShouldProcess($destinstance, "Reporting status of migration for $jobname")) {
                    $copyJobStatus.Status = "Successful"
                    $copyJobStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
            }
        }
    }
}