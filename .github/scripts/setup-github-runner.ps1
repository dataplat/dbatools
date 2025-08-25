param(
    [string]$GitHubToken,
    [string]$BuildId,
    [string]$VmssName,
    [string]$Repository
)

$ErrorActionPreference = "Stop"

try {
    Write-Host "=== GitHub Runner Setup ===" -ForegroundColor Green

    # Get instance metadata
    $InstanceName = (Invoke-RestMethod -Uri "http://169.254.169.254/metadata/instance/compute/name?api-version=2021-02-01" -Headers @{"Metadata" = "true" })

    # Generate unique runner name
    $RunnerName = "$VmssName-$InstanceName-$BuildId"
    $RunnerLabels = "self-hosted,windows,sql-server,$VmssName,build-$BuildId"

    Write-Host "Configuring runner: $RunnerName" -ForegroundColor Yellow
    Write-Host "Labels: $RunnerLabels" -ForegroundColor Yellow
    Write-Host "Repository: $Repository" -ForegroundColor Yellow

    $RunnerPath = "C:\actions-runner"
    if (!(Test-Path $RunnerPath)) {
        Write-Error "GitHub runner not found at $RunnerPath"
        exit 1
    }

    Set-Location $RunnerPath

    # Remove existing config if present
    if (Test-Path ".runner") {
        Write-Host "Removing existing runner configuration" -ForegroundColor Yellow
        .\config.cmd remove --token $GitHubToken 2>$null
        Start-Sleep -Seconds 5
    }

    # Configure new runner
    Write-Host "Configuring new runner..." -ForegroundColor Green
    .\config.cmd --url "https://github.com/$Repository" --token $GitHubToken --name $RunnerName --labels $RunnerLabels --work _work --replace --ephemeral --unattended

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Runner configuration failed with exit code $LASTEXITCODE"
        exit 1
    }

    Write-Host "Runner configured successfully" -ForegroundColor Green
    Write-Host "Starting runner service..." -ForegroundColor Yellow

    # Start the runner (blocks until job completes due to --ephemeral)
    .\run.cmd

} catch {
    Write-Error "Runner setup failed: $_"
    Write-EventLog -LogName Application -Source "Application" -EventId 1001 -EntryType Error -Message "GitHub runner setup failed: $_"
    exit 1
} finally {
    Write-Host "Runner completed - instance ready for reuse" -ForegroundColor Cyan
}