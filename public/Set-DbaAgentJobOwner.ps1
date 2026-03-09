function Set-DbaAgentJobOwner {
    <#
    .SYNOPSIS
        Updates SQL Server Agent job ownership to ensure jobs are owned by a specific login

    .DESCRIPTION
        This function standardizes SQL Agent job ownership by updating jobs that don't match a specified owner login. It's commonly used for security compliance, post-migration cleanup, and environment standardization where consistent job ownership is required.

        By default, jobs are reassigned to the 'sa' account (or the renamed sysadmin account if 'sa' was renamed), but you can specify any valid login. The function automatically detects renamed 'sa' accounts by finding the login with ID 1.

        Only local (non-MultiServer) jobs are processed by default, though you can target specific jobs or exclude certain ones. The function validates that the target login exists and prevents assignment to Windows groups, which cannot own SQL Agent jobs.

        Jobs already owned by the target login are skipped, and detailed status information is returned for each job processed.

        Best practice reference: https://www.itprotoday.com/sql-server-tip-assign-ownership-jobs-sysadmin-account

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Job
        Specifies which SQL Agent jobs to update ownership for. Accepts job names as strings and supports tab completion from the target server.
        Use this when you need to update ownership for specific jobs rather than processing all jobs on the instance.

    .PARAMETER ExcludeJob
        Specifies SQL Agent jobs to skip during the ownership update process. Accepts job names as strings with tab completion.
        Useful for excluding critical jobs or jobs that must retain their current ownership for security or operational reasons.

    .PARAMETER InputObject
        Accepts SQL Agent job objects from the pipeline, typically from Get-DbaAgentJob output.
        Use this for advanced filtering scenarios where you need to process jobs based on complex criteria like owner, category, or schedule properties.

    .PARAMETER Login
        Specifies the target login account that should own the SQL Agent jobs. Defaults to 'sa' or automatically detects the renamed sysadmin account (login ID 1).
        Must be a valid SQL login or Windows account that exists on the server. Cannot be a Windows group as they cannot own SQL Agent jobs.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Job
        Author: Michael Fal (@Mike_Fal), mikefal.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaAgentJobOwner

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Agent.Job

        Returns one Job object per SQL Agent job processed, with added connection context and operation status information.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Name: The SQL Agent job name
        - Category: The job category
        - OwnerLoginName: The login name that owns the job (updated if operation was successful)
        - Status: Operation result status (Skipped, Failed, or Successful)
        - Notes: Additional information about the operation result (reason for skip/failure, empty on success)

        All properties from the base SMO Job object are accessible using Select-Object *. The output includes all original SMO Job properties plus the added connection context properties and status information.

    .EXAMPLE
        PS C:\> Set-DbaAgentJobOwner -SqlInstance localhost

        Sets SQL Agent Job owner to sa on all jobs where the owner does not match sa.

    .EXAMPLE
        PS C:\> Set-DbaAgentJobOwner -SqlInstance localhost -Login DOMAIN\account

        Sets SQL Agent Job owner to 'DOMAIN\account' on all jobs where the owner does not match 'DOMAIN\account'. Note
        that Login must be a valid security principal that exists on the target server.

    .EXAMPLE
        PS C:\> Set-DbaAgentJobOwner -SqlInstance localhost -Job job1, job2

        Sets SQL Agent Job owner to 'sa' on the job1 and job2 jobs if their current owner does not match 'sa'.

    .EXAMPLE
        PS C:\> 'sqlserver','sql2016' | Set-DbaAgentJobOwner

        Sets SQL Agent Job owner to sa on all jobs where the owner does not match sa on both sqlserver and sql2016.

    .EXAMPLE
        PS C:\> Get-DbaAgentJob -SqlInstance vmsql | Where-Object OwnerLoginName -eq login1 | Set-DbaAgentJobOwner -TargetLogin login2 | Out-Gridview

        Sets SQL Agent Job owner to login2 where their current owner is login1 on instance vmsql. Send result to gridview.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Jobs")]
        [object[]]$Job,
        [object[]]$ExcludeJob,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Agent.Job[]]$InputObject,
        [Alias("TargetLogin")]
        [string]$Login,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            #Get job list. If value for -Job is passed, massage to make it a string array.
            #Otherwise, use all jobs on the instance where owner not equal to -TargetLogin
            Write-Message -Level Verbose -Message "Gathering jobs to update."

            if ($Job) {
                $jobcollection = $server.JobServer.Jobs | Where-Object { $Job -contains $_.Name }
            } else {
                $jobcollection = $server.JobServer.Jobs | Where-Object JobType -eq Local
            }

            if ($ExcludeJob) {
                $jobcollection = $jobcollection | Where-Object { $ExcludeJob -notcontains $_.Name }
            }

            $InputObject += $jobcollection
        }

        Write-Message -Level Verbose -Message "Updating $($InputObject.Count) job(s)."
        foreach ($agentJob in $InputObject) {
            $jobname = $agentJob.Name
            $server = $agentJob.Parent.Parent

            if (-not $Login) {
                # dynamic sa name for orgs who have changed their sa name
                $newLogin = ($server.logins | Where-Object { $_.id -eq 1 }).Name
            } else {
                $newLogin = $Login
            }

            #Validate login
            if ($agentJob.OwnerLoginName -eq $newLogin) {
                $status = 'Skipped'
                $notes = "Owner already set"
            } else {
                if (($server.Logins.Name) -notcontains $newLogin) {
                    $status = 'Failed'
                    $notes = "Login $newLogin not valid"
                } else {
                    if ($server.logins[$newLogin].LoginType -eq 'WindowsGroup') {
                        $status = 'Failed'
                        $notes = "$newLogin is a Windows Group and can not be a job owner."
                    } else {
                        if ($PSCmdlet.ShouldProcess($instance, "Setting job owner for $jobname to $newLogin")) {
                            try {
                                Write-Message -Level Verbose -Message "Setting job owner for $jobname to $newLogin on $instance."
                                #Set job owner to $TargetLogin (default 'sa')
                                $agentJob.OwnerLoginName = $newLogin
                                $agentJob.Alter()
                                $status = 'Successful'
                                $notes = ''
                            } catch {
                                Stop-Function -Message "Issue setting job owner on $jobName." -Target $jobName -InnerErrorRecord $_ -Category InvalidOperation
                            }
                        }
                    }
                }
            }
            Add-Member -Force -InputObject $agentJob -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
            Add-Member -Force -InputObject $agentJob -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
            Add-Member -Force -InputObject $agentJob -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
            Add-Member -Force -InputObject $agentJob -MemberType NoteProperty -Name Status -value $status
            Add-Member -Force -InputObject $agentJob -MemberType NoteProperty -Name Notes -value $notes
            Select-DefaultView -InputObject $agentJob -Property ComputerName, InstanceName, SqlInstance, Name, Category, OwnerLoginName, Status, Notes
        }
    }
}