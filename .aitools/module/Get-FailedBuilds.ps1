function Get-FailedBuilds {
    <#
    .SYNOPSIS
        Gets failed AppVeyor builds for a pull request.

    .DESCRIPTION
        Retrieves AppVeyor build information for failed builds associated with a pull request.

    .PARAMETER PRNumber
        The pull request number to check.

    .PARAMETER Project
        The AppVeyor project name. Defaults to "dataplat/dbatools".

    .NOTES
        Tags: AppVeyor, CI, PullRequest
        Author: dbatools team
        Requires: gh CLI
    #>
    [CmdletBinding()]
    param([int]$PRNumber, [string]$Project)

    $checks = gh pr checks $PRNumber --json "name,state,link" | ConvertFrom-Json
    $appveyorChecks = $checks | Where-Object {
        $_.name -like "*AppVeyor*" -and $_.state -eq "FAILURE"
    }

    return $appveyorChecks | ForEach-Object {
        if ($_.link -match '/builds/(\d+)') {
            @{
                BuildId = $Matches[1]
                Project = $Project
                Link = $_.link
            }
        }
    } | Where-Object { $_ }
}