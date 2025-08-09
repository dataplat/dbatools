function Get-TestArtifacts {
    <#
    .SYNOPSIS
        Gets test artifacts from an AppVeyor job.

    .DESCRIPTION
        Retrieves test failure summary artifacts from an AppVeyor job.

    .PARAMETER JobId
        The AppVeyor job ID to get artifacts from.

    .NOTES
        Tags: AppVeyor, Testing, Artifacts
        Author: dbatools team
        Requires: APPVEYOR_API_TOKEN environment variable
    #>
    [CmdletBinding()]
    param([string]$JobId)

    $artifacts = Invoke-AppVeyorApi "buildjobs/$JobId/artifacts"
    return $artifacts | Where-Object {
        $_.fileName -match 'TestFailureSummary.*\.json'
    }
}