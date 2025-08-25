# set-registry.ps1
# Sets required environment variables for GitHub Actions runner setup

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Write-Host $logMessage -ForegroundColor Cyan
    Add-Content -Path "C:\set-registry.log" -Value $logMessage -ErrorAction SilentlyContinue
}

try {
    Write-Log "=== Setting Registry Environment Variables ==="

    # Set environment variables
    [Environment]::SetEnvironmentVariable("VMSS_GH_TOKEN", "--VMSS_GH_TOKEN--", "Machine")
    [Environment]::SetEnvironmentVariable("GITHUB_REPOSITORY", "--GITHUB_REPOSITORY--", "Machine")
    [Environment]::SetEnvironmentVariable("BUILD_ID", "--BUILD_ID--", "Machine")
    [Environment]::SetEnvironmentVariable("VMSS_NAME", "--VMSS_NAME--", "Machine")

    Write-Log "Environment variables set successfully:"
    Write-Log "  VMSS_GH_TOKEN: [MASKED]"
    Write-Log "  GITHUB_REPOSITORY: --GITHUB_REPOSITORY--"
    Write-Log "  BUILD_ID: --BUILD_ID--"
    Write-Log "  VMSS_NAME: --VMSS_NAME--"

    # Reload environment variables for current session
    $env:VMSS_GH_TOKEN = [Environment]::GetEnvironmentVariable("VMSS_GH_TOKEN", "Machine")
    $env:GITHUB_REPOSITORY = [Environment]::GetEnvironmentVariable("GITHUB_REPOSITORY", "Machine")
    $env:BUILD_ID = [Environment]::GetEnvironmentVariable("BUILD_ID", "Machine")
    $env:VMSS_NAME = [Environment]::GetEnvironmentVariable("VMSS_NAME", "Machine")

    Write-Log "Environment variables loaded into current session"
    Write-Log "=== Registry Setup Completed Successfully ==="

    exit 0

} catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)"
    exit 1
}