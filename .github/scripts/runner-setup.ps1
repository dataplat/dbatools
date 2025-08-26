# runner-setup.ps1 - Simplified for Custom Script Extension
$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Write-Host $logMessage -ForegroundColor Green
    Add-Content -Path "C:\runner-setup.log" -Value $logMessage
}

function Get-KeyVaultSecret {
    param([string]$SecretName, [string]$KeyVaultName)

    # System-assigned identity - no client_id needed
    $tokenResponse = Invoke-RestMethod -Method Get `
        -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2021-02-01&resource=https://vault.azure.net' `
        -Headers @{Metadata = "true" }

    $uri = "https://$KeyVaultName.vault.azure.net/secrets/$SecretName?api-version=7.2"
    $response = Invoke-RestMethod -Method Get -Uri $uri `
        -Headers @{Authorization = "Bearer $($tokenResponse.access_token)" }

    return $response.value
}

try {
    Write-Log "=== GitHub Actions Runner Setup Starting ==="
    Write-Log "Machine: $env:COMPUTERNAME"

    # Get secrets from Key Vault (system identity)
    Write-Log "Retrieving secrets from Key Vault..."
    $env:GITHUB_REPOSITORY = Get-KeyVaultSecret -SecretName "GITHUB-REPOSITORY" -KeyVaultName "dbatoolsci"
    $env:RUNNER_TOKEN = Get-KeyVaultSecret -SecretName "GITHUB-RUNNER-TOKEN" -KeyVaultName "dbatoolsci"
    $env:BUILD_ID = Get-KeyVaultSecret -SecretName "GITHUB-BUILD-ID" -KeyVaultName "dbatoolsci"
    $env:VMSS_NAME = Get-KeyVaultSecret -SecretName "VMSS-NAME" -KeyVaultName "dbatoolsci"

    # Get instance metadata
    $instanceName = (Invoke-RestMethod -Uri "http://169.254.169.254/metadata/instance/compute/name?api-version=2021-02-01" `
            -Headers @{"Metadata" = "true" })

    # Create runner directory
    $runnerDir = "C:\actions-runner"
    if (Test-Path $runnerDir) { Remove-Item -Path $runnerDir -Recurse -Force }
    New-Item -ItemType Directory -Path $runnerDir -Force | Out-Null
    Set-Location $runnerDir

    # Download latest runner
    $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/actions/runner/releases/latest"
    $runnerVersion = $latestRelease.tag_name.TrimStart('v')
    $runnerUrl = "https://github.com/actions/runner/releases/download/v$runnerVersion/actions-runner-win-x64-$runnerVersion.zip"

    Write-Log "Downloading runner version: $runnerVersion"
    Invoke-WebRequest -Uri $runnerUrl -OutFile "actions-runner.zip"
    Expand-Archive -Path "actions-runner.zip" -DestinationPath . -Force
    Remove-Item "actions-runner.zip"

    # Configure runner
    $runnerName = "$env:VMSS_NAME-$instanceName-$env:BUILD_ID"
    $runnerLabels = "self-hosted,windows,sql-server,$env:VMSS_NAME,build-$env:BUILD_ID"

    Write-Log "Configuring runner: $runnerName"
    .\config.cmd --url "https://github.com/$env:GITHUB_REPOSITORY" `
        --token $env:RUNNER_TOKEN `
        --name $runnerName `
        --labels $runnerLabels `
        --work "_work" `
        --replace `
        --ephemeral `
        --unattended

    # Start runner
    Write-Log "Starting GitHub Actions runner..."
    .\run.cmd

} catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    exit 1
}