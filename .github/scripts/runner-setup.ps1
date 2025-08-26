# runner-setup.ps1
# GitHub Actions Runner Setup Script for Windows VMSS

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Write-Host $logMessage -ForegroundColor Green
    Add-Content -Path "C:\runner-setup.log" -Value $logMessage -ErrorAction SilentlyContinue
}

try {
    Write-Log "=== GitHub Actions Runner Setup Starting ==="
    Write-Log "Machine: $env:COMPUTERNAME"
    Write-Log "Build ID: $env:BUILD_ID"
    Write-Log "VMSS Name: $env:VMSS_NAME"
    Write-Log "Repository: $env:GITHUB_REPOSITORY"

    # Get instance name
    $instanceName = try {
        (Invoke-RestMethod -Uri "http://169.254.169.254/metadata/instance/compute/name?api-version=2021-02-01" -Headers @{"Metadata" = "true"} -TimeoutSec 10)
    } catch {
        $env:COMPUTERNAME
    }

    # Create runner directory
    $runnerDir = "C:\actions-runner"
    if (Test-Path $runnerDir) {
        Write-Log "Removing existing runner directory"
        Set-Location "C:\"
        Remove-Item -Path $runnerDir -Recurse -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    Write-Log "Creating runner directory: $runnerDir"
    New-Item -ItemType Directory -Path $runnerDir -Force | Out-Null
    Set-Location $runnerDir

    # Get latest runner version
    Write-Log "Getting latest GitHub Actions runner version..."
    $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/actions/runner/releases/latest" -TimeoutSec 30
    $runnerVersion = $latestRelease.tag_name.TrimStart('v')
    Write-Log "Latest runner version: $runnerVersion"

    # Download runner
    $runnerUrl = "https://github.com/actions/runner/releases/download/v$runnerVersion/actions-runner-win-x64-$runnerVersion.zip"
    $runnerZip = "actions-runner.zip"

    Write-Log "Downloading runner from: $runnerUrl"
    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile($runnerUrl, (Join-Path $runnerDir $runnerZip))
    Write-Log "Downloaded runner package"

    # Extract runner
    Write-Log "Extracting runner package..."
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory((Join-Path $runnerDir $runnerZip), $runnerDir)
    Remove-Item $runnerZip -Force
    Write-Log "Extracted runner package"

    # Generate runner name and labels
    $runnerName = "$env:VMSS_NAME-$instanceName-$env:BUILD_ID"
    $runnerLabels = "self-hosted,windows,sql-server,$env:VMSS_NAME,build-$env:BUILD_ID,$($instanceName.ToLower())"

    Write-Log "Configuring runner:"
    Write-Log "  Name: $runnerName"
    Write-Log "  Labels: $runnerLabels"

    # Configure runner
    Write-Log "Running runner configuration..."
    .\config.cmd --url "https://github.com/$env:GITHUB_REPOSITORY" --token $env:RUNNER_TOKEN --name $runnerName --labels $runnerLabels --work _work --replace --ephemeral --unattended

    if ($LASTEXITCODE -ne 0) {
        throw "Runner configuration failed with exit code $LASTEXITCODE"
    }

    Write-Log "Runner configured successfully"

    # Start the runner
    Write-Log "Starting GitHub Actions runner..."
    $runnerProcess = Start-Process -FilePath ".\run.cmd" -WorkingDirectory $runnerDir -PassThru -WindowStyle Hidden

    if ($runnerProcess) {
        Write-Log "Runner started with Process ID: $($runnerProcess.Id)"
        Start-Sleep -Seconds 5

        if (-not $runnerProcess.HasExited) {
            Write-Log "Runner is running successfully"
        } else {
            throw "Runner process exited unexpectedly with code $($runnerProcess.ExitCode)"
        }
    } else {
        throw "Failed to start runner process"
    }

    Write-Log "=== Runner Setup Completed Successfully ==="

} catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)"

    # Cleanup on error
    try {
        if (Test-Path $runnerDir) {
            Set-Location "C:\"
            Remove-Item -Path $runnerDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Log "Failed to cleanup on error: $($_.Exception.Message)"
    }

    throw $_
}