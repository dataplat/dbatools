function Set-DbaAgentJobOwner {
    <#
    .SYNOPSIS
        Sets SQL Agent job owners with a desired login if jobs do not match that owner.

    .DESCRIPTION
        This function alters SQL Agent Job ownership to match a specified login if their current owner does not match the target login. By default, the target login will be 'sa',
        but the the user may specify a different login for ownership. This be applied to all jobs or only to a select collection of jobs.

        Best practice reference: https://www.itprotoday.com/sql-server-tip-assign-ownership-jobs-sysadmin-account

        If the 'sa' account was renamed, the new name will be used.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Job
        Specifies the job(s) to process. Options for this list are auto-populated from the server. If unspecified, all jobs will be processed.

    .PARAMETER ExcludeJob
        Specifies the job(s) to exclude from processing. Options for this list are auto-populated from the server.

    .PARAMETER InputObject
        Enables piped input from Get-DbaAgentJob

    .PARAMETER Login
        Specifies the login that you wish check for ownership. This defaults to 'sa' or the sysadmin name if sa was renamed. This must be a valid security principal which exists on the target server.

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
        Author: Michael Fal (@Mike_Fal), http://mikefal.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaAgentJobOwner

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
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            #Get job list. If value for -Job is passed, massage to make it a string array.
            #Otherwise, use all jobs on the instance where owner not equal to -TargetLogin
            Write-Message -Level Verbose -Message "Gathering jobs to update."

            if ($Job) {
                $jobcollection = $server.JobServer.Jobs | Where-Object { $Job -contains $_.Name }
            } else {
                $jobcollection = $server.JobServer.Jobs
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