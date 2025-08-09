function Repair-PullRequestTest {
    <#
    .SYNOPSIS
        Fixes failing Pester tests in open pull requests using Claude AI.

    .DESCRIPTION
        This function checks open PRs for AppVeyor failures, extracts failing test information,
        compares with working tests from the Development branch, and uses Claude to fix the issues.
        It handles Pester v5 migration issues by providing context from both working and failing versions.

    .PARAMETER PRNumber
        Specific PR number to process. If not specified, processes all open PRs with failures.

    .PARAMETER Model
        The AI model to use with Claude Code.
        Default: claude-sonnet-4-20250514

    .PARAMETER AutoCommit
        If specified, automatically commits the fixes made by Claude.

    .PARAMETER MaxPRs
        Maximum number of PRs to process. Default: 5

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
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [int]$PRNumber,
        [string]$Model = "claude-sonnet-4-20250514",
        [switch]$AutoCommit,
        [int]$MaxPRs = 5
    )

    begin {
        # Ensure we're in the dbatools repository
        $gitRoot = git rev-parse --show-toplevel 2>$null
        if (-not $gitRoot -or -not (Test-Path "$gitRoot/dbatools.psm1")) {
            throw "This command must be run from within the dbatools repository"
        }

        Write-Verbose "Working in repository: $gitRoot"

        # Check for uncommitted changes first
        $statusOutput = git status --porcelain 2>$null
        if ($statusOutput) {
            throw "Repository has uncommitted changes. Please commit, stash, or discard them before running this function.`n$($statusOutput -join "`n")"
        }

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
        $ghAuthStatus = gh auth status 2>&1
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

            # Initialize overall progress tracking
            $prCount = 0
            $totalPRs = $prs.Count

            foreach ($pr in $prs) {
                $prCount++
                $prProgress = [math]::Round(($prCount / $totalPRs) * 100, 0)

                Write-Progress -Activity "Repairing Pull Request Tests" -Status "Processing PR #$($pr.number): $($pr.title)" -PercentComplete $prProgress -Id 0
                Write-Verbose "`nProcessing PR #$($pr.number): $($pr.title)"

                # Get the list of files changed in this PR to filter which tests to fix
                $changedTestFiles = @()
                $changedCommandFiles = @()

                Write-Verbose "PR files object: $($pr.files | ConvertTo-Json -Depth 3)"

                if ($pr.files -and $pr.files.Count -gt 0) {
                    foreach ($file in $pr.files) {
                        Write-Verbose "Processing file: $($file.filename) (path: $($file.path))"
                        $filename = if ($file.filename) { $file.filename } elseif ($file.path) { $file.path } else { $file }

                        if ($filename -like "*Tests.ps1" -or $filename -like "tests/*.Tests.ps1") {
                            $testFileName = [System.IO.Path]::GetFileName($filename)
                            $changedTestFiles += $testFileName
                            Write-Verbose "Added test file: $testFileName"
                        } elseif ($filename -like "public/*.ps1") {
                            $commandName = [System.IO.Path]::GetFileNameWithoutExtension($filename)
                            $testFileName = "$commandName.Tests.ps1"
                            $changedCommandFiles += $testFileName
                            Write-Verbose "Added command test file: $testFileName (from command: $commandName)"
                        }
                    }
                } else {
                    Write-Verbose "No files found in PR object or files array is empty"
                }

                # Combine both directly changed test files and test files for changed commands
                $relevantTestFiles = ($changedTestFiles + $changedCommandFiles) | Sort-Object -Unique

                Write-Verbose "Changed test files in PR #$($pr.number): $($changedTestFiles -join ', ')"
                Write-Verbose "Test files for changed commands in PR #$($pr.number): $($changedCommandFiles -join ', ')"
                Write-Verbose "All relevant test files to process: $($relevantTestFiles -join ', ')"

                # Before any checkout operations, confirm our starting point
                $currentBranch = git rev-parse --abbrev-ref HEAD 2>$null
                Write-Verbose "About to process PR, currently on branch: '$currentBranch'"

                if ($currentBranch -ne $originalBranch) {
                    Write-Warning "Branch changed unexpectedly! Expected '$originalBranch', but on '$currentBranch'. Returning to original branch."
                    git checkout $originalBranch 2>$null | Out-Null
                }

                # Check for AppVeyor failures
                $appveyorChecks = $pr.statusCheckRollup | Where-Object {
                    $_.context -like "*appveyor*" -and $_.state -match "PENDING|FAILURE"
                }

                if (-not $appveyorChecks) {
                    Write-Verbose "No AppVeyor failures found in PR #$($pr.number)"
                    continue
                }

                # Fetch and checkout PR branch (suppress output)
                Write-Progress -Activity "Repairing Pull Request Tests" -Status "Checking out branch: $($pr.headRefName)" -PercentComplete $prProgress -Id 0
                Write-Verbose "Checking out branch: $($pr.headRefName)"
                Write-Verbose "Switching from '$originalBranch' to '$($pr.headRefName)'"

                git fetch origin $pr.headRefName 2>$null | Out-Null
                git checkout $pr.headRefName 2>$null | Out-Null

                # Verify the checkout worked
                $afterCheckout = git rev-parse --abbrev-ref HEAD 2>$null
                Write-Verbose "After checkout, now on branch: '$afterCheckout'"

                if ($afterCheckout -ne $pr.headRefName) {
                    Write-Warning "Failed to checkout PR branch '$($pr.headRefName)'. Currently on '$afterCheckout'. Skipping this PR."
                    continue
                }

                # Get AppVeyor build details
                Write-Progress -Activity "Repairing Pull Request Tests" -Status "Fetching test failures from AppVeyor..." -PercentComplete $prProgress -Id 0
                $getFailureParams = @{
                    PullRequest = $pr.number
                }
                $allFailedTests = Get-AppVeyorFailure @getFailureParams

                if (-not $allFailedTests) {
                    Write-Verbose "Could not retrieve test failures from AppVeyor for PR #$($pr.number)"
                    continue
                }

                # Process only failed tests for files that were changed in this PR
                # This focuses the autofix on tests related to actual changes made
                $filteredOutTests = @()
                $failedTests = @()

                foreach ($test in $allFailedTests) {
                    $testFileName = [System.IO.Path]::GetFileName($test.TestFile)
                    Write-Verbose "Checking test: $testFileName against relevant files: [$($relevantTestFiles -join ', ')]"
                    if ($relevantTestFiles.Count -eq 0) {
                        Write-Verbose "  -> No relevant files defined, filtering out $testFileName"
                        $filteredOutTests += $test
                    } elseif ($testFileName -in $relevantTestFiles) {
                        Write-Verbose "  -> MATCH: Including $testFileName"
                        $failedTests += $test
                    } else {
                        Write-Verbose "  -> NO MATCH: Filtering out $testFileName"
                        $filteredOutTests += $test
                    }
                }

                # Show what we're filtering out
                if ($filteredOutTests.Count -gt 0) {
                    Write-Verbose "FILTERED OUT $($filteredOutTests.Count) test failures (not related to PR changes):"
                    $filteredOutGroups = $filteredOutTests | Group-Object TestFile
                    foreach ($group in $filteredOutGroups) {
                        $testFileName = [System.IO.Path]::GetFileName($group.Name)
                        Write-Verbose "  - $testFileName ($($group.Count) failures)"
                        foreach ($test in $group.Group) {
                            Write-Verbose "    * $($test.TestName)"
                        }
                    }
                }

                if ($allFailedTests.Count -gt 0 -and $failedTests.Count -eq 0) {
                    Write-Verbose "Found $($allFailedTests.Count) total failures, but none are for files changed in this PR"
                    Write-Verbose "Skipping PR #$($pr.number) - no relevant test failures to fix"
                    continue
                } elseif ($failedTests.Count -gt 0) {
                    Write-Verbose "PROCESSING $($failedTests.Count) test failures (related to PR changes):"
                    $includedGroups = $failedTests | Group-Object TestFile
                    foreach ($group in $includedGroups) {
                        $testFileName = [System.IO.Path]::GetFileName($group.Name)
                        Write-Verbose "  + $testFileName ($($group.Count) failures)"
                    }
                }

                if (-not $failedTests -or $failedTests.Count -eq 0) {
                    Write-Verbose "No test failures found in PR #$($pr.number)"
                    continue
                }

                Write-Verbose "Processing $($failedTests.Count) test failures in PR #$($pr.number)"

                # Group failures by test file
                $testGroups = $failedTests | Group-Object TestFile
                $totalTestFiles = $testGroups.Count
                $totalFailures = $failedTests.Count
                $processedFailures = 0
                $fileCount = 0

                Write-Progress -Activity "Repairing Pull Request Tests" -Status "Found $totalFailures failed tests across $totalTestFiles files in PR #$($pr.number)" -PercentComplete $prProgress -Id 0

                foreach ($group in $testGroups) {
                    $fileCount++
                    $testFileName = $group.Name
                    $failures = $group.Group
                    $fileFailureCount = $failures.Count

                    # Calculate progress within this PR
                    $fileProgress = [math]::Round(($fileCount / $totalTestFiles) * 100, 0)

                    Write-Progress -Activity "Fixing Tests in $testFileName" -Status "Processing $fileFailureCount failures ($($processedFailures + $fileFailureCount) of $totalFailures total)" -PercentComplete $fileProgress -Id 1 -ParentId 0
                    Write-Verbose "  Fixing $testFileName with $fileFailureCount failure(s)"

                    if ($PSCmdlet.ShouldProcess($testFileName, "Fix failing tests using Claude")) {
                        # Get working version from Development branch
                        Write-Progress -Activity "Fixing Tests in $testFileName" -Status "Getting working version from Development branch" -PercentComplete 10 -Id 2 -ParentId 1

                        # Temporarily switch to Development to get working test file
                        Write-Verbose "Temporarily switching to 'development' branch"
                        git checkout development 2>$null | Out-Null

                        $afterDevCheckout = git rev-parse --abbrev-ref HEAD 2>$null
                        Write-Verbose "After development checkout, now on: '$afterDevCheckout'"

                        $workingTestPath = Resolve-Path "tests/$testFileName" -ErrorAction SilentlyContinue
                        $workingTempPath = Join-Path $tempDir "working-$testFileName"

                        if ($workingTestPath -and (Test-Path $workingTestPath)) {
                            Copy-Item $workingTestPath $workingTempPath -Force
                            Write-Verbose "Copied working test to: $workingTempPath"
                        } else {
                            Write-Warning "Could not find working test file in Development branch: tests/$testFileName"
                        }

                        # Get the command source file path (while on development)
                        $commandName = [System.IO.Path]::GetFileNameWithoutExtension($testFileName) -replace '\.Tests$', ''
                        Write-Progress -Activity "Fixing Tests in $testFileName" -Status "Getting command source for $commandName" -PercentComplete 20 -Id 2 -ParentId 1

                        $commandSourcePath = $null
                        $possiblePaths = @(
                            "functions/$commandName.ps1",
                            "public/$commandName.ps1",
                            "private/$commandName.ps1"
                        )
                        foreach ($path in $possiblePaths) {
                            if (Test-Path $path) {
                                $commandSourcePath = (Resolve-Path $path).Path
                                Write-Verbose "Found command source: $commandSourcePath"
                                break
                            }
                        }

                        # Switch back to PR branch
                        Write-Verbose "Switching back to PR branch '$($pr.headRefName)'"
                        git checkout $pr.headRefName 2>$null | Out-Null

                        $afterPRReturn = git rev-parse --abbrev-ref HEAD 2>$null
                        Write-Verbose "After returning to PR, now on: '$afterPRReturn'"

                        # Show detailed progress for each failure being fixed
                        for ($i = 0; $i -lt $failures.Count; $i++) {
                            $failureProgress = [math]::Round((($i + 1) / $failures.Count) * 100, 0)
                            Write-Progress -Activity "Fixing Tests in $testFileName" -Status "Fixing failure $($i + 1) of $fileFailureCount - $($failures[$i].TestName)" -PercentComplete $failureProgress -Id 2 -ParentId 1
                        }

                        # Build the repair message with context
                        $repairMessage = "You are fixing ONLY the specific test failures in $testFileName. This test has already been migrated to Pester v5 and styled according to dbatools conventions.`n`n"

                        $repairMessage += "CRITICAL RULES - DO NOT CHANGE THESE:`n"
                        $repairMessage += "1. PRESERVE ALL COMMENTS EXACTLY - Every single comment must remain intact`n"
                        $repairMessage += "2. Keep ALL Pester v5 structure (BeforeAll/BeforeEach blocks, #Requires header, static CommandName)`n"
                        $repairMessage += "3. Keep ALL hashtable alignment - equals signs must stay perfectly aligned`n"
                        $repairMessage += "4. Keep ALL variable naming (unique scoped names, `$splat<Purpose> format)`n"
                        $repairMessage += "5. Keep ALL double quotes for strings`n"
                        $repairMessage += "6. Keep ALL existing `$PSDefaultParameterValues handling for EnableException`n"
                        $repairMessage += "7. Keep ALL current parameter validation patterns with filtering`n"
                        $repairMessage += "8. ONLY fix the specific errors - make MINIMAL changes to get tests passing`n`n"

                        $repairMessage += "COMMON PESTER v5 SCOPING ISSUES TO CHECK:`n"
                        $repairMessage += "- Variables defined in BeforeAll may need `$global: to be accessible in It blocks`n"
                        $repairMessage += "- Variables shared across Context blocks may need explicit scoping`n"
                        $repairMessage += "- Arrays and objects created in setup blocks may need scope declarations`n"
                        $repairMessage += "- Test data variables may need `$global: prefix for cross-block access`n`n"

                        $repairMessage += "WHAT YOU CAN CHANGE:`n"
                        $repairMessage += "- Fix syntax errors causing the specific failures`n"
                        $repairMessage += "- Correct variable scoping issues (add `$global: if needed for cross-block variables)`n"
                        $repairMessage += "- Fix array operations (`$results.Count → `$results.Status.Count if needed)`n"
                        $repairMessage += "- Correct boolean skip conditions`n"
                        $repairMessage += "- Fix Where-Object syntax if causing errors`n"
                        $repairMessage += "- Adjust assertion syntax if failing`n`n"

                        $repairMessage += "FAILURES TO FIX:`n"

                        foreach ($failure in $failures) {
                            $repairMessage += "`nFAILURE: $($failure.TestName)`n"
                            $repairMessage += "ERROR: $($failure.ErrorMessage)`n"
                            if ($failure.LineNumber) {
                                $repairMessage += "LINE: $($failure.LineNumber)`n"
                            }
                        }

                        $repairMessage += "`n`nREFERENCE (DEVELOPMENT BRANCH):`n"
                        $repairMessage += "The working version is provided for comparison of test logic only. Do NOT copy its structure - it may be older Pester v4 format without our current styling. Use it only to understand what the test SHOULD accomplish.`n`n"

                        $repairMessage += "TASK: Make the minimal code changes necessary to fix only the specific failures above while preserving all existing Pester v5 migration work and dbatools styling conventions."

                        # Prepare context files for Claude
                        $contextFiles = @()
                        if (Test-Path $workingTempPath) {
                            $contextFiles += $workingTempPath
                        }
                        if ($commandSourcePath -and (Test-Path $commandSourcePath)) {
                            $contextFiles += $commandSourcePath
                        }

                        # Get the path to the failing test file
                        $failingTestPath = Resolve-Path "tests/$testFileName" -ErrorAction SilentlyContinue
                        if (-not $failingTestPath) {
                            Write-Warning "Could not find failing test file: tests/$testFileName"
                            continue
                        }

                        # Use Invoke-AITool to fix the test
                        $aiParams = @{
                            Message      = $repairMessage
                            File         = $failingTestPath.Path
                            Model        = $Model
                            Tool         = 'Claude'
                            ContextFiles = $contextFiles
                        }
                        # verbose the parameters
                        Write-Verbose "Invoking Claude with parameters: $($aiParams | Out-String)"
                        Write-Verbose "Invoking Claude with Message: $($aiParams.Message)"
                        Write-Verbose "Invoking Claude with ContextFiles: $($contextFiles -join ', ')"

                        try {
                            Invoke-AITool @aiParams
                        } catch {
                            Write-Warning "Claude failed with context files, retrying without command source file: $($_.Exception.Message)"

                            # Retry without the command source file - only include working test file
                            $retryContextFiles = @()
                            if (Test-Path $workingTempPath) {
                                $retryContextFiles += $workingTempPath
                            }

                            $retryParams = @{
                                Message      = $repairMessage
                                File         = $failingTestPath.Path
                                Model        = $Model
                                Tool         = 'Claude'
                                ContextFiles = $retryContextFiles
                            }

                            Write-Verbose "Retrying with reduced context files: $($retryContextFiles -join ', ')"
                            Invoke-AITool @retryParams
                        }

                        Update-PesterTest -InputObject $failingTestPath.Path
                    }

                    $processedFailures += $fileFailureCount

                    # Clear the detailed progress for this file
                    Write-Progress -Activity "Fixing Tests in $testFileName" -Completed -Id 2
                    Write-Progress -Activity "Fixing Tests in $testFileName" -Status "Completed $testFileName ($processedFailures of $totalFailures total failures processed)" -PercentComplete 100 -Id 1 -ParentId 0
                }

                # Clear the file-level progress
                Write-Progress -Activity "Fixing Tests in $testFileName" -Completed -Id 1

                # Commit changes if requested
                if ($AutoCommit) {
                    Write-Progress -Activity "Repairing Pull Request Tests" -Status "Committing fixes for PR #$($pr.number)..." -PercentComplete $prProgress -Id 0
                    $changedFiles = git diff --name-only 2>$null
                    if ($changedFiles) {
                        Write-Verbose "Committing fixes..."
                        git add -A 2>$null | Out-Null
                        git commit -m "Fix failing Pester tests (automated fix via Claude AI)" 2>$null | Out-Null
                        Write-Verbose "Changes committed successfully"
                    }
                }

                # After processing this PR, explicitly return to original branch
                Write-Verbose "Finished processing PR #$($pr.number), returning to original branch '$originalBranch'"
                git checkout $originalBranch 2>$null | Out-Null

                $afterPRComplete = git rev-parse --abbrev-ref HEAD 2>$null
                Write-Verbose "After PR completion, now on: '$afterPRComplete'"
            }

            # Complete the overall progress
            Write-Progress -Activity "Repairing Pull Request Tests" -Status "Completed processing $totalPRs PR(s)" -PercentComplete 100 -Id 0
            Write-Progress -Activity "Repairing Pull Request Tests" -Completed -Id 0

        } finally {
            # Clear any remaining progress bars
            Write-Progress -Activity "Repairing Pull Request Tests" -Completed -Id 0
            Write-Progress -Activity "Fixing Tests" -Completed -Id 1
            Write-Progress -Activity "Individual Test Fix" -Completed -Id 2

            # Return to original branch with extra verification
            $finalCurrentBranch = git rev-parse --abbrev-ref HEAD 2>$null
            Write-Verbose "In finally block, currently on: '$finalCurrentBranch', should return to: '$originalBranch'"

            if ($finalCurrentBranch -ne $originalBranch) {
                Write-Verbose "Returning to original branch: $originalBranch"
                git checkout $originalBranch 2>$null | Out-Null

                # Verify the final checkout worked
                $verifyFinal = git rev-parse --abbrev-ref HEAD 2>$null
                Write-Verbose "After final checkout, now on: '$verifyFinal'"

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
                Write-Verbose "Cleaned up temp directory: $tempDir"
            }
        }
    }
}