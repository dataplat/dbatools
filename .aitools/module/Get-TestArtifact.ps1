function Get-TestArtifact {
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
    param(
        [Parameter(ValueFromPipeline)]
        [string[]]$JobId = "0hvpvgv93ojh6ili"
    )

    foreach ($id in $JobId) {
        Write-Verbose "Fetching artifacts for Job ID: $id"
        Invoke-AppVeyorApi "buildjobs/$id/artifacts" | Where-Object fileName -match 'TestFailureSummary.*\.json'
    }
}