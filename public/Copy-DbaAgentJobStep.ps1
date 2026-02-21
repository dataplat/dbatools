function Copy-DbaAgentJobStep {
    <#
    .SYNOPSIS
        Copies job steps from one SQL Server Agent job to another, preserving job history by synchronizing steps without dropping the job itself.

    .DESCRIPTION
        Synchronizes SQL Server Agent job steps between instances by copying step definitions from source jobs to destination jobs. Unlike Copy-DbaAgentJob with -Force, this command preserves job execution history because it only drops and recreates individual steps rather than the entire job. This is essential for maintaining historical job execution data in Always On Availability Group scenarios, disaster recovery environments, or when deploying step modifications across multiple servers.

        The function removes all existing steps from the destination job before copying source steps, ensuring a clean synchronization. Job metadata like ownership, schedules, and alerts remain unchanged on the destination.

    .PARAMETER Source
        Source SQL Server instance containing the jobs with steps to copy. You must have sysadmin access and server version must be SQL Server 2000 or higher.
        Use this when copying job steps from a specific instance rather than piping job objects with InputObject.

    .PARAMETER SourceSqlCredential
        Alternative credentials for connecting to the source SQL Server instance. Accepts PowerShell credentials (Get-Credential).
        Use this when the source server requires different authentication than your current Windows session, such as SQL authentication or cross-domain scenarios.
        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

    .PARAMETER Destination
        Destination SQL Server instance(s) where job steps will be synchronized. You must have sysadmin access and the server must be SQL Server 2000 or higher.
        Supports multiple destinations to copy job steps to multiple servers simultaneously, such as syncing all AG replicas or DR servers.

    .PARAMETER DestinationSqlCredential
        Alternative credentials for connecting to the destination SQL Server instance. Accepts PowerShell credentials (Get-Credential).
        Use this when the destination server requires different authentication than your current Windows session, such as SQL authentication or cross-domain scenarios.
        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

    .PARAMETER Job
        Specifies which SQL Agent jobs to process by name. Accepts wildcards and multiple job names.
        Use this to synchronize steps for specific jobs, such as copying modified steps from a primary AG replica to secondary replicas.
        If unspecified, all jobs will be processed.

    .PARAMETER ExcludeJob
        Specifies which SQL Agent jobs to skip during the copy operation. Accepts wildcards and multiple job names.
        Use this to exclude specific jobs from bulk operations, such as skipping environment-specific jobs that shouldn't be synchronized.

    .PARAMETER Step
        Specifies which job steps to copy by name. If not specified, all steps are copied.
        Use this to synchronize specific steps rather than all steps from a job.

    .PARAMETER InputObject
        Accepts SQL Agent job objects from the pipeline, typically from Get-DbaAgentJob.
        Use this to copy steps for pre-filtered jobs or when combining with other job management cmdlets for complex workflows.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration, Agent, Job
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Copy-DbaAgentJobStep

    .OUTPUTS
        PSCustomObject (MigrationObject)

        Returns one object per job processed with the following properties:

        Default display properties (via Select-DefaultView):
        - DateTime: The timestamp when the job step copy operation was executed
        - SourceServer: The name of the source SQL Server instance
        - DestinationServer: The name of the destination SQL Server instance
        - Name: The name of the SQL Agent job
        - Type: The operation type, always "Agent Job Steps"
        - Status: The status of the operation - "Successful" if steps were copied, "Skipped" if the destination job does not exist, or "Failed" if an error occurred
        - Notes: Additional information about the operation, such as the number of steps synchronized or reason for skipping/failure

        All properties are always available on the returned object even though Select-DefaultView limits the display.

    .EXAMPLE
        PS C:\> Copy-DbaAgentJobStep -Source PrimaryAG -Destination SecondaryAG1, SecondaryAG2 -Job "MaintenanceJob"

        Copies all job steps from the "MaintenanceJob" on PrimaryAG to the same job on SecondaryAG1 and SecondaryAG2, preserving job history on the destination servers.

    .EXAMPLE
        PS C:\> Get-DbaAgentJob -SqlInstance PrimaryAG -Job "BackupJob" | Copy-DbaAgentJobStep -Destination SecondaryAG1

        Retrieves the BackupJob from PrimaryAG and synchronizes its steps to the same job on SecondaryAG1 using pipeline input.

    .EXAMPLE
        PS C:\> Copy-DbaAgentJobStep -Source sqlserver2014a -Destination sqlcluster -Job "DataETL" -SourceSqlCredential $cred

        Copies job steps for the "DataETL" job from sqlserver2014a to sqlcluster, using SQL credentials for the source server and Windows credentials for the destination.

    .EXAMPLE
        PS C:\> Copy-DbaAgentJobStep -Source Primary -Destination Replica1, Replica2, Replica3

        Synchronizes all job steps from Primary to multiple AG replicas, ensuring all replicas have identical job step definitions while preserving their individual job execution histories.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [object[]]$Job,
        [object[]]$ExcludeJob,
        [string[]]$Step,
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
                if (Test-Bound "Job") {
                    $splatGetJob["Job"] = $Job
                }
                if (Test-Bound "ExcludeJob") {
                    $splatGetJob["ExcludeJob"] = $ExcludeJob
                }
                $InputObject = Get-DbaAgentJob @splatGetJob
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $Source" -Category ConnectionError -ErrorRecord $_ -Target $Source
                return
            }
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }
            $destJobs = $destServer.JobServer.Jobs

            foreach ($sourceJob in $InputObject) {
                $jobName = $sourceJob.Name
                $sourceserver = $sourceJob.Parent.Parent

                $copyJobStepStatus = [PSCustomObject]@{
                    SourceServer      = $sourceserver.Name
                    DestinationServer = $destServer.Name
                    Name              = $jobName
                    Type              = "Agent Job Steps"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [DbaDateTime](Get-Date)
                }

                if ((Test-Bound "Job") -and $jobName -notin $Job) {
                    Write-Message -Level Verbose -Message "Job [$jobName] filtered. Skipping."
                    continue
                }
                if ((Test-Bound "ExcludeJob") -and $jobName -in $ExcludeJob) {
                    Write-Message -Level Verbose -Message "Job [$jobName] excluded. Skipping."
                    continue
                }
                Write-Message -Message "Working on job: $jobName" -Level Verbose

                if ($destJobs.name -notcontains $sourceJob.name) {
                    if ($Pscmdlet.ShouldProcess($destinstance, "Job $jobName does not exist on destination. Skipping step synchronization.")) {
                        $copyJobStepStatus.Status = "Skipped"
                        $copyJobStepStatus.Notes = "Job does not exist on destination. Use Copy-DbaAgentJob to create it first."
                        $copyJobStepStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Warning -Message "Job $jobName does not exist on destination $destinstance. Use Copy-DbaAgentJob to create it first."
                    }
                    continue
                }

                # Filter source steps if Step parameter is specified
                $sourceSteps = $sourceJob.JobSteps
                if (Test-Bound "Step") {
                    $sourceSteps = $sourceSteps | Where-Object Name -in $Step
                    if (-not $sourceSteps) {
                        Write-Message -Level Warning -Message "No matching steps found in job $jobName for specified step names: $($Step -join ', ')"
                        continue
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Synchronizing steps for job $jobName")) {
                    try {
                        $destJob = $destServer.JobServer.Jobs[$jobName]

                        # Remove existing steps - copy to array first to avoid collection modification during enumeration
                        $stepsToRemove = @($destJob.JobSteps | ForEach-Object { $_ })
                        if (Test-Bound "Step") {
                            $stepsToRemove = $stepsToRemove | Where-Object Name -in $Step
                        }

                        Write-Message -Message "Removing $($stepsToRemove.Count) existing step(s) from $jobName on $destinstance" -Level Verbose
                        foreach ($stepToRemove in $stepsToRemove) {
                            Write-Message -Message "Removing step $($stepToRemove.Name) from $jobName on $destinstance" -Level Verbose
                            $stepToRemove.Drop()
                        }
                        $destJob.JobSteps.Refresh()

                        Write-Message -Message "Copying $($sourceSteps.Count) step(s) from $jobName to $destinstance" -Level Verbose
                        foreach ($sourceStep in $sourceSteps) {
                            Write-Message -Message "Creating step $($sourceStep.Name) in $jobName on $destinstance" -Level Verbose
                            $sql = $sourceStep.Script() | Out-String
                            # Replace @job_id with @job_name since the destination job has a different GUID.
                            # Allow optional whitespace around = to handle different SMO script formats across SQL Server versions.
                            $sql = $sql -replace "@job_id\s*=\s*N'[0-9a-fA-F\-]+'", "@job_name=N'$($jobName -replace "'", "''")'"
                            Write-Message -Message $sql -Level Debug
                            $destServer.Query($sql)
                        }

                        $destJob.JobSteps.Refresh()
                        $copyJobStepStatus.Status = "Successful"
                        $copyJobStepStatus.Notes = "Synchronized $($sourceSteps.Count) job step(s)"
                        $copyJobStepStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyJobStepStatus.Status = "Failed"
                        $copyJobStepStatus.Notes = (Get-ErrorMessage -Record $_)
                        $copyJobStepStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Stop-Function -Message "Failed to synchronize steps for job $jobName on $destinstance" -ErrorRecord $_ -Target $destinstance -Continue
                    }
                }
            }
        }
    }
}
