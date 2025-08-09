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
        [string[]]$JobId = "u2vte5xhhhtqput0"
    )

    foreach ($id in $JobId) {
        Write-Verbose "Fetching artifacts for Job ID: $id"
        $result = Invoke-AppVeyorApi "buildjobs/$id/artifacts" | Where-Object fileName -match TestFailureSummary

        [pscustomobject]@{
            JobId    = $id
            Filename = $result.fileName
            Type     = $result.type
            Size     = $result.size
            Created  = $result.created
            Content  = Invoke-AppVeyorApi "buildjobs/$id/artifacts/$($result.fileName)"
        }
    }
}