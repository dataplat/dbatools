function Get-TestArtifactContent {
    <#
    .SYNOPSIS
        Downloads the raw content of test artifacts from an AppVeyor job.

    .DESCRIPTION
        Retrieves and returns the raw content of test failure summary artifacts from an AppVeyor job.
        This function accepts pipeline input from Get-TestArtifact and downloads the artifact content
        using the existing Invoke-AppVeyorApi function.

    .PARAMETER JobId
        The AppVeyor job ID containing the artifact.

    .PARAMETER FileName
        The artifact file name as returned by Get-TestArtifact.

    .NOTES
        Tags: AppVeyor, Testing, Artifacts
        Author: dbatools team
        Requires: APPVEYOR_API_TOKEN environment variable
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$JobId,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$FileName
    )
    process {
        Write-Verbose "Downloading content from $FileName (job $JobId)"

        try {
            Invoke-AppVeyorApi "buildjobs/$JobId/artifacts/$FileName"
        } catch {
            Write-Error "Failed to download artifact content: $_"
        }
    }
}