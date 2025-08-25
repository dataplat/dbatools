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

# Wait for set-registry.ps1 file to appear and execute it
function Wait-ForRegistryScript {
    $registryScriptPath = "C:\scripts\set-registry.ps1"
    $maxWaitMinutes = 10
    $waitIntervalSeconds = 10
    $maxAttempts = ($maxWaitMinutes * 60) / $waitIntervalSeconds

    Write-Log "Waiting for registry script: $registryScriptPath"
    Write-Log "Max wait time: $maxWaitMinutes minutes"

    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        if (Test-Path $registryScriptPath) {
            Write-Log "Registry script found after $($attempt * $waitIntervalSeconds) seconds"

            try {
                Write-Log "Executing registry script..."
                & $registryScriptPath

                if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq $null) {
                    Write-Log "Registry script executed successfully"
                    return $true
                } else {
                    throw "Registry script failed with exit code $LASTEXITCODE"
                }
            } catch {
                Write-Log "ERROR executing registry script: $($_.Exception.Message)"
                throw $_
            }
        }

        if ($attempt -eq $maxAttempts) {
            throw "Timeout: Registry script not found after $maxWaitMinutes minutes"
        }

        Write-Log "Registry script not found, waiting... (attempt $attempt/$maxAttempts)"
        Start-Sleep -Seconds $waitIntervalSeconds
    }
}

# Wait for and execute the registry script before proceeding
Wait-ForRegistryScript

try {
    Write-Log "=== GitHub Actions Runner Setup Starting ==="
    Write-Log "Machine: $env:COMPUTERNAME"
    Write-Log "Build ID: $env:BUILD_ID"
    Write-Log "VMSS Name: $env:VMSS_NAME"
    Write-Log "Repository: $env:GITHUB_REPOSITORY"

    # Validate required environment variables
    if (-not $env:VMSS_GH_TOKEN) { throw "VMSS_GH_TOKEN environment variable is required" }
    if (-not $env:GITHUB_REPOSITORY) { throw "GITHUB_REPOSITORY environment variable is required" }
    if (-not $env:BUILD_ID) { throw "BUILD_ID environment variable is required" }
    if (-not $env:VMSS_NAME) { throw "VMSS_NAME environment variable is required" }

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
    .\config.cmd --url "https://github.com/$env:GITHUB_REPOSITORY" --token $env:VMSS_GH_TOKEN --name $runnerName --labels $runnerLabels --work _work --replace --ephemeral --unattended

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