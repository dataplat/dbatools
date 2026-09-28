function Copy-DbaAgentJob {
    <#
    .SYNOPSIS
        Migrates SQL Server Agent jobs between instances with dependency validation

    .DESCRIPTION
        Copies SQL Server Agent jobs from one instance to another while automatically validating all dependencies including databases, logins, proxy accounts, and operators. This eliminates the manual process of checking prerequisites before moving jobs during migrations, disaster recovery, or environment promotions.

        The function intelligently skips jobs associated with maintenance plans and provides detailed validation messages for any missing dependencies. By default, existing jobs are preserved unless -Force is specified to overwrite them.

    .PARAMETER Source
        Source SQL Server instance containing the jobs to copy. You must have sysadmin access and server version must be SQL Server version 2000 or higher.
        Use this when copying jobs from a specific instance rather than piping job objects with InputObject.

    .PARAMETER SourceSqlCredential
        Alternative credentials for connecting to the source SQL Server instance. Accepts PowerShell credentials (Get-Credential).
        Use this when the source server requires different authentication than your current Windows session, such as SQL authentication or cross-domain scenarios.
        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

    .PARAMETER Destination
        Destination SQL Server instance(s) where jobs will be created. You must have sysadmin access and the server must be SQL Server 2000 or higher.
        Supports multiple destinations to copy jobs to multiple servers simultaneously during migrations or DR setup.

    .PARAMETER DestinationSqlCredential
        Alternative credentials for connecting to the destination SQL Server instance. Accepts PowerShell credentials (Get-Credential).
        Use this when the destination server requires different authentication than your current Windows session, such as SQL authentication or cross-domain scenarios.
        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

    .PARAMETER Job
        Specifies which SQL Agent jobs to copy by name. Accepts wildcards and multiple job names.
        Use this to copy specific jobs instead of all jobs, such as during selective migrations or when testing job deployments.
        If unspecified, all jobs will be processed.

    .PARAMETER ExcludeJob
        Specifies which SQL Agent jobs to skip during the copy operation. Accepts wildcards and multiple job names.
        Use this to exclude specific jobs from bulk operations, such as skipping environment-specific jobs or maintenance tasks that shouldn't be migrated.

    .PARAMETER DisableOnSource
        Disables the job on the source server after successfully copying it to the destination.
        Use this during server migrations or failover scenarios where you want to prevent the job from running on the old server while it runs on the new one.

    .PARAMETER DisableOnDestination
        Creates the job on the destination server but leaves it disabled.
        Use this when deploying jobs to test environments or when you need to review and modify job steps before enabling them in the new environment.

    .PARAMETER InputObject
        Accepts SQL Agent job objects from the pipeline, typically from Get-DbaAgentJob.
        Use this to copy pre-filtered jobs or when combining with other job management cmdlets for complex workflows.

        .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER Force
        Overwrites existing jobs on the destination server and automatically sets missing job owners to the 'sa' login.
        Use this when you need to replace existing jobs or when source job owners don't exist on the destination server during migrations.

    .PARAMETER NewName
        The new name for the job on the destination server.
        Required when source and destination are the same server instance. Use this to create a copy of a job under a different name on the same or a different server.
        Cannot be used when copying multiple jobs simultaneously.

    .PARAMETER UseLastModified
        Compares the job definition on source and destination - job properties, enabled state, steps and schedules - and only copies when they actually differ.
        When the definitions differ, the direction is decided by each job's effective last-modified time: the later of msdb.dbo.sysjobs.date_modified and
        the date_modified of every schedule attached to the job (sp_update_schedule only touches sysschedules, not the job row). Both values are normalised
        to UTC using each server's own time zone offset so instances in different time zones compare correctly:
        - Job doesn't exist on destination: creates it
        - Definitions identical: skips, regardless of timestamps
        - Only the enabled state differs and source is not older: updates the flag in place without recreating the job
        - Definitions differ and source is newer (or equal): drops and recreates the job
        - Definitions differ and destination is newer: skips with a warning
        Job IDs, timestamps, version numbers, schedule IDs/UIDs and run history are excluded from the comparison, so jobs that are
        identical but were created independently (for example on AG replicas) are not needlessly recreated.
        Use this for incremental synchronization scenarios where you want to keep jobs up-to-date without unconditionally overwriting them.

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

    .OUTPUTS
        MigrationObject (PSCustomObject)

        Returns one object per job processed, regardless of whether it was successfully copied, skipped, or failed. This provides a consistent record of all job migration operations.

        Properties:
        - DateTime: Timestamp when the operation was attempted (DbaDateTime type)
        - SourceServer: The name of the source SQL Server instance
        - DestinationServer: The name of the destination SQL Server instance
        - Name: The name of the SQL Agent job
        - Type: Always "Agent Job" indicating the type of object being migrated
        - Status: The outcome of the operation - "Successful", "Skipped", or "Failed"
        - Notes: Descriptive message explaining the status (reason for skip, error details, etc.)

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

    .EXAMPLE
        PS C:\> Copy-DbaAgentJob -Source sqlserver2014a -Destination sqlserver2014b -UseLastModified

        Copies jobs from sqlserver2014a to sqlserver2014b, creating jobs that don't exist and recreating only those whose definition differs and where the source is not older. Jobs with an identical definition are skipped even when their date_modified values differ. A job that differs only in its enabled state has the flag updated in place.

    .EXAMPLE
        PS C:\> Copy-DbaAgentJob -Source sqlserver2014a -Destination sqlserver2014a -Job "OriginalJob" -NewName "JobCopy"

        Copies the job "OriginalJob" on sqlserver2014a to the same server as "JobCopy". When source and destination are the same instance, -NewName is required.
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
        [string]$NewName,
        [switch]$UseLastModified,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Agent.Job[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        if ($Source) {
            try {
                $splatGetJob = @{
                    SqlInstance   = $Source
                    SqlCredential = $SourceSqlCredential
                }
                if (Test-Bound 'Job') {
                    $splatGetJob['Job'] = $Job
                }
                if (Test-Bound 'ExcludeJob') {
                    $splatGetJob['ExcludeJob'] = $ExcludeJob
                }
                $InputObject = Get-DbaAgentJob @splatGetJob
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $Source" -Category ConnectionError -ErrorRecord $_ -Target $Source
                return
            }
        }
        if ((Test-Bound "NewName") -and $InputObject.Count -gt 1) {
            Stop-Function -Message "Cannot use -NewName when copying multiple jobs"
            return
        }
        if ($Force) { $ConfirmPreference = 'none' }

        # A job's effective last-modified must include its schedules: sp_update_schedule
        # only touches sysschedules.date_modified, never sysjobs.date_modified.
        # Returned already normalised to UTC using the server's own offset.
        $sqlLastModified = "
SELECT DATEADD(MINUTE, -DATEPART(TZOFFSET, SYSDATETIMEOFFSET()), MAX(x.date_modified)) AS LastModifiedUtc
FROM (
    SELECT j.date_modified
    FROM msdb.dbo.sysjobs AS j
    WHERE j.job_id = @jobId
    UNION ALL
    SELECT s.date_modified
    FROM msdb.dbo.sysjobschedules AS js
    INNER JOIN msdb.dbo.sysschedules AS s ON s.schedule_id = js.schedule_id
    WHERE js.job_id = @jobId
) AS x"

        # Destinations whose job collection has been refreshed during this invocation (-UseLastModified only)
        $refreshedDestinations = @{}
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }
            if ($UseLastModified -and -not $refreshedDestinations.ContainsKey($destServer.Name)) {
                # dbatools reuses server objects within a session; refresh once so new/dropped jobs are seen on repeat runs
                $destServer.JobServer.Jobs.Refresh()
                $refreshedDestinations[$destServer.Name] = $true
            }
            $destJobs = $destServer.JobServer.Jobs

            foreach ($serverJob in $InputObject) {
                $jobName = $serverJob.Name
                $jobId = $serverJob.JobId
                $sourceserver = $serverJob.Parent.Parent
                $alertsReferencingJob = @()
                $destJobName = if (Test-Bound "NewName") { $NewName } else { $jobName }

                if ($sourceserver.Name -eq $destServer.Name -and -not (Test-Bound "NewName")) {
                    Stop-Function -Message "Source and destination are the same server ($($destServer.Name)). Use -NewName to copy job [$jobName] with a different name on the same server." -Continue
                }

                $copyJobStatus = [PSCustomObject]@{
                    SourceServer      = $sourceserver.Name
                    DestinationServer = $destServer.Name
                    Name              = $destJobName
                    Type              = "Agent Job"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [DbaDateTime](Get-Date)
                }

                if ((Test-Bound 'Job') -and $jobName -notin $Job) {
                    Write-Message -Level Verbose -Message "Job [$jobName] filtered. Skipping."
                    continue
                }
                if ((Test-Bound 'ExcludeJob') -and $jobName -in $ExcludeJob) {
                    Write-Message -Level Verbose -Message "Job [$jobName] excluded. Skipping."
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
                    if ($Pscmdlet.ShouldProcess($destinstance, "Job [$jobName] is associated with Maintenance Plan: $MaintenancePlanName")) {
                        $copyJobStatus.Status = "Skipped"
                        $copyJobStatus.Notes = "Job is associated with maintenance plan"
                        $copyJobStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Job [$jobName] is associated with Maintenance Plan: $MaintenancePlanName"
                    }
                    continue
                }

                $dbNames = ($serverJob.JobSteps | Where-Object { $_.SubSystem -notin 'ActiveScripting', 'AnalysisQuery', 'AnalysisCommand' }).DatabaseName | Where-Object { $_.Length -gt 0 }
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
                    # Secondary check: verify if the owner has access via AD group membership
                    $missingLogin = $missingLogin | Where-Object {
                        $ownerName = $_
                        try {
                            $adInfo = $destServer.EnumWindowsUserInfo($ownerName)
                            if ($adInfo.Rows.Count -gt 0) {
                                Write-Message -Level Verbose -Message "Login $ownerName not found as a direct login but has access via AD group membership on destination. Proceeding."
                                $false
                            } else {
                                $true
                            }
                        } catch {
                            Write-Message -Level Verbose -Message "Could not verify AD group membership for $ownerName on destination: $PSItem"
                            $true
                        }
                    }
                }

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
                    $missingOperator = ($missingOperators | Sort-Object | Get-Unique) -join ", "
                    if ($Pscmdlet.ShouldProcess($destinstance, "Operator(s) $($missingOperator) doesn't exist on destination. Skipping job [$jobName]")) {
                        $copyJobStatus.Status = "Skipped"
                        $copyJobStatus.Notes = "Job is dependent on operator $missingOperator"
                        $copyJobStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Operator(s) $($missingOperator) doesn't exist on destination. Skipping job [$jobName]"
                    }
                    continue
                }

                if ($destJobs.name -contains $destJobName) {
                    if ($UseLastModified) {
                        try {
                            $destJob = $destServer.JobServer.Jobs[$destJobName]

                            # SMO caches and dbatools reuses server objects within a session, so refresh
                            # both jobs and their child collections before comparing and before Script()
                            $serverJob.Refresh()
                            $serverJob.JobSteps.Refresh($true)
                            $serverJob.JobSchedules.Refresh($true)
                            $destJob.Refresh()
                            $destJob.JobSteps.Refresh($true)
                            $destJob.JobSchedules.Refresh($true)

                            # Compare the definitions first. Timestamps only decide direction when the
                            # definitions actually differ; on their own they are never a reason to copy.
                            $splatFingerprint = @{ Job = $serverJob }
                            if ($missingLogin.Count -gt 0) {
                                # -Force remaps a missing owner to sa on the destination, so compare against that
                                $splatFingerprint['OwnerLoginName'] = Get-SqlSaLogin -SqlInstance $destServer
                            }
                            if ($DisableOnDestination) {
                                # desired destination state is disabled regardless of the source
                                $splatFingerprint['IsEnabled'] = $false
                            }
                            $sourcePrint = Get-AgentJobFingerprint @splatFingerprint
                            $destPrint = Get-AgentJobFingerprint -Job $destJob

                            if ($sourcePrint.Hash -eq $destPrint.Hash) {
                                if ($Pscmdlet.ShouldProcess($destinstance, "Job $destJobName has an identical definition on source and destination. Skipping.")) {
                                    $copyJobStatus.Status = "Skipped"
                                    $copyJobStatus.Notes = "Job definition is identical on source and destination"
                                    $copyJobStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                    Write-Message -Level Verbose -Message "Job $destJobName has an identical definition on source and destination. Skipping."
                                }
                                continue
                            }

                            $changed = @()
                            if ($sourcePrint.Job -cne $destPrint.Job) { $changed += "job properties" }
                            if ($sourcePrint.Enabled -cne $destPrint.Enabled) { $changed += "enabled state" }
                            if ($sourcePrint.Steps -cne $destPrint.Steps) { $changed += "steps" }
                            if ($sourcePrint.Schedules -cne $destPrint.Schedules) { $changed += "schedules" }
                            $changedText = $changed -join ", "

                            # Effective last-modified (job row + attached schedules), already in UTC
                            $sourceDate = (Invoke-DbaQuery -SqlInstance $sourceserver -Database msdb -Query $sqlLastModified -SqlParameter @{ jobId = $serverJob.JobID }).LastModifiedUtc
                            $destDate = (Invoke-DbaQuery -SqlInstance $destServer -Database msdb -Query $sqlLastModified -SqlParameter @{ jobId = $destJob.JobID }).LastModifiedUtc

                            if ($destDate -gt $sourceDate) {
                                if ($Pscmdlet.ShouldProcess($destinstance, "Job $destJobName differs ($changedText) but is newer on destination. Skipping.")) {
                                    $copyJobStatus.Status = "Skipped"
                                    $copyJobStatus.Notes = "Definition differs ($changedText) but destination job is newer than source (dest: $destDate UTC, source: $sourceDate UTC)"
                                    $copyJobStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                    Write-Message -Level Warning -Message "Job $destJobName differs from source ($changedText) but is newer on destination ($destDate UTC) than source ($sourceDate UTC). Skipping. Use -Force without -UseLastModified to overwrite."
                                }
                                continue
                            }

                            # Only the enabled flag differs: align it in place instead of dropping and recreating
                            if ($changed.Count -eq 1 -and $changed[0] -eq "enabled state") {
                                $targetEnabled = if ($DisableOnDestination) { $false } else { $serverJob.IsEnabled }
                                if ($Pscmdlet.ShouldProcess($destinstance, "Job $destJobName differs only in enabled state. Setting IsEnabled to $targetEnabled.")) {
                                    try {
                                        $destJob.IsEnabled = $targetEnabled
                                        $destJob.Alter()
                                        if ($DisableOnSource) {
                                            Write-Message -Message "Disabling $jobName on $($sourceserver.Name)" -Level Verbose
                                            $serverJob.IsEnabled = $false
                                            $serverJob.Alter()
                                        }
                                        $copyJobStatus.Status = "Successful"
                                        $copyJobStatus.Notes = "Enabled state set to $targetEnabled in place; definition otherwise identical, job not recreated"
                                        $copyJobStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                        Write-Message -Level Verbose -Message "Job $destJobName differs only in enabled state. Set IsEnabled to $targetEnabled without recreating."
                                    } catch {
                                        $copyJobStatus.Status = "Failed"
                                        $copyJobStatus.Notes = (Get-ErrorMessage -Record $_).Message
                                        $copyJobStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                        Write-Message -Level Verbose -Message "Issue updating enabled state for job $destJobName on $destinstance | $PSItem"
                                    }
                                }
                                continue
                            }

                            # Definition differs and source is newer (or the timestamps tie): source wins
                            if ($Pscmdlet.ShouldProcess($destinstance, "Job $destJobName differs ($changedText) and source is not older (source: $sourceDate UTC, dest: $destDate UTC). Dropping and recreating.")) {
                                try {
                                    Write-Message -Message "Job $destJobName differs from source ($changedText). Dropping and recreating." -Level Verbose
                                    # Before dropping, save which alerts reference this job
                                    $splatAlertsForJob = @{
                                        SqlInstance  = $destServer
                                        Database     = "msdb"
                                        Query        = "SELECT name FROM dbo.sysalerts WHERE job_id = (SELECT job_id FROM dbo.sysjobs WHERE name = @jobName)"
                                        SqlParameter = @{ jobName = $destJobName }
                                    }
                                    $alertsReferencingJob = (Invoke-DbaQuery @splatAlertsForJob).name
                                    Write-Message -Message "Found $($alertsReferencingJob.Count) alert(s) referencing job $destJobName" -Level Verbose
                                    $destJob.Drop()
                                } catch {
                                    $copyJobStatus.Status = "Failed"
                                    $copyJobStatus.Notes = (Get-ErrorMessage -Record $_).Message
                                    $copyJobStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                    Write-Message -Level Verbose -Message "Issue dropping job $jobName on $destinstance | $PSItem"
                                    continue
                                }
                            }
                        } catch {
                            Write-Message -Level Warning -Message "Error comparing job definitions for $jobName | $PSItem"
                            if ($force -eq $false) {
                                if ($Pscmdlet.ShouldProcess($destinstance, "Job $jobName exists at destination. Use -Force to drop and migrate.")) {
                                    $copyJobStatus.Status = "Skipped"
                                    $copyJobStatus.Notes = "Already exists on destination"
                                    $copyJobStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                    Write-Message -Level Verbose -Message "Job $jobName exists at destination. Use -Force to drop and migrate."
                                }
                                continue
                            }
                        }
                    } elseif ($force -eq $false) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Job $jobName exists at destination. Use -Force to drop and migrate.")) {
                            $copyJobStatus.Status = "Skipped"
                            $copyJobStatus.Notes = "Already exists on destination"
                            $copyJobStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Job $jobName exists at destination. Use -Force to drop and migrate."
                        }
                        continue
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Dropping job $destJobName and recreating")) {
                            try {
                                Write-Message -Message "Dropping Job $destJobName" -Level Verbose
                                # Before dropping, save which alerts reference this job
                                $splatAlertsForJob = @{
                                    SqlInstance  = $destServer
                                    Database     = "msdb"
                                    Query        = "SELECT name FROM dbo.sysalerts WHERE job_id = (SELECT job_id FROM dbo.sysjobs WHERE name = @jobName)"
                                    SqlParameter = @{ jobName = $destJobName }
                                }
                                $alertsReferencingJob = (Invoke-DbaQuery @splatAlertsForJob).name
                                Write-Message -Message "Found $($alertsReferencingJob.Count) alert(s) referencing job $destJobName" -Level Verbose
                                $destServer.JobServer.Jobs[$destJobName].Drop()
                            } catch {
                                $copyJobStatus.Status = "Failed"
                                $copyJobStatus.Notes = (Get-ErrorMessage -Record $_).Message
                                $copyJobStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Write-Message -Level Verbose -Message "Issue dropping job $jobName on $destinstance | $PSItem"
                                continue
                            }
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Creating Job $destJobName")) {
                    try {
                        Write-Message -Message "Copying Job $jobName as $destJobName" -Level Verbose
                        $sql = $serverJob.Script() | Out-String

                        if ($missingLogin.Count -gt 0 -and $force) {
                            $saLogin = Get-SqlSaLogin -SqlInstance $destServer
                            $sql = $sql -replace [Regex]::Escape("@owner_login_name=N'$missingLogin'"), "@owner_login_name=N'$saLogin'"
                        }

                        $sql = $sql -replace [Regex]::Escape("@server=N'$($sourceserver.DomainInstanceName)'"), "@server=N'$($destServer.DomainInstanceName)'"

                        if (Test-Bound "NewName") {
                            $sql = $sql -replace [Regex]::Escape("@job_name=N'$jobName'"), "@job_name=N'$NewName'"
                        }

                        Write-Message -Message $sql -Level Debug
                        $destServer.Query($sql)

                        $destServer.JobServer.Jobs.Refresh()
                        $destServer.JobServer.Jobs[$destJobName].IsEnabled = $sourceServer.JobServer.Jobs[$serverJob.name].IsEnabled
                        $destServer.JobServer.Jobs[$destJobName].Alter()

                        # Restore alert-to-job links if job was dropped and recreated
                        if ($alertsReferencingJob -and $alertsReferencingJob.Count -gt 0) {
                            Write-Message -Message "Restoring alert-to-job links for $jobName" -Level Verbose
                            foreach ($alertName in $alertsReferencingJob) {
                                try {
                                    $splatUpdateAlert = @{
                                        SqlInstance  = $destServer
                                        Database     = "msdb"
                                        Query        = "EXEC dbo.sp_update_alert @name = @alertName, @job_name = @jobName"
                                        SqlParameter = @{
                                            alertName = $alertName
                                            jobName   = $jobName
                                        }
                                    }
                                    $null = Invoke-DbaQuery @splatUpdateAlert
                                    Write-Message -Message "Restored link between alert [$alertName] and job [$jobName]" -Level Verbose
                                } catch {
                                    Write-Message -Level Warning -Message "Failed to restore alert link for [$alertName] to job [$jobName] | $PSItem"
                                }
                            }
                        }

                        $copyJobStatus.Status = "Successful"
                        $copyJobStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyJobStatus.Status = "Failed"
                        $copyJobStatus.Notes = (Get-ErrorMessage -Record $_)
                        $copyJobStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Issue copying job $jobName on $destinstance | $PSItem"
                        continue
                    }
                }

                if ($DisableOnDestination) {
                    if ($Pscmdlet.ShouldProcess($destinstance, "Disabling $destJobName")) {
                        Write-Message -Message "Disabling $destJobName on $destinstance" -Level Verbose
                        $destServer.JobServer.Jobs[$destJobName].IsEnabled = $False
                        $destServer.JobServer.Jobs[$destJobName].Alter()
                    }
                }

                if ($DisableOnSource) {
                    if ($Pscmdlet.ShouldProcess($source, "Disabling $jobName")) {
                        Write-Message -Message "Disabling $jobName on $source" -Level Verbose
                        $serverJob.IsEnabled = $false
                        $serverJob.Alter()
                    }
                }
            }
        }
    }
}
