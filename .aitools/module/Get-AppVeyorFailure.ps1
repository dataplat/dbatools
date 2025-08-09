function Get-AppVeyorFailure {
    [CmdletBinding()]
    param (
        [int[]]$PullRequest
    )

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
            $buildId = $Matches[1]
        } else {
            Write-Verbose "Could not parse AppVeyor build ID from URL: $($appveyorCheck.link)"
            continue
        }

        try {
            Write-Progress -Activity "Getting build details" -Status "Fetching build details for PR #$prNumber" -PercentComplete $prPercentComplete
            Write-Verbose "Fetching build details for build ID: $buildId"

            $apiParams = @{
                Endpoint = "projects/dataplat/dbatools/builds/$buildId"
            }
            $build = Invoke-AppVeyorApi @apiParams

            if (-not $build -or -not $build.build -or -not $build.build.jobs) {
                Write-Verbose "No build data or jobs found for build $buildId"
                continue
            }

            $failedJobs = $build.build.jobs | Where-Object Status -eq "failed"

            if (-not $failedJobs) {
                Write-Verbose "No failed jobs found in build $buildId"
                continue
            }

            $totalJobs = $failedJobs.Count
            $currentJob = 0

            foreach ($job in $failedJobs) {
                $currentJob++
                Write-Progress -Activity "Getting job failure information" -Status "Processing job $currentJob of $totalJobs for PR #$prNumber" -PercentComplete $prPercentComplete -CurrentOperation "Job: $($job.name)"
                Write-Verbose "Processing failed job: $($job.name) (ID: $($job.jobId))"
                (Get-TestArtifact -JobId $job.jobid).Content.Failures
            }
        } catch {
            Write-Verbose "Failed to fetch AppVeyor build details for build ${buildId}: $_"
            continue
        }
    }

    Write-Progress -Activity "Get-AppVeyorFailure" -Completed
}
