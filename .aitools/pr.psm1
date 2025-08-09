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

        Write-Verbose "Original branch detected as: '$originalBranch'" -ForegroundColor Yellow
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
                $prsJson = gh pr view $PRNumber --json "number,title,headRefName,state,statusCheckRollup" 2>$null
                if (-not $prsJson) {
                    throw "Could not fetch PR #$PRNumber"
                }
                $prs = @($prsJson | ConvertFrom-Json)
            } else {
                $prsJson = gh pr list --state open --limit $MaxPRs --json "number,title,headRefName,state,statusCheckRollup" 2>$null
                $prs = $prsJson | ConvertFrom-Json
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
                Write-Verbose "After checkout, now on branch: '$afterCheckout'" -ForegroundColor Yellow

                if ($afterCheckout -ne $pr.headRefName) {
                    Write-Warning "Failed to checkout PR branch '$($pr.headRefName)'. Currently on '$afterCheckout'. Skipping this PR."
                    continue
                }

                # Get AppVeyor build details
                Write-Progress -Activity "Repairing Pull Request Tests" -Status "Fetching test failures from AppVeyor..." -PercentComplete $prProgress -Id 0
                $getFailureParams = @{
                    PullRequest = $pr.number
                }
                $failedTests = Get-AppVeyorFailure @getFailureParams

                if (-not $failedTests) {
                    Write-Verbose "Could not retrieve test failures from AppVeyor"
                    continue
                }

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
                        $repairMessage = "Fix the following test failures in $testFileName`:`n`n"

                        foreach ($failure in $failures) {
                            $repairMessage += "FAILURE: $($failure.TestName)`n"
                            $repairMessage += "ERROR: $($failure.ErrorMessage)`n"
                            if ($failure.LineNumber) {
                                $repairMessage += "LINE: $($failure.LineNumber)`n"
                            }
                            $repairMessage += "`n"
                        }

                        $repairMessage += "Please analyze the failing test file and fix the issues. "

                        if (Test-Path $workingTempPath) {
                            $repairMessage += "Use the working version from the Development branch as reference for comparison. "
                        }

                        if ($commandSourcePath) {
                            $repairMessage += "The command source file is also provided for context about the actual implementation."
                        }

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

                        Write-Verbose "Invoking Claude to fix test failures"
                        Invoke-AITool @aiParams
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
                Write-Verbose "Finished processing PR #$($pr.number), returning to original branch '$originalBranch'" -ForegroundColor Yellow
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
            Write-Verbose "In finally block, currently on: '$finalCurrentBranch', should return to: '$originalBranch'" -ForegroundColor Yellow

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
function Invoke-AppVeyorApi {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Endpoint,

        [string]$AccountName = 'dataplat',

        [string]$Method = 'Get'
    )

    # Check for API token
    $apiToken = $env:APPVEYOR_API_TOKEN
    if (-not $apiToken) {
        Write-Warning "APPVEYOR_API_TOKEN environment variable not set."
        return
    }

    # Always use v1 base URL even with v2 tokens
    $baseUrl = "https://ci.appveyor.com/api"
    $fullUrl = "$baseUrl/$Endpoint"

    # Prepare headers
    $headers = @{
        'Authorization' = "Bearer $apiToken"
        'Content-Type'  = 'application/json'
        'Accept'        = 'application/json'
    }

    Write-Verbose "Making API call to: $fullUrl"

    try {
        $restParams = @{
            Uri         = $fullUrl
            Method      = $Method
            Headers     = $headers
            ErrorAction = 'Stop'
        }
        $response = Invoke-RestMethod @restParams
        return $response
    } catch {
        $errorMessage = "Failed to call AppVeyor API: $($_.Exception.Message)"

        if ($_.ErrorDetails.Message) {
            $errorMessage += " - $($_.ErrorDetails.Message)"
        }

        throw $errorMessage
    }
}

function Get-AppVeyorFailure {
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
        Write-Verbose "Found $($PullRequest.Count) open PRs: $($PullRequest -join ', ')"
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
                            ($line -match '\[-\]|\bfail|\berror|\bexception|Failed:|Error:' -or
                             $line -match 'should\s+(?:be|not|contain|match)' -or
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
                                ($line -match 'Exception|Error' -and $line -match '\.Tests\.ps1')) {

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
function Repair-TestFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$TestFileName,

        [Parameter(Mandatory)]
        [array]$Failures,

        [Parameter(Mandatory)]
        [string]$Model,

        [Parameter(Mandatory)]
        [string]$OriginalBranch
    )

    $testPath = Join-Path (Get-Location) "tests" $TestFileName
    if (-not (Test-Path $testPath)) {
        Write-Warning "Test file not found: $testPath"
        return
    }

    # Extract command name from test file name
    $commandName = [System.IO.Path]::GetFileNameWithoutExtension($TestFileName) -replace '\.Tests$', ''

    # Find the command implementation
    $publicParams = @{
        Path    = (Join-Path (Get-Location) "public")
        Filter  = "$commandName.ps1"
        Recurse = $true
    }
    $commandPath = Get-ChildItem @publicParams | Select-Object -First 1 -ExpandProperty FullName

    if (-not $commandPath) {
        $privateParams = @{
            Path    = (Join-Path (Get-Location) "private")
            Filter  = "$commandName.ps1"
            Recurse = $true
        }
        $commandPath = Get-ChildItem @privateParams | Select-Object -First 1 -ExpandProperty FullName
    }

    # Get the working test from Development branch
    Write-Verbose "Fetching working test from development branch"
    $workingTest = git show "development:tests/$TestFileName" 2>$null

    if (-not $workingTest) {
        Write-Warning "Could not fetch working test from development branch"
        $workingTest = "# Working test from development branch not available"
    }

    # Get current (failing) test content
    $contentParams = @{
        Path = $testPath
        Raw  = $true
    }
    $failingTest = Get-Content @contentParams

    # Get command implementation if found
    $commandImplementation = if ($commandPath -and (Test-Path $commandPath)) {
        $cmdContentParams = @{
            Path = $commandPath
            Raw  = $true
        }
        Get-Content @cmdContentParams
    } else {
        "# Command implementation not found"
    }

    # Build failure details
    $failureDetails = $Failures | ForEach-Object {
        "Runner: $($_.Runner)" +
        "`nLine: $($_.LineNumber)" +
        "`nError: $($_.ErrorMessage)"
    }
    $failureDetailsString = $failureDetails -join "`n`n"

    # Create the prompt for Claude
    $prompt = "Fix the failing Pester v5 test file. This test was working in the development branch but is failing in the current PR." +
              "`n`n## IMPORTANT CONTEXT" +
              "`n- This is a Pester v5 test file that needs to be fixed" +
              "`n- The test was working in development branch but failing after changes in this PR" +
              "`n- Focus on fixing the specific failures while maintaining Pester v5 compatibility" +
              "`n- Common issues include: scope problems, mock issues, parameter validation changes" +
              "`n`n## FAILURES DETECTED" +
              "`nThe following failures occurred across different test runners:" +
              "`n$failureDetailsString" +
              "`n`n## COMMAND IMPLEMENTATION" +
              "`nHere is the actual PowerShell command being tested:" +
              "`n``````powershell" +
              "`n$commandImplementation" +
              "`n``````" +
              "`n`n## WORKING TEST FROM DEVELOPMENT BRANCH" +
              "`nThis version was working correctly:" +
              "`n``````powershell" +
              "`n$workingTest" +
              "`n``````" +
              "`n`n## CURRENT FAILING TEST (THIS IS THE FILE TO FIX)" +
              "`nFix this test file to resolve all the failures:" +
              "`n``````powershell" +
              "`n$failingTest" +
              "`n``````" +
              "`n`n## INSTRUCTIONS" +
              "`n1. Analyze the differences between working and failing versions" +
              "`n2. Identify what's causing the failures based on the error messages" +
              "`n3. Fix the test while maintaining Pester v5 best practices" +
              "`n4. Ensure all parameter validations match the command implementation" +
              "`n5. Keep the same test structure and coverage as the original" +
              "`n6. Pay special attention to BeforeAll/BeforeEach blocks and variable scoping" +
              "`n7. Ensure mocks are properly scoped and implemented for Pester v5" +
              "`n`nPlease fix the test file to resolve all failures."

    # Use Invoke-AITool to fix the test
    Write-Verbose "Sending test to Claude for fixes"

    $aiParams = @{
        Message         = $prompt
        File            = $testPath
        Model           = $Model
        Tool            = 'Claude'
        ReasoningEffort = 'high'
    }

    try {
        Invoke-AITool @aiParams
        Write-Verbose "    ✓ Test file repaired successfully"
    } catch {
        Write-Error "Failed to repair test file: $_"
    }
}



function Show-AppVeyorBuildStatus {
    <#
    .SYNOPSIS
        Shows detailed AppVeyor build status for a specific build ID.

    .DESCRIPTION
        Retrieves and displays comprehensive build information from AppVeyor API v2,
        including build status, jobs, and test results with adorable formatting.

    .PARAMETER BuildId
        The AppVeyor build ID to retrieve status for

    .PARAMETER AccountName
        The AppVeyor account name. Defaults to 'dataplat'

    .EXAMPLE
        PS C:\> Show-AppVeyorBuildStatus -BuildId 12345

        Shows detailed status for AppVeyor build 12345 with maximum cuteness
    #>
    [CmdletBinding()]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost', '',
        Justification = 'Intentional: command renders a user-facing TUI with colors/emojis in CI.'
    )]
    param (
        [Parameter(Mandatory)]
        [string]$BuildId,

        [string]$AccountName = 'dataplat'
    )

    try {
        Write-Host "🔍 " -NoNewline -ForegroundColor Cyan
        Write-Host "Fetching AppVeyor build details..." -ForegroundColor Gray

        $apiParams = @{
            Endpoint    = "projects/dataplat/dbatools/builds/$BuildId"
            AccountName = $AccountName
        }
        $response = Invoke-AppVeyorApi @apiParams

        if ($response -and $response.build) {
            $build = $response.build

            # Header with fancy border
            Write-Host "`n╭─────────────────────────────────────────╮" -ForegroundColor Magenta
            Write-Host "│          🏗️  AppVeyor Build Status      │" -ForegroundColor Magenta
            Write-Host "╰─────────────────────────────────────────╯" -ForegroundColor Magenta

            # Build details with cute icons
            Write-Host "🆔 Build ID:   " -NoNewline -ForegroundColor Yellow
            Write-Host "$($build.buildId)" -ForegroundColor White

            # Status with colored indicators
            Write-Host "📊 Status:     " -NoNewline -ForegroundColor Yellow
            switch ($build.status.ToLower()) {
                'success' { Write-Host "✅ $($build.status)" -ForegroundColor Green }
                'failed' { Write-Host "❌ $($build.status)" -ForegroundColor Red }
                'running' { Write-Host "⚡ $($build.status)" -ForegroundColor Cyan }
                'queued' { Write-Host "⏳ $($build.status)" -ForegroundColor Yellow }
                default { Write-Host "❓ $($build.status)" -ForegroundColor Gray }
            }

            Write-Host "📦 Version:    " -NoNewline -ForegroundColor Yellow
            Write-Host "$($build.version)" -ForegroundColor White

            Write-Host "🌿 Branch:     " -NoNewline -ForegroundColor Yellow
            Write-Host "$($build.branch)" -ForegroundColor Green

            Write-Host "💾 Commit:     " -NoNewline -ForegroundColor Yellow
            Write-Host "$($build.commitId.Substring(0,8))" -ForegroundColor Cyan

            Write-Host "🚀 Started:    " -NoNewline -ForegroundColor Yellow
            Write-Host "$($build.started)" -ForegroundColor White

            if ($build.finished) {
                Write-Host "🏁 Finished:   " -NoNewline -ForegroundColor Yellow
                Write-Host "$($build.finished)" -ForegroundColor White
            }

            # Jobs section with adorable formatting
            if ($build.jobs) {
                Write-Host "`n╭─── 👷‍♀️ Jobs ───╮" -ForegroundColor Cyan
                foreach ($job in $build.jobs) {
                    Write-Host "│ " -NoNewline -ForegroundColor Cyan

                    # Job status icons
                    switch ($job.status.ToLower()) {
                        'success' { Write-Host "✨ " -NoNewline -ForegroundColor Green }
                        'failed' { Write-Host "💥 " -NoNewline -ForegroundColor Red }
                        'running' { Write-Host "🔄 " -NoNewline -ForegroundColor Cyan }
                        default { Write-Host "⭕ " -NoNewline -ForegroundColor Gray }
                    }

                    Write-Host "$($job.name): " -NoNewline -ForegroundColor White
                    Write-Host "$($job.status)" -ForegroundColor $(
                        switch ($job.status.ToLower()) {
                            'success' { 'Green' }
                            'failed' { 'Red' }
                            'running' { 'Cyan' }
                            default { 'Gray' }
                        }
                    )

                    if ($job.duration) {
                        Write-Host "│   ⏱️  Duration: " -NoNewline -ForegroundColor Cyan
                        Write-Host "$($job.duration)" -ForegroundColor Gray
                    }
                }
                Write-Host "╰────────────────╯" -ForegroundColor Cyan
            }

            Write-Host "`n🎉 " -NoNewline -ForegroundColor Green
            Write-Host "Build status retrieved successfully!" -ForegroundColor Green
        } else {
            Write-Host "⚠️  " -NoNewline -ForegroundColor Yellow
            Write-Host "No build data returned from AppVeyor API" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "`n💥 " -NoNewline -ForegroundColor Red
        Write-Host "Oops! Something went wrong:" -ForegroundColor Red
        Write-Host "   $($_.Exception.Message)" -ForegroundColor Gray

        if (-not $env:APPVEYOR_API_TOKEN) {
            Write-Host "`n🔑 " -NoNewline -ForegroundColor Yellow
            Write-Host "AppVeyor API Token Setup:" -ForegroundColor Yellow
            Write-Host "   1️⃣  Go to " -NoNewline -ForegroundColor Cyan
            Write-Host "https://ci.appveyor.com/api-token" -ForegroundColor Blue
            Write-Host "   2️⃣  Generate a new API token (v2)" -ForegroundColor Cyan
            Write-Host "   3️⃣  Set: " -NoNewline -ForegroundColor Cyan
            Write-Host "`$env:APPVEYOR_API_TOKEN = 'your-token'" -ForegroundColor White
        }
    }
}