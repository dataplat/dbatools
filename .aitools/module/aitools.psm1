#Requires -Version 5.1

<#
.SYNOPSIS
    AI Tools Module

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

# Set the module path to the dbatools root directory (two levels up from .aitools/module)
$script:ModulePath = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

# Auto-configure aider environment variables for .aitools directory
try {
    # Use Join-Path instead of Resolve-Path to avoid "path does not exist" errors
    $env:AIDER_CONFIG_FILE = Join-Path $PSScriptRoot "../.aider.conf.yml"
    $env:AIDER_ENV_FILE = Join-Path $PSScriptRoot "../.env"
    $env:AIDER_MODEL_SETTINGS_FILE = Join-Path $PSScriptRoot "../.aider.model.settings.yml"

    # Ensure .aider directory exists before setting history file paths
    $aiderDir = Join-Path $PSScriptRoot "../.aider"
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

$functionFiles = Get-ChildItem -Path $PSScriptRoot -Filter '*.ps1' -File -Recurse

foreach ($file in $functionFiles) {
    if (Test-Path $file.FullName) {
        Write-Verbose "Importing function from: $file"
        . $file.FullName
    } else {
        Write-Warning "Function file not found: $filePath"
    }
}

Export-ModuleMember -Function $functionFiles.BaseName

Write-Verbose "dbatools AI Tools module loaded successfully"