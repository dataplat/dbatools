function Get-TargetPullRequest {
    <#
    .SYNOPSIS
        Gets target pull request numbers for processing.

    .DESCRIPTION
        Returns the specified pull request numbers, or if none specified,
        returns all open pull request numbers.

    .PARAMETER PullRequest
        Array of specific pull request numbers. If not provided, gets all open PRs.

    .NOTES
        Tags: PullRequest, GitHub, CI
        Author: dbatools team
        Requires: gh CLI
    #>
    [CmdletBinding()]
    param(
        [int[]]$PullRequest
    )

    $results = gh pr list --state open --json "number" | ConvertFrom-Json
    if ($PullRequest) {
        $results | Where-Object { $_.number -in $PullRequest }
    } else {
        $results
    }
}