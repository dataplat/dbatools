function Parse-TestArtifact {
    <#
    .SYNOPSIS
        Parses test failure artifacts from AppVeyor.

    .DESCRIPTION
        Downloads and parses test failure summary artifacts to extract detailed failure information.

    .PARAMETER Artifact
        The artifact object to parse.

    .PARAMETER JobId
        The AppVeyor job ID.

    .PARAMETER JobName
        The name of the job.

    .PARAMETER PRNumber
        The pull request number.

    .NOTES
        Tags: AppVeyor, Testing, Artifacts, Parsing
        Author: dbatools team
        Requires: APPVEYOR_API_TOKEN environment variable
    #>
    [CmdletBinding()]
    param($Artifact, [string]$JobId, [string]$JobName, [int]$PRNumber)

    $content = Invoke-AppVeyorApi "buildjobs/$JobId/artifacts/$($Artifact.fileName)"
    $summary = $content | ConvertFrom-Json

    return $summary.Failures | ForEach-Object {
        [PSCustomObject]@{
            TestName = $_.Name
            TestFile = $_.TestFile
            Command = $_.TestFile -replace '\.Tests\.ps1$', ''
            Describe = $_.Describe
            Context = $_.Context
            ErrorMessage = $_.ErrorMessage
            JobName = $JobName
            JobId = $JobId
            PRNumber = $PRNumber
        }
    }
}