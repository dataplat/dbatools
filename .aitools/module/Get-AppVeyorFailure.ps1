function Get-AppVeyorFailure {
    <#
    .SYNOPSIS
        Retrieves test failure information from AppVeyor builds.

    .DESCRIPTION
        This function fetches test failure details from AppVeyor builds, either by specifying
        pull request numbers or a specific build number. It extracts failed test information
        from build artifacts and returns detailed failure data for analysis.

    .PARAMETER PullRequest
        Array of pull request numbers to process. If not specified and no BuildId is provided,
        processes all open pull requests with AppVeyor failures.

    .PARAMETER BuildId
        Specific AppVeyor build number to target instead of automatically detecting from PR checks.
        When specified, retrieves failures directly from this build number, ignoring PR-based detection.

    .PARAMETER Pattern
        Optional regex pattern to filter failures by filename. When specified, only returns failures
        that match the pattern using the -match operator.

    .NOTES
        Tags: Testing, AppVeyor, CI, PullRequest
        Author: dbatools team
        Requires: AppVeyor API access, gh CLI

    .EXAMPLE
        PS C:\> Get-AppVeyorFailure
        Retrieves test failures from all open pull requests with AppVeyor failures.

    .EXAMPLE
        PS C:\> Get-AppVeyorFailure -PullRequest 9234
        Retrieves test failures from AppVeyor builds associated with PR #9234.

    .EXAMPLE
        PS C:\> Get-AppVeyorFailure -PullRequest 9234, 9235
        Retrieves test failures from AppVeyor builds associated with PRs #9234 and #9235.

    .EXAMPLE
        PS C:\> Get-AppVeyorFailure -BuildId 12345
        Retrieves test failures directly from AppVeyor build #12345, bypassing PR detection.

    .EXAMPLE
        PS C:\> Get-AppVeyorFailure -PullRequest 9234 -Pattern "Remove-Dba"
        Retrieves test failures from PR #9234, filtered to only show failures matching "Remove-Dba".

    .EXAMPLE
        PS C:\> Get-AppVeyorFailure -Pattern "\.Tests\.ps1$"
        Retrieves test failures from all open PRs, filtered to only show failures from .Tests.ps1 files.
    #>
    [CmdletBinding()]
    param (
        [int[]]$PullRequest,

        [int]$BuildId,

        [string]$Pattern
    )

    # If BuildId is specified, use it directly instead of looking up PR checks
    if ($BuildId) {
        Write-Progress -Activity "Get-AppVeyorFailure" -Status "Fetching build details for build #$BuildId..." -PercentComplete 0
        Write-Verbose "Using specified build number: $BuildId"

        try {
            $apiParams = @{
                Endpoint = "projects/dataplat/dbatools/builds/$BuildId"
            }
            $build = Invoke-AppVeyorApi @apiParams

            if (-not $build -or -not $build.build -or -not $build.build.jobs) {
                Write-Verbose "No build data or jobs found for build $BuildId"
                Write-Progress -Activity "Get-AppVeyorFailure" -Completed
                return
            }

            $failedJobs = $build.build.jobs | Where-Object Status -eq "failed"

            if (-not $failedJobs) {
                Write-Verbose "No failed jobs found in build $BuildId"
                Write-Progress -Activity "Get-AppVeyorFailure" -Completed
                return
            }

            $totalJobs = $failedJobs.Count
            $currentJob = 0

            foreach ($job in $failedJobs) {
                $currentJob++
                $jobProgress = [math]::Round(($currentJob / $totalJobs) * 100)
                Write-Progress -Activity "Getting job failure information" -Status "Processing failed job $currentJob of $totalJobs for build #$BuildId" -PercentComplete $jobProgress -CurrentOperation "Job: $($job.name)"
                Write-Verbose "Processing failed job: $($job.name) (ID: $($job.jobId))"
                $failures = (Get-TestArtifact -JobId $job.jobid).Content.Failures
                if ($Pattern) { $failures | Where-Object { $_ -match $Pattern } } else { $failures }
            }
        } catch {
            Write-Verbose "Failed to fetch AppVeyor build details for build ${BuildId}: $_"
        }

        Write-Progress -Activity "Get-AppVeyorFailure" -Completed
        return
    }

    # Original logic for PR-based build detection
    if (-not $PullRequest) {
        Write-Progress -Activity "Get-AppVeyorFailure" -Status "Fetching open pull requests..." -PercentComplete 0
        Write-Verbose "No pull request numbers specified, getting all open PRs..."
        $prsJson = gh pr list --state open --json "number,title,headRefName,state,statusCheckRollup"
        if (-not $prsJson) {
            Write-Progress -Activity "Get-AppVeyorFailure" -Completed
            Write-Warning "No open pull requests found"
            return
        }
        $openPRs = $prsJson | ConvertFrom-Json
        $PullRequest = $openPRs | ForEach-Object { $_.number }
        Write-Verbose "Found $($PullRequest.Count) open PRs: $($PullRequest -join ',')"
    }

    $totalPRs = $PullRequest.Count
    $currentPR = 0

    foreach ($prNumber in $PullRequest) {
        $currentPR++
        $prPercentComplete = [math]::Round(($currentPR / $totalPRs) * 100)
        Write-Progress -Activity "Getting PR build information" -Status "Processing PR #$prNumber ($currentPR of $totalPRs)" -PercentComplete $prPercentComplete
        Write-Verbose "Fetching AppVeyor build information for PR #$prNumber"

        $checksJson = gh pr checks $prNumber --json "name,state,link" 2>$null
        if (-not $checksJson) {
            Write-Verbose "Could not fetch checks for PR #$prNumber"
            continue
        }

        $checks = $checksJson | ConvertFrom-Json
        $appveyorCheck = $checks | Where-Object { $_.name -like "*AppVeyor*" -and $_.state -match "PENDING|FAILURE" }

        if (-not $appveyorCheck) {
            Write-Verbose "No failing or pending AppVeyor builds found for PR #$prNumber"
            continue
        }

        if ($appveyorCheck.link -match '/project/[^/]+/[^/]+/builds/(\d+)') {
            $buildmatch = $Matches[1]
        } else {
            Write-Verbose "Could not parse AppVeyor build ID from URL: $($appveyorCheck.link)"
            continue
        }

        try {
            Write-Progress -Activity "Getting build details" -Status "Fetching build details for PR #$prNumber" -PercentComplete $prPercentComplete
            Write-Verbose "Fetching build details for build ID: $buildmatch"

            $apiParams = @{
                Endpoint = "projects/dataplat/dbatools/builds/$buildmatch"
            }
            $build = Invoke-AppVeyorApi @apiParams

            if (-not $build -or -not $build.build -or -not $build.build.jobs) {
                Write-Verbose "No build data or jobs found for build $buildmatch"
                continue
            }

            $failedJobs = $build.build.jobs | Where-Object Status -eq "failed"

            if (-not $failedJobs) {
                Write-Verbose "No failed jobs found in build $buildmatch"
                continue
            }

            $totalJobs = $failedJobs.Count
            $currentJob = 0

            foreach ($job in $failedJobs) {
                $currentJob++
                Write-Progress -Activity "Getting job failure information" -Status "Processing failed job $currentJob of $totalJobs for PR #$prNumber" -PercentComplete $prPercentComplete -CurrentOperation "Job: $($job.name)"
                Write-Verbose "Processing failed job: $($job.name) (ID: $($job.jobId))"
                $failures = (Get-TestArtifact -JobId $job.jobid).Content.Failures
                if ($Pattern) { $failures | Where-Object { $_ -match $Pattern } } else { $failures }
            }
        } catch {
            Write-Verbose "Failed to fetch AppVeyor build details for build ${buildId}: $_"
            continue
        }
    }

    Write-Progress -Activity "Get-AppVeyorFailure" -Completed
}
