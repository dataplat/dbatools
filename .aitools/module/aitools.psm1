#Requires -Version 5.1

<#
.SYNOPSIS
    dbatools AI Tools Module

.DESCRIPTION
    This module provides AI-powered tools for dbatools development, including:
    - Pull request test repair using Claude AI
    - AppVeyor build status monitoring
    - Pester test migration to v5
    - Automated code quality fixes
    - Test failure analysis and repair

.NOTES
    Tags: AI, Testing, Pester, CI/CD, AppVeyor
    Author: dbatools team
    Requires: PowerShell 5.1+, gh CLI, git
#>

# Set module-wide variables
$PSDefaultParameterValues['Import-Module:Verbose'] = $false

# Auto-configure aider environment variables for .aitools directory
try {
    # Use Join-Path instead of Resolve-Path to avoid "path does not exist" errors
    $env:AIDER_CONFIG_FILE = Join-Path $PSScriptRoot "../.aitools/.aider.conf.yml"
    $env:AIDER_ENV_FILE = Join-Path $PSScriptRoot "../.aitools/.env"
    $env:AIDER_MODEL_SETTINGS_FILE = Join-Path $PSScriptRoot "../.aitools/.aider.model.settings.yml"

    # Ensure .aider directory exists before setting history file paths
    $aiderDir = Join-Path $PSScriptRoot "../.aitools/.aider"
    if (-not (Test-Path $aiderDir)) {
        New-Item -Path $aiderDir -ItemType Directory -Force | Out-Null
        Write-Verbose "Created .aider directory: $aiderDir"
    }

    $env:AIDER_INPUT_HISTORY_FILE = Join-Path $aiderDir "aider.input.history"
    $env:AIDER_CHAT_HISTORY_FILE = Join-Path $aiderDir "aider.chat.history.md"
    $env:AIDER_LLM_HISTORY_FILE = Join-Path $aiderDir "aider.llm.history"

    # Create empty history files if they don't exist
    @($env:AIDER_INPUT_HISTORY_FILE, $env:AIDER_CHAT_HISTORY_FILE, $env:AIDER_LLM_HISTORY_FILE) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -Path $_ -ItemType File -Force | Out-Null
            Write-Verbose "Created aider history file: $_"
        }
    }

    Write-Verbose "Aider environment configured for .aitools directory"
} catch {
    Write-Verbose "Could not configure aider environment: $_"
}

# Import all function files
$functionFiles = @(
    # Major commands
    'Repair-PullRequestTest.ps1',
    'Show-AppVeyorBuildStatus.ps1',
    'Get-AppVeyorFailures.ps1',
    'Update-PesterTest.ps1',
    'Invoke-AITool.ps1',
    'Invoke-AutoFix.ps1',
    'Repair-Error.ps1',
    'Repair-SmallThing.ps1',

    # Helper functions
    'Invoke-AppVeyorApi.ps1',
    'Get-AppVeyorFailure.ps1',
    'Repair-TestFile.ps1',
    'Get-TargetPRs.ps1',
    'Get-FailedBuilds.ps1',
    'Get-BuildFailures.ps1',
    'Get-JobFailures.ps1',
    'Get-TestArtifacts.ps1',
    'Parse-TestArtifact.ps1',
    'Format-TestFailures.ps1',
    'Invoke-AutoFixSingleFile.ps1',
    'Invoke-AutoFixProcess.ps1'
)

foreach ($file in $functionFiles) {
    $filePath = Join-Path $PSScriptRoot $file
    if (Test-Path $filePath) {
        Write-Verbose "Importing function from: $file"
        . $filePath
    } else {
        Write-Warning "Function file not found: $filePath"
    }
}

# Export public functions
$publicFunctions = @(
    'Repair-PullRequestTest',
    'Show-AppVeyorBuildStatus',
    'Get-AppVeyorFailures',
    'Update-PesterTest',
    'Invoke-AITool',
    'Invoke-AutoFix',
    'Repair-Error',
    'Repair-SmallThing'
)

Export-ModuleMember -Function $publicFunctions

Write-Verbose "dbatools AI Tools module loaded successfully"