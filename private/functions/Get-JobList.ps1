function Get-JobList {
    <#
    .SYNOPSIS
        Helper function to get SQL Agent jobs.
    .DESCRIPTION
        Helper function to get all SQL Agent jobs or provide filter
    .PARAMETER SqlInstance
        SQL Server instance
    .PARAMETER SqlCredential
        Credential to use if SqlInstance did not include it.
    .PARAMETER JobFilter
        Object of jobs to filter on, also supports wildcard patterns
    .PARAMETER StepFilter
        Object of job steps to filter on, also supports wildcard patterns
    .PARAMETER Not
        Reverse results where object returned excludes filtered content.
    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .EXAMPLE
        Get-JobList -SqlInstance sql2016

        Returns the full JobServer.Jobs object found on sql2016
    .EXAMPLE
        Get-JobList -SqlInstance sql2016 -JobFilter '*job*'

        Returns the Job object for each job name found to have "job" in the name on sql2016
    .EXAMPLE
        Get-JobList -SqlInstance sql2016 -JobFilter '*job*' -Not

        Returns any Job object that does not have "job" in the name on sql2016
    .EXAMPLE
        Get-JobList -SqlInstance YourServer -JobFilter 'JobName'

        Returns the Job object where the job name is 'JobName' on sql2016
    .EXAMPLE
        Get-JobList -SqlInstance YourServer -JobFilter 'JobName' -Not

        Returns any Job object where the job name is not 'JobName' on sql2016
    .EXAMPLE
        Get-JobList -SqlInstance YourServer -JobFilter job_3_upload, job_3_download

        Returns the Job object for where job is job_3_upload or job_3_download on sql2016
    .EXAMPLE
        Get-JobList -SqlInstance YourServer -JobFilter job_3_upload, job_3_download -Not

        Returns any Job object where job is not job_3_upload or job_3_download on sql2016
    .NOTES
        Author: Shawn Melton (@wsmelton)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT
    #>
    [cmdletbinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$JobFilter,
        [string[]]$StepFilter,
        [switch]$Not,
        [switch]$EnableException
    )
    process {
        $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential

        $jobs = $server.JobServer.Jobs
        if ( (Test-Bound 'JobFilter') -or (Test-Bound 'StepFilter') ) {
            
            foreach ($job in $jobs) {
                foreach($jFilter in $JobFilter) {
                    if ($jFilter -match '`*') {
                        if ($Not) {
                            $job | Where-Object Name -NotLike $jFilter
                        } else {
                            $job | Where-Object Name -Like $jFilter
                        }
                    } else {
                        if ($Not) {
                            $job | Where-Object Name -NE $jFilter
                        } else {
                            $job | Where-Object Name -EQ $jFilter
                        }
                    }
                }
                foreach($sFilter in $StepFilter) {
                    if ($sFilter -match '`*') {
                        if ($Not) {
                            $stepFound = $job.JobSteps | Where-Object Name -NotLike $sFilter
                            if ($stepFound.Count -gt 0) {
                                $job
                            }
                        } else {
                            $stepFound = $job.JobSteps | Where-Object Name -Like $sFilter
                            if ($stepFound.Count -gt 0) {
                                $job
                            }
                        }
                    } else {
                        if ($Not) {
                            $stepFound = $job.JobSteps | Where-Object Name -NE $sFilter
                            if ($stepFound.Count -gt 0) {
                                $job
                            }
                        } else {
                            $stepFound = $job.JobSteps | Where-Object Name -EQ $sFilter
                            if ($stepFound.Count -gt 0) {
                                $job
                            }
                        }
                    }
                }                
            }
        } else {
            $jobs
        }
    }
}