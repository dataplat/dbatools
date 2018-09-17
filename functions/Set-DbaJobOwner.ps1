function Set-DbaJobOwner {
    <#
        .SYNOPSIS
            Sets SQL Agent job owners with a desired login if jobs do not match that owner.

        .DESCRIPTION
            This function alters SQL Agent Job ownership to match a specified login if their current owner does not match the target login. By default, the target login will be 'sa', but the the user may specify a different login for ownership. This be applied to all jobs or only to a select collection of jobs.

            Best practice reference: http://sqlmag.com/blog/sql-server-tip-assign-ownership-jobs-sysadmin-account

        .NOTES
            Tags: Agent, Job
            Author: Michael Fal (@Mike_Fal), http://mikefal.net

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .PARAMETER SqlInstance
            Specifies the SQL Server instance(s) to scan.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Job
            Specifies the job(s) to process. Options for this list are auto-populated from the server. If unspecified, all jobs will be processed.

        .PARAMETER ExcludeJob
            Specifies the job(s) to exclude from processing. Options for this list are auto-populated from the server.

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

        .LINK
            https://dbatools.io/Set-DbaJobOwner

        .EXAMPLE
            Set-DbaJobOwner -SqlInstance localhost

            Sets SQL Agent Job owner to sa on all jobs where the owner does not match sa.

        .EXAMPLE
            Set-DbaJobOwner -SqlInstance localhost -Login DOMAIN\account

            Sets SQL Agent Job owner to sa on all jobs where the owner does not match 'DOMAIN\account'. Note
            that Login must be a valid security principal that exists on the target server.

        .EXAMPLE
            Set-DbaJobOwner -SqlInstance localhost -Job job1, job2

            Sets SQL Agent Job owner to 'sa' on the job1 and job2 jobs if their current owner does not match 'sa'.

        .EXAMPLE
            'sqlserver','sql2016' | Set-DbaJobOwner

            Sets SQL Agent Job owner to sa on all jobs where the owner does not match sa on both sqlserver and sql2016.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Jobs")]
        [object[]]$Job,
        [object[]]$ExcludeJob,
        [Alias("TargetLogin")]
        [string]$Login,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        foreach ($servername in $SqlInstance) {
            #connect to the instance
            Write-Message -Level Verbose -Message "Connecting to $servername."
            $server = Connect-SqlInstance $servername -SqlCredential $SqlCredential

            # dynamic sa name for orgs who have changed their sa name
            if (!$Login) {
                $Login = ($server.logins | Where-Object { $_.id -eq 1 }).Name
            }

            #Validate login
            if (($server.Logins.Name) -notcontains $Login) {
                if ($SqlInstance.count -eq 1) {
                    throw -Message "Invalid login: $Login."
                }
                else {
                    Write-Message -Level Warning -Message "$Login is not a valid login on $servername. Moving on."
                    Continue
                }
            }

            if ($server.logins[$Login].LoginType -eq 'WindowsGroup') {
                throw "$Login is a Windows Group and can not be a job owner."
            }

            #Get database list. If value for -Job is passed, massage to make it a string array.
            #Otherwise, use all jobs on the instance where owner not equal to -TargetLogin
            Write-Message -Level Verbose -Message "Gathering jobs to update."

            if ($Job) {
                $jobcollection = $server.JobServer.Jobs | Where-Object { $_.OwnerLoginName -ne $Login -and $Job -contains $_.Name }
            }
            else {
                $jobcollection = $server.JobServer.Jobs | Where-Object { $_.OwnerLoginName -ne $Login }
            }

            if ($ExcludeJob) {
                $jobcollection = $jobcollection | Where-Object { $ExcludeJob -notcontains $_.Name }
            }

            Write-Message -Level Verbose -Message "Updating $($jobcollection.Count) job(s)."
            foreach ($j in $jobcollection) {
                $jobname = $j.name

                if ($PSCmdlet.ShouldProcess($servername, "Setting job owner for $jobname to $Login")) {
                    try {
                        Write-Message -Level Verbose -Message "Setting job owner for $jobname to $Login on $servername."
                        #Set job owner to $TargetLogin (default 'sa')
                        $j.OwnerLoginName = $Login
                        $j.Alter()
                    }
                    catch {
                        Stop-Function -Message "Issue setting job owner on $jobName." -Target $jobName -InnerErrorRecord $_ -Category InvalidOperation
                    }
                }
            }
        }
    }
}
