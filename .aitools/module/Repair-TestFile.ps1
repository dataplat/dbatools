function Repair-TestFile {
    <#
    .SYNOPSIS
        Repairs a specific test file using AI tools.

    .DESCRIPTION
        Takes a test file with known failures and uses AI to fix the issues by comparing
        with a working version from the development branch.

    .PARAMETER TestFileName
        Name of the test file to repair.

    .PARAMETER Failures
        Array of failure objects containing error details.

    .PARAMETER Model
        AI model to use for repairs.

    .PARAMETER OriginalBranch
        The original branch to return to after repairs.

    .NOTES
        Tags: Testing, Pester, Repair, AI
        Author: dbatools team
        Requires: git, AI tools (Claude/Aider)
    #>
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