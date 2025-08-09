function Get-JobFailure {
    <#
    .SYNOPSIS
        Gets test failures from a specific AppVeyor job.

    .DESCRIPTION
        Retrieves test failure details from a failed AppVeyor job, preferring artifacts
        over log parsing when available.

    .PARAMETER JobId
        The AppVeyor job ID.

    .PARAMETER JobName
        The name of the job.

    .PARAMETER PRNumber
        The pull request number associated with this job.

    .NOTES
        Tags: AppVeyor, Testing, CI
        Author: dbatools team
        Requires: APPVEYOR_API_TOKEN environment variable
    #>
    [CmdletBinding()]
    param([string]$JobId, [string]$JobName, [int]$PRNumber)

    # Try artifacts first (most reliable)
    $artifacts = Get-TestArtifacts -JobId $JobId
    if ($artifacts) {
        return $artifacts | ForEach-Object {
            Parse-TestArtifact -Artifact $_ -JobId $JobId -JobName $JobName -PRNumber $PRNumber
        }
    }

    # Fallback to basic job info
    return @([PSCustomObject]@{
        TestName = "Build failed"
        TestFile = "Unknown"
        Command = "Unknown"
        ErrorMessage = "Job $JobName failed - no detailed test results available"
        JobName = $JobName
        JobId = $JobId
        PRNumber = $PRNumber
    })
}