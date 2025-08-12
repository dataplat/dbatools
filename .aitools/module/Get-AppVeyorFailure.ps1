function Get-AppVeyorFailure {
    <#
    .SYNOPSIS
        Retrieves test failure information from AppVeyor builds.

    .DESCRIPTION
        This function fetches test failure details from AppVeyor builds, either by specifying
        pull request numbers or a specific build number. It extracts failed test information
        from build artifacts and returns detailed failure data for analysis.

    .PARAMETER PullRequest
        Array of pull request numbers to process. If not specified and no BuildNumber is provided,
        processes all open pull requests with AppVeyor failures.

    .PARAMETER BuildNumber
        Specific AppVeyor build number to target instead of automatically detecting from PR checks.
        When specified, retrieves failures directly from this build number, ignoring PR-based detection.

    .PARAMETER Branch
        Specific branch name to get AppVeyor failures for. When specified, finds the latest build
        for this branch and retrieves failures from it.

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
        PS C:\> Get-AppVeyorFailure -BuildNumber 12345
        Retrieves test failures directly from AppVeyor build #12345, bypassing PR detection.

    .EXAMPLE
        PS C:\> Get-AppVeyorFailure -Branch "feature-branch"
        Retrieves test failures from the latest AppVeyor build for the specified branch.
    #>
    [CmdletBinding()]
    param (
        [int[]]$PullRequest,

        [int]$BuildNumber,

        [string]$Branch
    )

    # If Branch is specified, find the latest build for that branch
    if ($Branch) {
        Write-Progress -Activity "Get-AppVeyorFailure" -Status "Fetching latest build for branch '$Branch'..." -PercentComplete 0
        Write-Verbose "Looking for latest AppVeyor build for branch: $Branch"

        # Try GitHub CLI integration first
        $usedGh = $false
        try {
            $Owner = "dataplat"
            $Repo = "dbatools"

            # Get the latest commit SHA for the branch
            $sha = (& gh api "repos/$Owner/$Repo/commits?sha=$Branch&per_page=1" -q '.[0].sha' 2>$null)
            if ($sha) {
                $sha = $sha.Trim()

                # Try checks API first
                $detailsUrl = (& gh api "repos/$Owner/$Repo/commits/$sha/check-runs?per_page=100" -q '.check_runs | sort_by(.started_at, .created_at) | reverse[] | select((.name|test("appveyor";"i")) or (.app.slug=="appveyor")) | .details_url' 2>$null)
                if ($detailsUrl) {
                    $detailsUrl = ($detailsUrl -split "`r?`n" | Select-Object -First 1).Trim()
                }

                # Fallback to statuses API if no check-runs found
                if (-not $detailsUrl) {
                    $detailsUrl = (& gh api "repos/$Owner/$Repo/commits/$sha/status" -q '.statuses | sort_by(.updated_at, .created_at) | reverse[] | select(.context|test("appveyor";"i")) | .target_url' 2>$null)
                    if ($detailsUrl) {
                        $detailsUrl = ($detailsUrl -split "`r?`n" | Select-Object -First 1).Trim()
                    }
                }

                # Extract AppVeyor build version from URL
                if ($detailsUrl -and $detailsUrl -match '/build/([^/?#]+)') {
                    $version = $Matches[1]
                    Write-Verbose "Using GitHub checks to resolve AppVeyor build for branch '$Branch' (version: $version)"

                    # Call AppVeyor API directly with the version
                    $apiParams = @{
                        Endpoint = "projects/dataplat/dbatools/build/$version"
                    }
                    $build = Invoke-AppVeyorApi @apiParams

                    if ($build -and $build.build) {
                        $BuildNumber = $build.build.buildNumber
                        $usedGh = $true
                        Write-Verbose "Successfully resolved build #$BuildNumber using GitHub CLI"
                    }
                }
            }
<<<<<<< Updated upstream
=======
            $history = Invoke-AppVeyorApi @apiParams

            if (-not $history -or -not $history.builds) {
                Write-Verbose "No build history found"
                Write-Progress -Activity "Get-AppVeyorFailure" -Completed
                return
            }

            # Find the latest build for this branch
            $branchBuild = $history.builds | Where-Object { $_.branch -eq $Branch } | Select-Object -First 1

            if (-not $branchBuild) {
                Write-Verbose "No builds found for branch: $Branch"
                Write-Progress -Activity "Get-AppVeyorFailure" -Completed
                return
            }

            $BuildId = $branchBuild.buildId
            Write-Verbose "Found latest build ID $BuildId for branch '$Branch'"
>>>>>>> Stashed changes
        } catch {
            # Silently fall back to existing logic
            Write-Verbose "GitHub CLI approach failed, falling back to AppVeyor history API"
        }

        # Fallback to existing -Branch logic if GitHub CLI didn't work
        if (-not $usedGh) {
            try {
                # Get recent builds and find the latest one for this branch
                $apiParams = @{
                    Endpoint = "projects/dataplat/dbatools/history?recordsNumber=50"
                }
                $history = Invoke-AppVeyorApi @apiParams

                if (-not $history -or -not $history.builds) {
                    Write-Verbose "No build history found"
                    Write-Progress -Activity "Get-AppVeyorFailure" -Completed
                    return
                }

                # Find the latest build for this branch
                $branchBuild = $history.builds | Where-Object { $_.branch -eq $Branch } | Select-Object -First 1

                if (-not $branchBuild) {
                    Write-Verbose "No builds found for branch: $Branch"
                    Write-Progress -Activity "Get-AppVeyorFailure" -Completed
                    return
                }

                $BuildNumber = $branchBuild.buildNumber
                Write-Verbose "Found latest build #$BuildNumber for branch '$Branch'"
            } catch {
                Write-Verbose "Failed to fetch build history for branch ${Branch}: $_"
                Write-Progress -Activity "Get-AppVeyorFailure" -Completed
                return
            }
        }
    }

    # If BuildNumber is specified (either directly or found from branch), use it directly
    if ($BuildNumber -or $BuildId) {
        # For backward compatibility, BuildNumber parameter maps to buildId for API calls
        if ($BuildNumber -and -not $BuildId) {
            $BuildId = $BuildNumber
        }
        Write-Progress -Activity "Get-AppVeyorFailure" -Status "Fetching build details for build ID $BuildId..." -PercentComplete 0
        Write-Verbose "Using specified build ID: $BuildId"

        try {
            $apiParams = @{
                Endpoint = "projects/dataplat/dbatools/builds/$BuildId"
            }
            $build = Invoke-AppVeyorApi @apiParams

            if (-not $build -or -not $build.build -or -not $build.build.jobs) {
                Write-Verbose "No build data or jobs found for build ID $BuildId"
                Write-Progress -Activity "Get-AppVeyorFailure" -Completed
                return
            }

            $failedJobs = $build.build.jobs | Where-Object Status -eq "failed"

            if (-not $failedJobs) {
                Write-Verbose "No failed jobs found in build ID $BuildId"
                Write-Progress -Activity "Get-AppVeyorFailure" -Completed
                return
            }

            $totalJobs = $failedJobs.Count
            $currentJob = 0

            foreach ($job in $failedJobs) {
                $currentJob++
                $jobProgress = [math]::Round(($currentJob / $totalJobs) * 100)
                Write-Progress -Activity "Getting job failure information" -Status "Processing failed job $currentJob of $totalJobs for build ID $BuildId" -PercentComplete $jobProgress -CurrentOperation "Job: $($job.name)"
                Write-Verbose "Processing failed job: $($job.name) (ID: $($job.jobId))"
                (Get-TestArtifact -JobId $job.jobid).Content.Failures
            }
        } catch {
            Write-Verbose "Failed to fetch AppVeyor build details for build ID ${BuildId}: $_"
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

        # Get the list of files changed in this PR to filter which test failures to return
        $prDetailsJson = gh pr view $prNumber --json "files" 2>$null
        if (-not $prDetailsJson) {
            Write-Verbose "Could not fetch PR details for PR #$prNumber"
            continue
        }

        $prDetails = $prDetailsJson | ConvertFrom-Json
        $changedTestFiles = @()
        $changedCommandFiles = @()

        if ($prDetails.files -and $prDetails.files.Count -gt 0) {
            foreach ($file in $prDetails.files) {
                $filename = if ($file.filename) { $file.filename } elseif ($file.path) { $file.path } else { $file }

                if ($filename -like "*Tests.ps1" -or $filename -like "tests/*.Tests.ps1") {
                    $testFileName = [System.IO.Path]::GetFileName($filename)
                    $changedTestFiles += $testFileName
                    Write-Verbose "Added test file: $testFileName"
                } elseif ($filename -like "public/*.ps1") {
                    $commandName = [System.IO.Path]::GetFileNameWithoutExtension($filename)
                    $testFileName = "$commandName.Tests.ps1"
                    $changedCommandFiles += $testFileName
                    Write-Verbose "Added command test file: $testFileName (from command - $commandName)"
                }
            }
        }

        # Combine both directly changed test files and test files for changed commands
        $relevantTestFiles = ($changedTestFiles + $changedCommandFiles) | Sort-Object -Unique
        Write-Verbose "Relevant test files for PR #${prNumber}: $($relevantTestFiles -join ', ')"

        if ($relevantTestFiles.Count -eq 0) {
            Write-Verbose "No test files changed in PR #$prNumber, skipping"
            continue
        }

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
                Write-Progress -Activity "Getting job failure information" -Status "Processing failed job $currentJob of $totalJobs for PR #$prNumber" -PercentComplete $prPercentComplete -CurrentOperation "Job: $($job.name)"
                Write-Verbose "Processing failed job: $($job.name) (ID: $($job.jobId))"

                $allFailures = (Get-TestArtifact -JobId $job.jobid).Content.Failures

                # Filter failures to only include test files that were changed in this PR
                $filteredFailures = $allFailures | Where-Object {
                    $testFileName = [System.IO.Path]::GetFileName($_.TestFile)
                    $testFileName -in $relevantTestFiles
                }

                Write-Verbose "Found $($allFailures.Count) total failures, filtered to $($filteredFailures.Count) failures for changed files"
                $filteredFailures
            }
        } catch {
            Write-Verbose "Failed to fetch AppVeyor build details for build ${buildId}: $_"
            continue
        }
    }

    Write-Progress -Activity "Get-AppVeyorFailure" -Completed
}
