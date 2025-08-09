function Get-BuildFailures {
    <#
    .SYNOPSIS
        Gets test failures from a specific AppVeyor build.

    .DESCRIPTION
        Retrieves detailed failure information from failed jobs in an AppVeyor build.

    .PARAMETER Build
        Build object containing BuildId and Project information.

    .PARAMETER PRNumber
        The pull request number associated with this build.

    .NOTES
        Tags: AppVeyor, Testing, CI
        Author: dbatools team
        Requires: APPVEYOR_API_TOKEN environment variable
    #>
    [CmdletBinding()]
    param($Build, [int]$PRNumber)

    $buildData = Invoke-AppVeyorApi "projects/$($Build.Project)/builds/$($Build.BuildId)"
    $failedJobs = $buildData.build.jobs | Where-Object { $_.status -eq "failed" }

    $failures = @()
    foreach ($job in $failedJobs) {
        $jobFailures = Get-JobFailures -JobId $job.jobId -JobName $job.name -PRNumber $PRNumber
        $failures += $jobFailures
    }

    return $failures
}