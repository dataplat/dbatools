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
        Default: claude-3-5-sonnet-20241022

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
        [string]$Model = "claude-3-5-sonnet-20241022",
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

        # Store current branch to return to it later
        $originalBranch = git branch --show-current
        Write-Verbose "Current branch: $originalBranch"

        # Ensure gh CLI is available
        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
            throw "GitHub CLI (gh) is required but not found. Please install it first."
        }

        # Check gh auth status
        $ghAuthStatus = gh auth status 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Not authenticated with GitHub CLI. Please run 'gh auth login' first."
        }
    }

    process {
        try {
            # Get open PRs
            Write-Verbose "Fetching open pull requests..."

            if ($PRNumber) {
                $prsJson = gh pr view $PRNumber --json "number,title,headRefName,state,statusCheckRollup" 2>$null
                if (-not $prsJson) {
                    throw "Could not fetch PR #$PRNumber"
                }
                $prs = @($prsJson | ConvertFrom-Json)
            } else {
                $prsJson = gh pr list --state open --limit $MaxPRs --json "number,title,headRefName,state,statusCheckRollup"
                $prs = $prsJson | ConvertFrom-Json
            }

            Write-Verbose "Found $($prs.Count) open PR(s)"

            foreach ($pr in $prs) {
                Write-Verbose "`nProcessing PR #$($pr.number): $($pr.title)"

                # Check for AppVeyor failures
                $appveyorChecks = $pr.statusCheckRollup | Where-Object {
                    $_.context -like "*appveyor*" -and $_.state -match "PENDING|FAILURE"
                }

                if (-not $appveyorChecks) {
                    Write-Verbose "No AppVeyor failures found in PR #$($pr.number)"
                    continue
                }

                # Checkout PR branch
                Write-Verbose "Checking out branch: $($pr.headRefName)"
                git fetch origin $pr.headRefName
                git checkout $pr.headRefName

                # Get AppVeyor build details
                $failedTests = Get-AppVeyorFailure -PullRequest $pr.number

                if (-not $failedTests) {
                    Write-Verbose "Could not retrieve test failures from AppVeyor"
                    continue
                }

                # Group failures by test file
                $testGroups = $failedTests | Group-Object TestFile

                foreach ($group in $testGroups) {
                    $testFileName = $group.Name
                    $failures = $group.Group

                    Write-Verbose "  Fixing $testFileName with $($failures.Count) failure(s)"

                    if ($PSCmdlet.ShouldProcess($testFileName, "Fix failing tests using Claude")) {
                        Repair-TestFile -TestFileName $testFileName `
                            -Failures $failures `
                            -Model $Model `
                            -OriginalBranch $originalBranch
                    }
                }

                # Commit changes if requested
                if ($AutoCommit) {
                    $changedFiles = git diff --name-only
                    if ($changedFiles) {
                        Write-Verbose "Committing fixes..."
                        git add -A
                        git commit -m "Fix failing Pester tests (automated fix via Claude AI)"
                        Write-Verbose "Changes committed successfully"
                    }
                }
            }
        } finally {
            # Return to original branch
            Write-Verbose "`nReturning to original branch: $originalBranch"
            git checkout $originalBranch -q
        }
    }
}

function Get-AppVeyorFailure {
    <#
    .SYNOPSIS
        Gets the AppVeyor failure for specific pull request(s) or all open ones

    .DESCRIPTION
        Gets the AppVeyor failure for specific pull request(s) or all open ones if none specified

    .PARAMETER PullRequest
        The pull request number(s) to get the AppVeyor failure for. If not specified, gets all open PRs

    .EXAMPLE
        PS C:\> Get-AppVeyorFailure -PullRequest 1234

        Gets the AppVeyor failure for pull request 1234

    .EXAMPLE
        PS C:\> Get-AppVeyorFailure -PullRequest 1234, 5678

        Gets the AppVeyor failure for pull requests 1234 and 5678

    .EXAMPLE
        PS C:\> Get-AppVeyorFailure

        Gets the AppVeyor failure for all open pull requests
    #>
    param (
        [int[]]$PullRequest
    )

    # If no PullRequest numbers specified, get all open PRs
    if (-not $PullRequest) {
        Write-Verbose "No pull request numbers specified, getting all open PRs..."
        $prsJson = gh pr list --state open --json "number,title,headRefName,state,statusCheckRollup"
        if (-not $prsJson) {
            Write-Warning "No open pull requests found"
            return $null
        }
        $openPRs = $prsJson | ConvertFrom-Json
        $PullRequest = $openPRs | ForEach-Object { $_.number }
        Write-Verbose "Found $($PullRequest.Count) open PRs: $($PullRequest -join ', ')"
    }

    $allResults = @()

    # Loop through each PR number
    $prCount = 0
    foreach ($prNumber in $PullRequest) {
        $prCount++
        Write-Progress -Activity "Processing Pull Requests" -Status "PR #$prNumber ($prCount of $($PullRequest.Count))" -PercentComplete (($prCount / $PullRequest.Count) * 100)
        Write-Verbose "`nFetching AppVeyor build information for PR #$prNumber"

        # Get PR checks from GitHub
        $checksJson = gh pr checks $prNumber --json "name,state,link" 2>$null
        if (-not $checksJson) {
            Write-Warning "Could not fetch checks for PR #$prNumber"
            continue
        }

        $checks = $checksJson | ConvertFrom-Json
        $appveyorCheck = $checks | Where-Object { $_.name -like "*AppVeyor*" -and $_.state -match "PENDING|FAILURE" }

        if (-not $appveyorCheck) {
            Write-Verbose "No failing or pending AppVeyor builds found for PR #$prNumber"
            continue
        }

        # Parse AppVeyor build URL to get build ID
        if ($appveyorCheck.link -match '/project/[^/]+/[^/]+/builds/(\d+)') {
            $buildId = $Matches[1]
        } else {
            Write-Warning "Could not parse AppVeyor build ID from URL: $($appveyorCheck.link)"
            continue
        }

        # Fetch build details from AppVeyor API
        $apiUrl = "https://ci.appveyor.com/api/projects/sqlcollaborative/dbatools/builds/$buildId"

        try {
            $build = Invoke-RestMethod -Uri $apiUrl -Method Get
        } catch {
            Write-Warning "Failed to fetch AppVeyor build details: $_"
            continue
        }

        # Process each job (runner) in the build
        $jobCount = 0
        $failedJobs = $build.build.jobs | Where-Object { $_.status -eq "failed" }
        foreach ($job in $build.build.jobs) {
            if ($job.status -ne "failed") {
                continue
            }

            $jobCount++
            Write-Progress -Activity "Processing Pull Requests" -Status "PR #$prNumber ($prCount of $($PullRequest.Count))" -PercentComplete (($prCount / $PullRequest.Count) * 100) -CurrentOperation "Processing job $jobCount of $($failedJobs.Count): $($job.name)"
            Write-Verbose "Processing failed job: $($job.name)"

            # Get job details including test results
            $jobApiUrl = "https://ci.appveyor.com/api/projects/sqlcollaborative/dbatools/builds/$buildId/jobs/$($job.jobId)"

            try {
                $jobDetails = Invoke-RestMethod -Uri $jobApiUrl -Method Get
            } catch {
                Write-Warning "Failed to fetch job details for $($job.jobId): $_"
                continue
            }

            # Parse test results from messages
            foreach ($message in $jobDetails.messages) {
                if ($message.message -match 'Failed: (.+?)\.Tests\.ps1:(\d+)') {
                    $testName = $Matches[1]
                    $lineNumber = $Matches[2]

                    [PSCustomObject]@{
                        TestFile     = "$testName.Tests.ps1"
                        Command      = $testName
                        LineNumber   = $lineNumber
                        Runner       = $job.name
                        ErrorMessage = $message.message
                        JobId        = $job.jobId
                        PRNumber     = $prNumber
                    }
                }
                # Alternative pattern for Pester output
                elseif ($message.message -match '\[-\] (.+?) \d+ms \((\d+)ms\|(\d+)ms\)' -and
                    $message.level -eq 'Error') {
                    # Extract test name from context
                    if ($message.message -match 'in (.+?)\.Tests\.ps1:(\d+)') {
                        $testName = $Matches[1]
                        $lineNumber = $Matches[2]

                        [PSCustomObject]@{
                            TestFile     = "$testName.Tests.ps1"
                            Command      = $testName
                            LineNumber   = $lineNumber
                            Runner       = $job.name
                            ErrorMessage = $message.message
                            JobId        = $job.jobId
                            PRNumber     = $prNumber
                        }
                    }
                }
            }
        }
    }

    # Complete the progress
    Write-Progress -Activity "Processing Pull Requests" -Completed
}

function Repair-TestFile {
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
    $commandPath = Get-ChildItem -Path (Join-Path (Get-Location) "public") -Filter "$commandName.ps1" -Recurse |
        Select-Object -First 1 -ExpandProperty FullName

    if (-not $commandPath) {
        $commandPath = Get-ChildItem -Path (Join-Path (Get-Location) "private") -Filter "$commandName.ps1" -Recurse |
            Select-Object -First 1 -ExpandProperty FullName
    }

    # Get the working test from Development branch
    Write-Verbose "Fetching working test from development branch"
    $workingTest = git show "development:tests/$TestFileName" 2>$null

    if (-not $workingTest) {
        Write-Warning "Could not fetch working test from development branch"
        $workingTest = "# Working test from development branch not available"
    }

    # Get current (failing) test content
    $failingTest = Get-Content $testPath -Raw

    # Get command implementation if found
    $commandImplementation = if ($commandPath -and (Test-Path $commandPath)) {
        Get-Content $commandPath -Raw
    } else {
        "# Command implementation not found"
    }

    # Build failure details
    $failureDetails = $Failures | ForEach-Object {
        @"
Runner: $($_.Runner)
Line: $($_.LineNumber)
Error: $($_.ErrorMessage)
"@
    } | Out-String

    # Create the prompt for Claude
    $prompt = @"
Fix the failing Pester v5 test file. This test was working in the development branch but is failing in the current PR.

## IMPORTANT CONTEXT
- This is a Pester v5 test file that needs to be fixed
- The test was working in development branch but failing after changes in this PR
- Focus on fixing the specific failures while maintaining Pester v5 compatibility
- Common issues include: scope problems, mock issues, parameter validation changes

## FAILURES DETECTED
The following failures occurred across different test runners:
$failureDetails

## COMMAND IMPLEMENTATION
Here is the actual PowerShell command being tested:
``````powershell
$commandImplementation
``````

## WORKING TEST FROM DEVELOPMENT BRANCH
This version was working correctly:
``````powershell
$workingTest
``````

## CURRENT FAILING TEST (THIS IS THE FILE TO FIX)
Fix this test file to resolve all the failures:
``````powershell
$failingTest
``````

## INSTRUCTIONS
1. Analyze the differences between working and failing versions
2. Identify what's causing the failures based on the error messages
3. Fix the test while maintaining Pester v5 best practices
4. Ensure all parameter validations match the command implementation
5. Keep the same test structure and coverage as the original
6. Pay special attention to BeforeAll/BeforeEach blocks and variable scoping
7. Ensure mocks are properly scoped and implemented for Pester v5

Please fix the test file to resolve all failures.
"@

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