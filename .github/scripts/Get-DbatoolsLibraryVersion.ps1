<#
.SYNOPSIS
    Gets the dbatools.library version to use in GitHub Actions workflows
.DESCRIPTION
    This script determines which version of dbatools.library to use based on:
    1. Workflow dispatch input (highest priority)
    2. Remote branch version file (for preview versions)
    3. Local version configuration file (default)
.PARAMETER WorkflowInputVersion
    Version passed from workflow_dispatch input
.PARAMETER RemoteBranch
    Branch name to check for version override (e.g., 'preview-version')
.PARAMETER RemoteRepo
    Repository to check for remote version (default: 'dataplat/appveyor-lab')
.EXAMPLE
    .\Get-DbatoolsLibraryVersion.ps1
    Gets version from local config file

.EXAMPLE
    .\Get-DbatoolsLibraryVersion.ps1 -WorkflowInputVersion "2024.5.1-preview"
    Uses the specified version

.EXAMPLE
    .\Get-DbatoolsLibraryVersion.ps1 -RemoteBranch "preview-2024.5.1"
    Checks for version file in remote branch
#>
[CmdletBinding()]
param(
    [string]$WorkflowInputVersion,
    [string]$RemoteBranch,
    [string]$RemoteRepo = 'dataplat/appveyor-lab'
)

# Priority 1: Use workflow input if provided
if ($WorkflowInputVersion) {
    Write-Host "Using workflow input version: $WorkflowInputVersion"
    return $WorkflowInputVersion
}

# Priority 2: Check remote branch if specified
if ($RemoteBranch -and $RemoteRepo) {
    try {
        $versionUrl = "https://raw.githubusercontent.com/$RemoteRepo/$RemoteBranch/dbatools-library-version.txt"
        Write-Host "Checking remote branch for version: $versionUrl"
        
        $remoteVersion = Invoke-RestMethod -Uri $versionUrl -ErrorAction Stop
        $remoteVersion = $remoteVersion.Trim()
        
        if ($remoteVersion) {
            Write-Host "Using remote branch version: $remoteVersion"
            return $remoteVersion
        }
    }
    catch {
        Write-Host "Could not fetch version from remote branch: $_"
        Write-Host "Falling back to local configuration"
    }
}

# Priority 3: Use local configuration file
$configPath = Join-Path $PSScriptRoot ".." "dbatools-library-version.json"
if (Test-Path $configPath) {
    $config = Get-Content $configPath | ConvertFrom-Json
    Write-Host "Using config file version: $($config.version)"
    return $config.version
}

# Fallback: Return default version
Write-Warning "No version configuration found, using default: 2024.4.12"
return "2024.4.12"