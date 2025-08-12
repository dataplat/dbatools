function Get-AppVeyorFailure {
    <#
    .SYNOPSIS
        Retrieves test failure information from AppVeyor builds with automatic detection.

    .DESCRIPTION
        This function fetches test failure details from AppVeyor builds. When called without parameters,
        it automatically detects the AppVeyor build associated with the current branch using multiple
        fallback methods (PR checks, commit status, check-runs API). You can also specify pull request
        numbers, build IDs, or branch names explicitly. It extracts failed test information from build
        artifacts and returns detailed failure data for analysis.

    .PARAMETER PullRequest
        Array of pull request numbers to process. If not specified and no BuildId or Branch is provided,
        automatically detects build failures from the current branch, or falls back to all open PRs.

    .PARAMETER BuildId
        Specific AppVeyor build number to target instead of automatically detecting from PR checks.
        When specified, retrieves failures directly from this build number, ignoring PR-based detection.

    .PARAMETER Branch
        Branch name to get AppVeyor build ID from. The function will attempt to find the AppVeyor
        build associated with this branch by checking PR status or commit status checks.

    .PARAMETER Pattern
        Optional regex pattern to filter failures by filename. When specified, only returns failures
        that match the pattern using the -match operator.

    .NOTES
        Tags: Testing, AppVeyor, CI, PullRequest
        Author: dbatools team
        Requires: AppVeyor API access, gh CLI

    .EXAMPLE
        PS C:\> Get-AppVeyorFailure
        Automatically detects and retrieves test failures from the current branch's AppVeyor build.
        If no build is found for the current branch, falls back to all open pull requests with AppVeyor failures.

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

    .EXAMPLE
        PS C:\> Get-AppVeyorFailure -Branch "feature/new-command"
        Retrieves test failures from AppVeyor builds associated with the "feature/new-command" branch.

    .EXAMPLE
        PS C:\> Get-AppVeyorFailure -Branch "main" -Pattern "Connect-Dba"
        Retrieves test failures from the main branch, filtered to only show failures matching "Connect-Dba".
    #>
    [CmdletBinding()]
    param (
        [int[]]$PullRequest,

        [int]$BuildId,

        [string]$Branch,

        [string]$Pattern
    )

    # Helper function to check if branch has been published to AppVeyor
    function Test-BranchPublished {
        param([string]$BranchName)

        if (-not $BranchName -or $BranchName -eq "HEAD") {
            return $false
        }

        try {
            # Check if branch exists on remote
            $remoteBranch = git ls-remote --heads origin $BranchName 2>$null
            if (-not $remoteBranch) {
                Write-Verbose "Branch '$BranchName' not found on remote origin"
                return $false
            }

            # Check if there are any AppVeyor builds for this branch
            $commitSha = git rev-parse "origin/$BranchName" 2>$null
            if (-not $commitSha) {
                $commitSha = git rev-parse $BranchName 2>$null
            }

            if ($commitSha) {
                # Try to find AppVeyor status/checks for this commit
                $checkRunsJson = gh api "repos/dataplat/dbatools/commits/$commitSha/check-runs" 2>$null
                if ($checkRunsJson) {
                    $checkRuns = $checkRunsJson | ConvertFrom-Json
                    $appveyorCheckRun = $checkRuns.check_runs | Where-Object {
                        $_.name -like "*AppVeyor*" -or $_.app.name -like "*AppVeyor*"
                    }
                    if ($appveyorCheckRun) {
                        return $true
                    }
                }

                # Fallback to status API
                $statusJson = gh api "repos/dataplat/dbatools/commits/$commitSha/status" 2>$null
                if ($statusJson) {
                    $status = $statusJson | ConvertFrom-Json
                    $appveyorStatus = $status.statuses | Where-Object {
                        $_.context -like "*appveyor*" -or $_.context -like "*AppVeyor*"
                    }
                    if ($appveyorStatus) {
                        return $true
                    }
                }
            }

            return $false
        } catch {
            Write-Verbose "Error checking if branch '$BranchName' is published: $_"
            return $false
        }
    }

    # Early exit if current branch hasn't been published (unless specific BuildId or Branch is provided)
    if (-not $BuildId -and -not $Branch -and -not $PullRequest) {
        $currentBranch = git rev-parse --abbrev-ref HEAD 2>$null
        if (-not $currentBranch) {
            $currentBranch = git branch --show-current 2>$null
        }

        if ($currentBranch -and $currentBranch -ne "HEAD") {
            if (-not (Test-BranchPublished -BranchName $currentBranch)) {
                Write-Warning "Current branch '$currentBranch' has not been published to AppVeyor. No errors to check."
                return
            }
        }
    }

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

    # If Branch is specified, try to get BuildId from branch
    if ($Branch) {
        Write-Progress -Activity "Get-AppVeyorFailure" -Status "Getting build ID from branch '$Branch'..." -PercentComplete 0
        Write-Verbose "Attempting to get AppVeyor build ID from branch: $Branch"

        $derivedBuildId = $null

        try {
            # Method 1: Try to find PR for the branch and get build ID from PR checks
            Write-Verbose "Checking for PR associated with branch '$Branch'"
            $branchPRJson = gh pr list --head $Branch --state all --limit 1 --json "number,statusCheckRollup" 2>$null

            if ($branchPRJson) {
                $branchPR = $branchPRJson | ConvertFrom-Json | Select-Object -First 1
                if ($branchPR -and $branchPR.statusCheckRollup) {
                    Write-Verbose "Found PR #$($branchPR.number) for branch '$Branch'"
                    $appveyorCheck = $branchPR.statusCheckRollup | Where-Object {
                        $_.context -like "*appveyor*" -or $_.context -like "*AppVeyor*"
                    }

                    if ($appveyorCheck -and $appveyorCheck.targetUrl) {
                        if ($appveyorCheck.targetUrl -match '/builds/(\d+)') {
                            $derivedBuildId = $Matches[1]
                            Write-Verbose "Extracted build ID $derivedBuildId from PR check URL: $($appveyorCheck.targetUrl)"
                        }
                    }
                }
            }

            # Method 2: If no PR found or no build ID from PR, try commit status approach
            if (-not $derivedBuildId) {
                Write-Verbose "No build ID found from PR checks, trying commit status approach"

                # Get the latest commit SHA for the branch
                $commitSha = git rev-parse "origin/$Branch" 2>$null
                if (-not $commitSha) {
                    $commitSha = git rev-parse $Branch 2>$null
                }

                if ($commitSha) {
                    Write-Verbose "Getting commit status for SHA: $commitSha"

                    # Try check-runs API first (newer GitHub checks)
                    $checkRunsJson = gh api "repos/dataplat/dbatools/commits/$commitSha/check-runs" 2>$null
                    if ($checkRunsJson) {
                        $checkRuns = $checkRunsJson | ConvertFrom-Json
                        $appveyorCheckRun = $checkRuns.check_runs | Where-Object {
                            $_.name -like "*AppVeyor*" -or $_.app.name -like "*AppVeyor*"
                        } | Select-Object -First 1

                        if ($appveyorCheckRun -and $appveyorCheckRun.details_url) {
                            if ($appveyorCheckRun.details_url -match '/builds/(\d+)') {
                                $derivedBuildId = $Matches[1]
                                Write-Verbose "Extracted build ID $derivedBuildId from check-run URL: $($appveyorCheckRun.details_url)"
                            }
                        }
                    }

                    # Fallback to status API (older GitHub status checks)
                    if (-not $derivedBuildId) {
                        $statusJson = gh api "repos/dataplat/dbatools/commits/$commitSha/status" 2>$null
                        if ($statusJson) {
                            $status = $statusJson | ConvertFrom-Json
                            $appveyorStatus = $status.statuses | Where-Object {
                                $_.context -like "*appveyor*" -or $_.context -like "*AppVeyor*"
                            } | Select-Object -First 1

                            if ($appveyorStatus -and $appveyorStatus.target_url) {
                                if ($appveyorStatus.target_url -match '/builds/(\d+)') {
                                    $derivedBuildId = $Matches[1]
                                    Write-Verbose "Extracted build ID $derivedBuildId from status URL: $($appveyorStatus.target_url)"
                                }
                            }
                        }
                    }
                } else {
                    Write-Verbose "Could not resolve commit SHA for branch '$Branch'"
                }
            }

        } catch {
            Write-Verbose "Error while trying to get build ID from branch '$Branch': $_"
        }

        if ($derivedBuildId) {
            Write-Verbose "Successfully derived build ID $derivedBuildId from branch '$Branch', using it directly"
            # Recursively call with the derived BuildId
            $getFailureParams = @{
                BuildId = [int]$derivedBuildId
            }
            if ($Pattern) { $getFailureParams.Pattern = $Pattern }
            return Get-AppVeyorFailure @getFailureParams
        } else {
            Write-Warning "Could not derive AppVeyor build ID from branch '$Branch'. No AppVeyor builds found for this branch."
            Write-Progress -Activity "Get-AppVeyorFailure" -Completed
            return
        }
    }

    # Enhanced auto-detection logic
    if (-not $PullRequest) {
        Write-Progress -Activity "Get-AppVeyorFailure" -Status "Auto-detecting build from current branch..." -PercentComplete 0
        Write-Verbose "No pull request numbers specified, attempting auto-detection from current branch..."

        # Get current branch name
        $currentBranch = git rev-parse --abbrev-ref HEAD 2>$null
        if (-not $currentBranch) {
            $currentBranch = git branch --show-current 2>$null
        }

        if ($currentBranch -and $currentBranch -ne "HEAD") {
            Write-Verbose "Current branch detected: $currentBranch"

            # Try to auto-detect build ID from current branch first
            $autoBuildId = $null

            try {
                # Method 1: Check if current branch has a PR and get build ID from it
                Write-Verbose "Checking for PR associated with current branch '$currentBranch'"
                $currentBranchPRJson = gh pr view --json "number,statusCheckRollup" 2>$null

                if ($currentBranchPRJson) {
                    $currentBranchPR = $currentBranchPRJson | ConvertFrom-Json
                    Write-Verbose "Found PR #$($currentBranchPR.number) for current branch '$currentBranch'"

                    $appveyorCheck = $currentBranchPR.statusCheckRollup | Where-Object {
                        $_.context -like "*appveyor*" -or $_.context -like "*AppVeyor*"
                    }

                    if ($appveyorCheck -and $appveyorCheck.targetUrl) {
                        if ($appveyorCheck.targetUrl -match '/builds/(\d+)') {
                            $autoBuildId = $Matches[1]
                            Write-Verbose "Auto-detected build ID $autoBuildId from current branch PR"
                        }
                    }
                }

                # Method 2: If no PR or no build ID from PR, try commit status approach
                if (-not $autoBuildId) {
                    Write-Verbose "No build ID found from PR, trying commit status for current branch"

                    $commitSha = git rev-parse HEAD 2>$null
                    if ($commitSha) {
                        Write-Verbose "Getting commit status for current HEAD: $commitSha"

                        # Try check-runs API first
                        $checkRunsJson = gh api "repos/dataplat/dbatools/commits/$commitSha/check-runs" 2>$null
                        if ($checkRunsJson) {
                            $checkRuns = $checkRunsJson | ConvertFrom-Json
                            $appveyorCheckRun = $checkRuns.check_runs | Where-Object {
                                $_.name -like "*AppVeyor*" -or $_.app.name -like "*AppVeyor*"
                            } | Select-Object -First 1

                            if ($appveyorCheckRun -and $appveyorCheckRun.details_url) {
                                if ($appveyorCheckRun.details_url -match '/builds/(\d+)') {
                                    $autoBuildId = $Matches[1]
                                    Write-Verbose "Auto-detected build ID $autoBuildId from check-run for current branch"
                                }
                            }
                        }

                        # Fallback to status API
                        if (-not $autoBuildId) {
                            $statusJson = gh api "repos/dataplat/dbatools/commits/$commitSha/status" 2>$null
                            if ($statusJson) {
                                $status = $statusJson | ConvertFrom-Json
                                $appveyorStatus = $status.statuses | Where-Object {
                                    $_.context -like "*appveyor*" -or $_.context -like "*AppVeyor*"
                                } | Select-Object -First 1

                                if ($appveyorStatus -and $appveyorStatus.target_url) {
                                    if ($appveyorStatus.target_url -match '/builds/(\d+)') {
                                        $autoBuildId = $Matches[1]
                                        Write-Verbose "Auto-detected build ID $autoBuildId from status for current branch"
                                    }
                                }
                            }
                        }
                    }
                }
            } catch {
                Write-Verbose "Error during auto-detection: $_"
            }

            # If we found a build ID, use it directly
            if ($autoBuildId) {
                Write-Verbose "Successfully auto-detected build ID $autoBuildId from current branch '$currentBranch', using it directly"
                $getFailureParams = @{
                    BuildId = [int]$autoBuildId
                }
                if ($Pattern) { $getFailureParams.Pattern = $Pattern }
                return Get-AppVeyorFailure @getFailureParams
            } else {
                Write-Verbose "Could not auto-detect build ID from current branch '$currentBranch', falling back to open PRs"
            }
        }

        # Fallback: get all open PRs if auto-detection failed
        Write-Verbose "Falling back to processing all open PRs..."
        $prsJson = gh pr list --state open --json "number,title,headRefName,state,statusCheckRollup"
        if (-not $prsJson) {
            Write-Progress -Activity "Get-AppVeyorFailure" -Completed
            Write-Warning "No open pull requests found and could not auto-detect build from current branch"
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
