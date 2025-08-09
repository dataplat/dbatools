function Get-TargetPullRequests {
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
    param([int[]]$PullRequest)

    if ($PullRequest) { return $PullRequest }

    $openPRs = gh pr list --state open --json "number" | ConvertFrom-Json
    return $openPRs.number
}