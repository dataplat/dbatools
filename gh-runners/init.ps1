<#
.SYNOPSIS
    GitHub Actions runner configuration script for Azure VMSS
.DESCRIPTION
    This script runs on VM startup via CustomScriptExtension.
    It configures the pre-installed GitHub Actions runner at C:\actions-runner
    and starts it in ephemeral mode (auto-destroy after one job).
.NOTES
    - Runner binaries are pre-installed in golden image at C:\actions-runner
    - Uses VM managed identity to access Key Vault
    - Configures runner as ephemeral (--ephemeral flag)
    - Runner auto-unregisters after completing one job
#>

$ErrorActionPreference = "Stop"
$RunnerDir = "C:\actions-runner"

# Logging function
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
}

try {
    Write-Log "=== GitHub Actions Runner Setup Starting ==="

    # Verify runner directory exists
    if (-not (Test-Path $RunnerDir)) {
        throw "Runner directory not found at $RunnerDir. Golden image may be corrupted."
    }

    Write-Log "Installing Azure PowerShell modules..."
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
    Install-Module -Name Az.Accounts -Force -AllowClobber -Repository PSGallery -Scope CurrentUser | Out-Null
    Install-Module -Name Az.KeyVault -Force -AllowClobber -Repository PSGallery -Scope CurrentUser | Out-Null
    Write-Log "Azure PowerShell modules installed"

    Write-Log "Authenticating with managed identity..."
    $null = Connect-AzAccount -Identity
    Write-Log "Successfully authenticated"

    # Get VM metadata to determine configuration
    Write-Log "Retrieving VM metadata..."
    $metadata = Invoke-RestMethod `
        -Uri "http://169.254.169.254/metadata/instance?api-version=2021-02-01" `
        -Headers @{Metadata="true"} `
        -TimeoutSec 10

    # Configuration (hardcoded since these don't change)
    $KeyVaultName = "dbatoolsci"
    $GithubOrg = "dataplat"
    $Repository = "dbatools"

    Write-Log "Configuration:"
    Write-Log "  - Key Vault: $KeyVaultName"
    Write-Log "  - Organization: $GithubOrg"
    Write-Log "  - Repository: $Repository"
    Write-Log "  - Runner Group: Default (no custom group)"
    Write-Log "  - VM Name: $($env:COMPUTERNAME)"

    Write-Log "Retrieving GitHub PAT from Key Vault..."
    $secretObj = Get-AzKeyVaultSecret `
        -VaultName $KeyVaultName `
        -Name "GITHUB-RUNNER-TOKEN"

    if (-not $secretObj) {
        throw "Failed to retrieve GitHub token from Key Vault"
    }

    # PS 3.0 compatible way to get plaintext secret
    $GithubToken = $secretObj.SecretValueText
    Write-Log "GitHub PAT retrieved successfully"

    Write-Log "Requesting runner registration token from GitHub API..."
    $headers = @{
        "Accept"               = "application/vnd.github+json"
        "Authorization"        = "Bearer $GithubToken"
        "X-GitHub-Api-Version" = "2022-11-28"
    }

    $tokenResponse = Invoke-RestMethod `
        -Uri "https://api.github.com/repos/$GithubOrg/$Repository/actions/runners/registration-token" `
        -Method Post `
        -Headers $headers `
        -TimeoutSec 30

    $RegistrationToken = $tokenResponse.token
    if (-not $RegistrationToken) {
        throw "Failed to obtain registration token from GitHub"
    }
    Write-Log "Registration token obtained"

    Write-Log "Changing directory to $RunnerDir"
    Set-Location $RunnerDir

    # Remove existing runner configuration if present
    if (Test-Path ".\.runner") {
        Write-Log "Existing runner configuration found, removing..."
        try {
            & .\config.cmd remove --token $RegistrationToken 2>&1 | Out-Null
        } catch {
            Write-Log "Failed to remove existing config (may not exist): $_" -Level "WARN"
        }
    }

    Write-Log "Configuring GitHub Actions runner (ephemeral mode)..."
    $configArgs = @(
        "--unattended",
        "--url", "https://github.com/$GithubOrg/$Repository",
        "--token", $RegistrationToken,
        "--name", $env:COMPUTERNAME,
        "--labels", "self-hosted,azure-vmss,windows,sqlserver",
        "--work", "_work",
        "--ephemeral",
        "--replace"
    )

    & .\config.cmd $configArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Runner configuration failed with exit code $LASTEXITCODE"
    }
    Write-Log "Runner configured successfully"

    Write-Log "Starting runner (will auto-destroy after completing one job)..."
    Write-Log "=== Runner Starting - This VM will terminate after job completion ==="

    # Run the runner (blocking call until job completes)
    & .\run.cmd

    $exitCode = $LASTEXITCODE
    Write-Log "Runner exited with code: $exitCode"

    if ($exitCode -eq 0) {
        Write-Log "=== Runner completed successfully ===" -Level "SUCCESS"
    } else {
        Write-Log "=== Runner exited with error ===" -Level "ERROR"
    }

    exit $exitCode

} catch {
    Write-Log "FATAL ERROR: $_" -Level "ERROR"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level "ERROR"
    exit 1
}
