function Repair-PullRequestTest {
    <#
   .SYNOPSIS
       Fixes failing Pester tests in open pull requests by replacing with working versions and running Update-PesterTest.

   .DESCRIPTION
       This function checks open PRs for AppVeyor failures, extracts failing test information,
       and replaces failing tests with working versions from the Development branch, then runs
       Update-PesterTest to migrate them properly.

   .PARAMETER PRNumber
       Specific PR number to process. If not specified, processes all open PRs with failures.

   .PARAMETER AutoCommit
       If specified, automatically commits the fixes made by the repair process.

   .PARAMETER MaxPRs
       Maximum number of PRs to process. Default: 5

   .PARAMETER BuildNumber
       Specific AppVeyor build number to target instead of automatically detecting from PR checks.
       When specified, uses this build number directly rather than finding the latest build for the PR.

   .NOTES
       Tags: Testing, Pester, PullRequest, CI
       Author: dbatools team
       Requires: gh CLI, git, AppVeyor API access

   .EXAMPLE
       PS C:\> Repair-PullRequestTest
       Checks all open PRs and fixes failing tests using Claude.

   .EXAMPLE
       PS C:\> Repair-PullRequestTest -PRNumber 9234 -AutoCommit
       Fixes failing tests in PR #9234 and automatically commits the changes.

   .EXAMPLE
       PS C:\> Repair-PullRequestTest -PRNumber 9234 -BuildNumber 12345
       Fixes failing tests in PR #9234 using AppVeyor build #12345 instead of the latest build.

   .EXAMPLE
       PS C:\> Repair-PullRequestTest -BuildNumber 12345
       Fixes failing tests from AppVeyor build #12345 across all relevant PRs.
   #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [int]$PRNumber,
        [switch]$AutoCommit,
        [int]$MaxPRs = 5,
        [int]$BuildNumber
    )

    begin {
        # Ensure we're in the dbatools repository
        $gitRoot = git rev-parse --show-toplevel 2>$null
        if (-not $gitRoot -or -not (Test-Path "$gitRoot/dbatools.psm1")) {
            throw "This command must be run from within the dbatools repository"
        } else {
            Write-Progress -Activity "Repairing Pull Request Tests" -Status "Importing dbatools" -PercentComplete 0
            Import-Module "$gitRoot/dbatools.psm1" -Force -ErrorAction Stop
        }

        Write-Verbose "Working in repository: $gitRoot"

        # Store current branch to return to it later - be more explicit
        $originalBranch = git rev-parse --abbrev-ref HEAD 2>$null
        if (-not $originalBranch) {
            $originalBranch = git branch --show-current 2>$null
        }

        Write-Verbose "Original branch detected as: '$originalBranch'"
        Write-Verbose "Current branch: $originalBranch"

        # Validate we got a branch name
        if (-not $originalBranch -or $originalBranch -eq "HEAD") {
            throw "Could not determine current branch name. Are you in a detached HEAD state?"
        }

        # Ensure gh CLI is available
        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
            throw "GitHub CLI (gh) is required but not found. Please install it first."
        }

        # Check gh auth status
        $null = gh auth status 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Not authenticated with GitHub CLI. Please run 'gh auth login' first."
        }

        # Create temp directory for working test files (cross-platform)
        $tempDir = if ($IsWindows -or $env:OS -eq "Windows_NT") {
            Join-Path $env:TEMP "dbatools-repair-$(Get-Random)"
        } else {
            Join-Path "/tmp" "dbatools-repair-$(Get-Random)"
        }

        if (-not (Test-Path $tempDir)) {
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
            Write-Verbose "Created temp directory: $tempDir"
        }

        # Initialize hash table to track processed files across all PRs
        $processedFiles = @{}
    }

    process {
        try {
            # Get open PRs
            Write-Verbose "Fetching open pull requests..."
            Write-Progress -Activity "Repairing Pull Request Tests" -Status "Fetching open PRs..." -PercentComplete 0

            if ($PRNumber) {
                $prsJson = gh pr view $PRNumber --json "number,title,headRefName,state,statusCheckRollup,files" 2>$null
                if (-not $prsJson) {
                    throw "Could not fetch PR #$PRNumber"
                }
                $prs = @($prsJson | ConvertFrom-Json)
            } else {
                # Try to find PR for current branch first
                Write-Verbose "No PR number specified, checking for PR associated with current branch '$originalBranch'"
                $currentBranchPR = gh pr view --json "number,title,headRefName,state,statusCheckRollup,files" 2>$null

                if ($currentBranchPR) {
                    Write-Verbose "Found PR for current branch: $originalBranch"
                    $prs = @($currentBranchPR | ConvertFrom-Json)
                } else {
                    Write-Verbose "No PR found for current branch, fetching all open PRs"
                    $prsJson = gh pr list --state open --limit $MaxPRs --json "number,title,headRefName,state,statusCheckRollup" 2>$null
                    $prs = $prsJson | ConvertFrom-Json

                    # For each PR, get the files changed (since pr list doesn't include files)
                    $prsWithFiles = @()
                    foreach ($pr in $prs) {
                        $prWithFiles = gh pr view $pr.number --json "number,title,headRefName,state,statusCheckRollup,files" 2>$null
                        if ($prWithFiles) {
                            $prsWithFiles += ($prWithFiles | ConvertFrom-Json)
                        }
                    }
                    $prs = $prsWithFiles
                }
            }

            Write-Verbose "Found $($prs.Count) open PR(s)"

            # Handle specific build number scenario differently
            if ($BuildNumber) {
                Write-Verbose "Using specific build number: $BuildNumber, bypassing PR-based detection"
                Write-Progress -Activity "Repairing Pull Request Tests" -Status "Fetching test failures from AppVeyor build #$BuildNumber..." -PercentComplete 50 -Id 0

                # Get failures directly from the specified build
                $getFailureParams = @{
                    BuildNumber = $BuildNumber
                }
                $allFailedTestsAcrossPRs = @(Get-AppVeyorFailure @getFailureParams)

                if (-not $allFailedTestsAcrossPRs) {
                    Write-Verbose "Could not retrieve test failures from AppVeyor build #$BuildNumber"
                    return
                }

                # For build-specific mode, we don't filter by PR files - process all failures
                $allRelevantTestFiles = @()

                # Use the first PR for branch operations (or current branch if no PR specified)
                $selectedPR = $prs | Select-Object -First 1
                if (-not $selectedPR -and -not $PRNumber) {
                    # No PR context, stay on current branch
                    $selectedPR = @{
                        number = "current"
                        headRefName = $originalBranch
                    }
                }
            } else {
                # Original PR-based logic
                # Collect ALL failed tests from ALL PRs first, then deduplicate
                $allFailedTestsAcrossPRs = @()
                $allRelevantTestFiles = @()
                $selectedPR = $null  # We'll use the first PR with failures for branch operations

                # Initialize overall progress tracking
                $prCount = 0
                $totalPRs = $prs.Count

                foreach ($pr in $prs) {
                    $prCount++
                    $prProgress = [math]::Round(($prCount / $totalPRs) * 100, 0)

                    Write-Progress -Activity "Repairing Pull Request Tests" -Status "Collecting failures from PR #$($pr.number) - $($pr.title)" -PercentComplete $prProgress -Id 0
                    Write-Verbose "`nCollecting failures from PR #$($pr.number) - $($pr.title)"

                    # Get the list of files changed in this PR to filter which tests to fix
                    $changedTestFiles = @()
                    $changedCommandFiles = @()

                    Write-Verbose "PR files object: $($pr.files | ConvertTo-Json -Depth 3)"

                    if ($pr.files -and $pr.files.Count -gt 0) {
                        foreach ($file in $pr.files) {
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
                    } else {
                        Write-Verbose "No files found in PR object or files array is empty"
                    }

                    # Combine both directly changed test files and test files for changed commands
                    $relevantTestFiles = ($changedTestFiles + $changedCommandFiles) | Sort-Object -Unique
                    $allRelevantTestFiles += $relevantTestFiles

                    Write-Verbose "Relevant test files for PR #$($pr.number) - $($relevantTestFiles -join '`n ')"

                    # Check for AppVeyor failures
                    $appveyorChecks = $pr.statusCheckRollup | Where-Object {
                        $_.context -like "*appveyor*" -and $_.state -match "PENDING|FAILURE"
                    }

                    if (-not $appveyorChecks) {
                        Write-Verbose "No AppVeyor failures found in PR #$($pr.number)"
                        continue
                    }

                    # Store the first PR with failures to use for branch operations
                    if (-not $selectedPR) {
                        $selectedPR = $pr
                        Write-Verbose "Selected PR #$($pr.number) '$($pr.headRefName)' as target branch for fixes"
                    }

                    # Get AppVeyor build details
                    Write-Progress -Activity "Repairing Pull Request Tests" -Status "Fetching test failures from AppVeyor for PR #$($pr.number)..." -PercentComplete $prProgress -Id 0
                    $getFailureParams = @{
                        PullRequest = $pr.number
                    }
                    $prFailedTests = Get-AppVeyorFailure @getFailureParams

                    if (-not $prFailedTests) {
                        Write-Verbose "Could not retrieve test failures from AppVeyor for PR #$($pr.number)"
                        continue
                    }

                    # Filter tests for this PR and add to collection
                    foreach ($test in $prFailedTests) {
                        $testFileName = [System.IO.Path]::GetFileName($test.TestFile)
                        if ($relevantTestFiles.Count -eq 0 -or $testFileName -in $relevantTestFiles) {
                            $allFailedTestsAcrossPRs += $test
                        }
                    }
                }
            }

            # If no failures found anywhere, exit
            if (-not $allFailedTestsAcrossPRs -or -not $selectedPR) {
                Write-Verbose "No test failures found across any PRs"
                return
            }

            # Now deduplicate and group ALL failures by test file
            $allRelevantTestFiles = $allRelevantTestFiles | Sort-Object -Unique
            Write-Verbose "All relevant test files across PRs - $($allRelevantTestFiles -join ', ')"

            # Create hash table to group ALL errors by unique file name
            $fileErrorMap = @{}
            foreach ($test in $allFailedTestsAcrossPRs) {
                $fileName = [System.IO.Path]::GetFileName($test.TestFile)
                # ONLY include files that are actually in the PR changes
                if ($allRelevantTestFiles.Count -eq 0 -or $fileName -in $allRelevantTestFiles) {
                    if (-not $fileErrorMap.ContainsKey($fileName)) {
                        $fileErrorMap[$fileName] = @()
                    }
                    $fileErrorMap[$fileName] += $test
                }
            }

            Write-Verbose "Found failures in $($fileErrorMap.Keys.Count) unique test files (filtered to PR changes only)"
            foreach ($fileName in $fileErrorMap.Keys) {
                Write-Verbose "  ${fileName} - $($fileErrorMap[$fileName].Count) failures"
            }

            # If no relevant failures after filtering, exit
            if ($fileErrorMap.Keys.Count -eq 0) {
                Write-Verbose "No test failures found in files that were changed in the PR(s)"
                return
            }

            # Check if we need to stash uncommitted changes
            $needsStash = $false
            if ((git status --porcelain 2>$null)) {
                Write-Verbose "Stashing uncommitted changes"
                git stash --quiet | Out-Null
                $needsStash = $true
            } else {
                Write-Verbose "No uncommitted changes to stash"
            }

            # Batch copy all working test files from development branch
            Write-Progress -Activity "Repairing Pull Request Tests" -Status "Getting working test files from development branch..." -PercentComplete 25 -Id 0
            Write-Verbose "Switching to development branch to copy all working test files"
            git checkout development --quiet 2>$null | Out-Null

            $copiedFiles = @()
            foreach ($fileName in $fileErrorMap.Keys) {
                $workingTestPath = Resolve-Path "tests/$fileName" -ErrorAction SilentlyContinue
                $workingTempPath = Join-Path $tempDir "working-$fileName"

                if ($workingTestPath -and (Test-Path $workingTestPath)) {
                    Copy-Item $workingTestPath $workingTempPath -Force
                    $copiedFiles += $fileName
                    Write-Verbose "Copied working test: $fileName"
                } else {
                    Write-Warning "Could not find working test file in Development branch: tests/$fileName"
                }
            }

            Write-Verbose "Copied $($copiedFiles.Count) working test files from development branch"

            # Switch to the selected PR branch for all operations (unless using current branch)
            if ($selectedPR.number -ne "current") {
                Write-Verbose "Switching to PR #$($selectedPR.number) branch '$($selectedPR.headRefName)'"
                git fetch origin $selectedPR.headRefName 2>$null | Out-Null
                git checkout $selectedPR.headRefName 2>$null | Out-Null

                # Verify the checkout worked
                $afterCheckout = git rev-parse --abbrev-ref HEAD 2>$null
                if ($afterCheckout -ne $selectedPR.headRefName) {
                    Write-Error "Failed to checkout selected PR branch '$($selectedPR.headRefName)'. Currently on '$afterCheckout'."
                    return
                }

                Write-Verbose "Successfully checked out branch '$($selectedPR.headRefName)'"
            } else {
                Write-Verbose "Switching back to original branch '$originalBranch'"
                git checkout $originalBranch --quiet 2>$null | Out-Null
            }

            # Unstash if we stashed earlier
            if ($needsStash) {
                Write-Verbose "Restoring stashed changes"
                git stash pop --quiet 2>$null | Out-Null
            }

            # Now process each unique file once - replace with working version and run Update-PesterTest
            Write-Progress -Activity "Repairing Pull Request Tests" -Status "Identified $($fileErrorMap.Keys.Count) files needing repairs - replacing with working versions..." -PercentComplete 50 -Id 0

            $totalUniqueFiles = $fileErrorMap.Keys.Count
            $processedFileCount = 0

            foreach ($fileName in $fileErrorMap.Keys) {
                $processedFileCount++

                # Skip if already processed
                if ($processedFiles.ContainsKey($fileName)) {
                    Write-Verbose "Skipping $fileName - already processed"
                    continue
                }

                $allFailuresForFile = $fileErrorMap[$fileName]
                $fileProgress = [math]::Round(($processedFileCount / $totalUniqueFiles) * 100, 0)

                Write-Progress -Activity "Fixing Unique Test Files" -Status "Processing $fileName" -PercentComplete $fileProgress -Id 1
                Write-Verbose "Processing $fileName - re-running Update-PesterTest to create newly migrated test file"

                if ($PSCmdlet.ShouldProcess($fileName, "Replace with working version and run Update-PesterTest")) {
                    # Get the pre-copied working test file
                    $workingTempPath = Join-Path $tempDir "working-$fileName"
                    if (-not (Test-Path $workingTempPath)) {
                        Write-Warning "Working test file not found in temp directory: $workingTempPath"
                        continue
                    }

                    # Get the path to the failing test file
                    $failingTestPath = Resolve-Path "tests/$fileName" -ErrorAction SilentlyContinue
                    if (-not $failingTestPath) {
                        Write-Warning "Could not find failing test file - tests/$fileName"
                        continue
                    }

                    Write-Progress -Activity "Fixing $fileName" -Status "Replacing with working version from development" -PercentComplete 30 -Id 2 -ParentId 1
                    Write-Verbose "Replacing failing test $fileName with working version from development"

                    # Replace the failing test with the working copy from development
                    try {
                        Copy-Item $workingTempPath $failingTestPath.Path -Force
                        Write-Verbose "Successfully replaced $fileName with working version"
                    } catch {
                        Write-Warning "Failed to replace $fileName with working version - $($_.Exception.Message)"
                        continue
                    }

                    Write-Progress -Activity "Fixing $fileName" -Status "Running Update-PesterTest..." -PercentComplete 70 -Id 2 -ParentId 1
                    Write-Verbose "Running Update-PesterTest on $fileName"

                    # Run Update-PesterTest against the working copy to migrate it properly
                    try {
                        # Skip the module import since we've already imported it
                        $env:SKIP_DBATOOLS_IMPORT = $true
                        Update-PesterTest -InputObject (Get-Item $failingTestPath.Path) -ErrorAction Stop
                        Remove-Item env:SKIP_DBATOOLS_IMPORT -ErrorAction SilentlyContinue
                        Write-Verbose "Successfully ran Update-PesterTest on $fileName"

                        # Mark this file as processed
                        $processedFiles[$fileName] = $true
                        Write-Verbose "Successfully processed $fileName"
                    } catch {
                        Write-Warning "Update-PesterTest failed for $fileName - $($_.Exception.Message)"
                    }

                    # Clear the detailed progress for this file
                    Write-Progress -Activity "Fixing $fileName" -Completed -Id 2
                }
            }

            # Clear the file-level progress
            Write-Progress -Activity "Fixing Unique Test Files" -Completed -Id 1

            # Commit changes if requested
            if ($AutoCommit) {
                Write-Progress -Activity "Repairing Pull Request Tests" -Status "Committing fixes..." -PercentComplete 90 -Id 0
                $changedFiles = git diff --name-only 2>$null
                if ($changedFiles) {
                    Write-Verbose "Committing fixes for all processed files..."
                    git add -A 2>$null | Out-Null
                    git commit -m "Fix failing Pester tests across multiple files (replaced with working versions + Update-PesterTest)" 2>$null | Out-Null
                    Write-Verbose "Changes committed successfully"
                }
            }

            # Complete the overall progress
            Write-Progress -Activity "Repairing Pull Request Tests" -Status "Completed processing $($processedFiles.Keys.Count) unique test files" -PercentComplete 100 -Id 0
            Write-Progress -Activity "Repairing Pull Request Tests" -Completed -Id 0

        } finally {
            # Clear any remaining progress bars
            Write-Progress -Activity "Repairing Pull Request Tests" -Completed -Id 0
            Write-Progress -Activity "Fixing Unique Test Files" -Completed -Id 1
            Write-Progress -Activity "Individual Test Fix" -Completed -Id 2

            # Return to original branch with extra verification
            $finalCurrentBranch = git rev-parse --abbrev-ref HEAD 2>$null
            Write-Verbose "In finally block, currently on - '$finalCurrentBranch', should return to - '$originalBranch'"

            if ($finalCurrentBranch -ne $originalBranch) {
                Write-Verbose "Returning to original branch - $originalBranch"
                git checkout $originalBranch 2>$null | Out-Null

                # Verify the final checkout worked
                $verifyFinal = git rev-parse --abbrev-ref HEAD 2>$null
                Write-Verbose "After final checkout, now on - '$verifyFinal'"

                if ($verifyFinal -ne $originalBranch) {
                    Write-Error "FAILED to return to original branch '$originalBranch'. Currently on '$verifyFinal'."
                } else {
                    Write-Verbose "Successfully returned to original branch '$originalBranch'"
                }
            } else {
                Write-Verbose "Already on correct branch '$originalBranch'"
            }

            # Clean up temp directory
            if (Test-Path $tempDir) {
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                Write-Verbose "Cleaned up temp directory - $tempDir"
            }
        }
    }
}