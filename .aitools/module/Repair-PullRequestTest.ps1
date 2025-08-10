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
        [string]$Model = "claude-sonnet-4-20250514",
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
                git stash
                $needsStash = $true
            } else {
                Write-Verbose "No uncommitted changes to stash"
            }

            # Batch copy all working test files from development branch
            Write-Progress -Activity "Repairing Pull Request Tests" -Status "Getting working test files from development branch..." -PercentComplete 25 -Id 0
            Write-Verbose "Switching to development branch to copy all working test files"
            git checkout development 2>$null | Out-Null

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
                git checkout $originalBranch 2>$null | Out-Null
            }

            # Unstash if we stashed earlier
            if ($needsStash) {
                Write-Verbose "Restoring stashed changes"
                git stash pop 2>$null | Out-Null
            }

            # Now process each unique file once with ALL its errors

            # Now process each unique file once with ALL its errors
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

                Write-Progress -Activity "Fixing Unique Test Files" -Status "Processing $fileName ($($allFailuresForFile.Count) failures)" -PercentComplete $fileProgress -Id 1
                Write-Verbose "Processing $fileName with $($allFailuresForFile.Count) total failure(s)"

                if ($PSCmdlet.ShouldProcess($fileName, "Fix failing tests using Claude")) {
                    # Get the pre-copied working test file
                    $workingTempPath = Join-Path $tempDir "working-$fileName"
                    if (-not (Test-Path $workingTempPath)) {
                        Write-Warning "Working test file not found in temp directory: $workingTempPath"
                    }

                    # Get the command source file path (from current branch)
                    $commandName = [System.IO.Path]::GetFileNameWithoutExtension($fileName) -replace '\.Tests$', ''
                    Write-Progress -Activity "Fixing $fileName" -Status "Getting command source for $commandName" -PercentComplete 20 -Id 2 -ParentId 1

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

                    # Build the repair message with ALL failures for this file
                    $repairMessage = "You are fixing ALL the test failures in $fileName. This test has already been migrated to Pester v5 and styled according to dbatools conventions.`n`n"

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

                    $repairMessage += "PESTER v5 STRUCTURAL PROBLEMS TO CONSIDER:`n"
                    $repairMessage += "If you only see generic failure messages like 'Test failed but no error message could be extracted' or 'Result: Failed' with no ErrorRecord/StackTrace, this indicates Pester v5 architectural issues:`n"
                    $repairMessage += "- Mocks defined at script level instead of in BeforeAll{} blocks`n"
                    $repairMessage += "- [Parameter()] attributes on test parameters (remove these)`n"
                    $repairMessage += "- Variables/functions not accessible during Run phase due to discovery/run separation`n"
                    $repairMessage += "- Should -Throw assertions with square brackets or special characters that break pattern matching`n"
                    $repairMessage += "- Mock scope issues where mocks aren't available to the functions being tested`n`n"

                    $repairMessage += "WHAT YOU CAN CHANGE:`n"
                    $repairMessage += "- Fix syntax errors causing the specific failures`n"
                    $repairMessage += "- Correct variable scoping issues (add `$global: if needed for cross-block variables)`n"
                    $repairMessage += "- Move mock definitions from script level into BeforeAll{} blocks`n"
                    $repairMessage += "- Remove [Parameter()] attributes from test parameters`n"
                    $repairMessage += "- Fix array operations (`$results.Count → `$results.Status.Count if needed)`n"
                    $repairMessage += "- Correct boolean skip conditions`n"
                    $repairMessage += "- Fix Where-Object syntax if causing errors`n"
                    $repairMessage += "- Adjust assertion syntax if failing`n"
                    $repairMessage += "- Escape special characters in Should -Throw patterns or use wildcards`n`n"

                    $repairMessage += "ALL FAILURES TO FIX IN THIS FILE:`n"

                    foreach ($failure in $allFailuresForFile) {
                        $repairMessage += "`nFAILURE - $($failure.TestName)`n"
                        $repairMessage += "ERROR - $($failure.ErrorMessage)`n"
                        if ($failure.LineNumber) {
                            $repairMessage += "LINE - $($failure.LineNumber)`n"
                        }
                    }

                    $repairMessage += "`n`nREFERENCE (DEVELOPMENT BRANCH):`n"
                    $repairMessage += "The working version is provided for comparison of test logic only. Do NOT copy its structure - it may be older Pester v4 format without our current styling. Use it only to understand what the test SHOULD accomplish.`n`n"

                    $repairMessage += "TASK - Make the minimal code changes necessary to fix ALL the failures above while preserving all existing Pester v5 migration work and dbatools styling conventions."
                    # Prepare context files for Claude
                    $contextFiles = @()
                    if (Test-Path $workingTempPath) {
                        $contextFiles += $workingTempPath
                    }
                    if ($commandSourcePath -and (Test-Path $commandSourcePath)) {
                        $contextFiles += $commandSourcePath
                    }

                    # Get the path to the failing test file
                    $failingTestPath = Resolve-Path "tests/$fileName" -ErrorAction SilentlyContinue
                    if (-not $failingTestPath) {
                        Write-Warning "Could not find failing test file - tests/$fileName"
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

                    Write-Verbose "Invoking Claude for $fileName with $($allFailuresForFile.Count) failures"

                    Write-Progress -Activity "Fixing $fileName" -Status "Running Claude AI to fix $($allFailuresForFile.Count) failures..." -PercentComplete 50 -Id 2 -ParentId 1

                    try {
                        Invoke-AITool @aiParams

                        # Mark this file as processed
                        $processedFiles[$fileName] = $true
                        Write-Verbose "Successfully processed $fileName"

                    } catch {
                        Write-Warning "Claude failed with context files for ${fileName}, retrying without command source file - $($_.Exception.Message)"

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

                        Write-Verbose "Retrying $fileName with reduced context files"
                        try {
                            Invoke-AITool @retryParams
                            $processedFiles[$fileName] = $true
                            Write-Verbose "Successfully processed $fileName on retry"
                        } catch {
                            Write-Warning "Failed to process $fileName even on retry - $($_.Exception.Message)"
                        }
                    }


                    Write-Progress -Activity "Fixing $fileName" -Status "Reformatting" -PercentComplete 90 -Id 2 -ParentId 1

                    # Update-PesterTest -InputObject $failingTestPath.Path
                    $null = Get-ChildItem $failingTestPath.Path | Invoke-DbatoolsFormatter

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
                    git commit -m "Fix failing Pester tests across multiple files (automated fix via Claude AI)" 2>$null | Out-Null
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