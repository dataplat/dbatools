function Get-AppVeyorFailure {
    <#
    .SYNOPSIS
        Retrieves test failures from AppVeyor builds for specified pull requests.

    .DESCRIPTION
        Fetches AppVeyor build information and parses logs to extract test failure details
        for one or more pull requests.

    .PARAMETER PullRequest
        Array of pull request numbers to check. If not specified, checks all open PRs.

    .NOTES
        Tags: AppVeyor, Testing, CI, PullRequest
        Author: dbatools team
        Requires: gh CLI, APPVEYOR_API_TOKEN environment variable
    #>
    [CmdletBinding()]
    param (
        [int[]]$PullRequest
    )

    if (-not $PullRequest) {
        Write-Verbose "No pull request numbers specified, getting all open PRs..."
        $prsJson = gh pr list --state open --json "number,title,headRefName,state,statusCheckRollup"
        if (-not $prsJson) {
            Write-Warning "No open pull requests found"
            return
        }
        $openPRs = $prsJson | ConvertFrom-Json
        $PullRequest = $openPRs | ForEach-Object { $_.number }
        Write-Verbose "Found $($PullRequest.Count) open PRs: $($PullRequest -join ',')"
    }

    foreach ($prNumber in $PullRequest) {
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
            Write-Verbose "Fetching build details for build ID: $buildId"

            $apiParams = @{
                Endpoint = "projects/dataplat/dbatools/builds/$buildId"
            }
            $build = Invoke-AppVeyorApi @apiParams

            if (-not $build -or -not $build.build -or -not $build.build.jobs) {
                Write-Verbose "No build data or jobs found for build $buildId"
                continue
            }

            $failedJobs = $build.build.jobs | Where-Object { $_.status -eq "failed" }

            if (-not $failedJobs) {
                Write-Verbose "No failed jobs found in build $buildId"
                continue
            }

            foreach ($job in $failedJobs) {
                Write-Verbose "Processing failed job: $($job.name) (ID: $($job.jobId))"

                try {
                    Write-Verbose "Fetching logs for job $($job.jobId)"

                    $logParams = @{
                        Endpoint = "buildjobs/$($job.jobId)/log"
                    }
                    $jobLogs = Invoke-AppVeyorApi @logParams

                    if (-not $jobLogs) {
                        Write-Verbose "No logs returned for job $($job.jobId)"
                        continue
                    }

                    Write-Verbose "Retrieved job logs for $($job.name) ($($jobLogs.Length) characters)"

                    $logLines = $jobLogs -split "`r?`n"
                    Write-Verbose "Parsing $($logLines.Count) log lines for test failures"

                    foreach ($line in $logLines) {
                        # Much broader pattern matching - this is the key fix
                        if ($line -match '\.Tests\.ps1' -and
                            ($line -match '\[-\]| \bfail | \berror | \bexception | Failed: | Error:' -or
                             $line -match 'should\s+(?:be | not | contain | match)' -or
                             $line -match 'Expected.*but.*was' -or
                             $line -match 'Assertion failed')) {

                            # Extract test file name
                            $testFileMatch = $line | Select-String -Pattern '([^\\\/\s]+\.Tests\.ps1)' | Select-Object -First 1
                            $testFile = if ($testFileMatch) { $testFileMatch.Matches[0].Groups[1].Value } else { "Unknown.Tests.ps1" }

                            # Extract line number if present
                            $lineNumber = if ($line -match ':(\d+)' -or $line -match 'line\s+(\d+)' -or $line -match '\((\d+)\)') {
                                $Matches[1]
                            } else {
                                "Unknown"
                            }

                            [PSCustomObject]@{
                                TestFile     = $testFile
                                Command      = $testFile -replace '\.Tests\.ps1$', ''
                                LineNumber   = $lineNumber
                                Runner       = $job.name
                                ErrorMessage = $line.Trim()
                                JobId        = $job.jobId
                                PRNumber     = $prNumber
                            }
                        }
                        # Look for general Pester test failures
                        elseif ($line -match '\[-\]\s+' -and $line -notmatch '^\s*\[-\]\s*$') {
                            [PSCustomObject]@{
                                TestFile     = "Unknown.Tests.ps1"
                                Command      = "Unknown"
                                LineNumber   = "Unknown"
                                Runner       = $job.name
                                ErrorMessage = $line.Trim()
                                JobId        = $job.jobId
                                PRNumber     = $prNumber
                            }
                        }
                        # Look for PowerShell errors in test context
                        elseif ($line -match 'At\s+.*\.Tests\.ps1:\d+' -or
                                ($line -match 'Exception| Error' -and $line -match '\.Tests\.ps1')) {

                            $testFileMatch = $line | Select-String -Pattern '([^\\\/\s]+\.Tests\.ps1)' | Select-Object -First 1
                            $testFile = if ($testFileMatch) { $testFileMatch.Matches[0].Groups[1].Value } else { "Unknown.Tests.ps1" }

                            $lineNumber = if ($line -match '\.Tests\.ps1:(\d+)') {
                                $Matches[1]
                            } else {
                                "Unknown"
                            }

                            [PSCustomObject]@{
                                TestFile     = $testFile
                                Command      = $testFile -replace '\.Tests\.ps1$', ''
                                LineNumber   = $lineNumber
                                Runner       = $job.name
                                ErrorMessage = $line.Trim()
                                JobId        = $job.jobId
                                PRNumber     = $prNumber
                            }
                        }
                    }

                } catch {
                    Write-Verbose "Failed to get logs for job $($job.jobId): $_"
                    continue
                }
            }
        } catch {
            Write-Verbose "Failed to fetch AppVeyor build details for build ${buildId}: $_"
            continue
        }
    }
}