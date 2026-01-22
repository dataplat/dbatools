function Test-DbaAgentJobOwner {
    <#
    .SYNOPSIS
        Identifies SQL Agent jobs with incorrect ownership for security compliance auditing

    .DESCRIPTION
        This function audits SQL Agent job ownership by comparing each job's current owner against a target login, typically 'sa' or another sysadmin account. Jobs owned by inappropriate accounts can pose security risks, especially if those accounts are disabled, deleted, or have reduced permissions. By default, it checks against the 'sa' account (or renamed sysadmin), but you can specify any valid login for your organization's security standards. Returns only jobs that don't match the expected ownership, making it easy to identify compliance violations that need remediation.

        Best practice reference: https://www.itprotoday.com/sql-server-tip-assign-ownership-jobs-sysadmin-account

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Job
        Specifies specific SQL Agent jobs to check for ownership compliance. When provided, only these named jobs are evaluated against the target owner.
        Use this to focus on critical jobs or when troubleshooting specific ownership issues. If omitted, all jobs on the instance are processed.

    .PARAMETER ExcludeJob
        Excludes specific SQL Agent jobs from the ownership compliance check. Useful for skipping system jobs or jobs that legitimately require different owners.
        Commonly used to exclude jobs like 'syspolicy_purge_history' or maintenance jobs that run under service accounts by design.

    .PARAMETER Login
        Specifies the target login that should own SQL Agent jobs for security compliance. Must be an existing login on the server, cannot be a Windows Group.
        Defaults to 'sa' (or the renamed sysadmin account). Common alternatives include service accounts or dedicated job owner logins required by your organization's security policies.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Job, Owner
        Author: Michael Fal (@Mike_Fal), mikefal.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaAgentJobOwner

    .OUTPUTS
        System.Management.Automation.PSCustomObject

        Returns one object per SQL Agent job found on the instance. By default, only jobs where the current owner does not match the target owner are returned. When -Job is specified, all matching jobs are returned regardless of ownership status.

        Default display properties (via Select-DefaultView):
        - Server: The name of the SQL Server instance
        - Job: The name of the SQL Agent job
        - JobType: Type of job (Remote for remote jobs, LocalJob, or other job type values)
        - CurrentOwner: The login name that currently owns this job
        - TargetOwner: The expected login name that should own this job (default 'sa' or specified via -Login parameter)
        - OwnerMatch: Boolean indicating if the current owner matches the target owner

    .EXAMPLE
        PS C:\> Test-DbaAgentJobOwner -SqlInstance localhost

        Returns all SQL Agent Jobs where the owner does not match 'sa'.

    .EXAMPLE
        PS C:\> Test-DbaAgentJobOwner -SqlInstance localhost -ExcludeJob 'syspolicy_purge_history'

        Returns SQL Agent Jobs except for the syspolicy_purge_history job

    .EXAMPLE
        PS C:\> Test-DbaAgentJobOwner -SqlInstance localhost -Login DOMAIN\account

        Returns all SQL Agent Jobs where the owner does not match DOMAIN\account. Note
        that Login must be a valid security principal that exists on the target server.

    #>
    [CmdletBinding()]
    [OutputType('System.Object[]')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Jobs")]
        [object[]]$Job,
        [object[]]$ExcludeJob,
        [Alias("TargetLogin")]
        [string]$Login,
        [switch]$EnableException
    )

    begin {
        #connect to the instance and set return array empty
        $return = @()
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            #Validate login
            if ($Login -and ($server.Logins.Name) -notcontains $Login) {
                if ($SqlInstance.count -eq 1) {
                    Stop-Function -Message "Invalid login: $Login."
                    return
                } else {
                    Write-Message -Level Warning -Message "$Login is not a valid login on $instance. Moving on."
                    continue
                }
            }
            if ($Login -and $server.Logins[$Login].LoginType -eq 'WindowsGroup') {
                Stop-Function -Message "$Login is a Windows Group and can not be a job owner."
                return
            }

            #Sets the Default Login to sa if the Login Paramater is not set.
            if (!($PSBoundParameters.ContainsKey('Login'))) {
                $Login = "sa"
            }
            #sql2000 id property is empty -force target login to 'sa' login
            if ($Login -and ( ($server.VersionMajor -lt 9) -and ([string]::IsNullOrEmpty($Login)) )) {
                $Login = "sa"
            }
            # dynamic sa name for orgs who have changed their sa name
            if ($Login -eq "sa") {
                $Login = ($server.Logins | Where-Object { $_.id -eq 1 }).Name
            }

            #Get database list. If value for -Job is passed, massage to make it a string array.
            #Otherwise, use all jobs on the instance where owner not equal to -TargetLogin
            Write-Message -Level Verbose -Message "Gathering jobs to check."
            if ($Job) {
                $jobCollection = $server.JobServer.Jobs | Where-Object { $Job -contains $_.Name }
            } elseif ($ExcludeJob) {
                $jobCollection = $server.JobServer.Jobs | Where-Object { $ExcludeJob -notcontains $_.Name }
            } else {
                $jobCollection = $server.JobServer.Jobs
            }

            #for each database, create custom object for return set.
            foreach ($j in $jobCollection) {
                Write-Message -Level Verbose -Message "Checking $j"
                $row = [ordered]@{
                    Server       = $server.Name
                    Job          = $j.Name
                    JobType      = if ($j.CategoryID -eq 1) { "Remote" } else { $j.JobType }
                    CurrentOwner = $j.OwnerLoginName
                    TargetOwner  = $Login
                    OwnerMatch   = if ($j.CategoryID -eq 1) { $true } else { $j.OwnerLoginName -eq $Login }

                }
                #add each custom object to the return array
                $return += New-Object PSObject -Property $row
            }
            if ($Job) {
                $results = $return
            } else {
                $results = $return | Where-Object { $_.OwnerMatch -eq $False }
            }
        }
    }
    end {
        #return results
        Select-DefaultView -InputObject $results -Property Server, Job, JobType, CurrentOwner, TargetOwner, OwnerMatch
    }

}