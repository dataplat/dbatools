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

function Retry-Operation {
    param(
        [scriptblock]$Operation,
        [int]$MaxAttempts = 3,
        [int]$DelaySeconds = 10,
        [string]$OperationName = "Operation"
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            Write-Log "Attempt $attempt/$MaxAttempts for $OperationName"
            return & $Operation
        } catch {
            Write-Log "Attempt $attempt failed for $OperationName`: $($_.Exception.Message)"

            if ($attempt -eq $MaxAttempts) {
                Write-Log "All attempts failed for $OperationName"
                throw
            }

            Write-Log "Waiting $DelaySeconds seconds before retry..."
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

function Wait-ForManagedIdentity {
    param([int]$MaxWaitMinutes = 5)

    $deadline = (Get-Date).AddMinutes($MaxWaitMinutes)
    $clientId = "8f2f754a-181c-4ba3-adc7-886ccd928406"

    Write-Log "Waiting for managed identity to become available..."

    while ((Get-Date) -lt $deadline) {
        try {
            # First, check if identity service is responding
            $identityInfo = Invoke-RestMethod -Method Get `
                -Uri 'http://169.254.169.254/metadata/identity/info?api-version=2021-02-01' `
                -Headers @{Metadata = "true" } `
                -TimeoutSec 10

            # Check if our specific user-assigned identity is available
            $ourIdentity = $identityInfo | Where-Object { $_.clientId -eq $clientId }
            if ($ourIdentity) {
                Write-Log "User-assigned identity found: $($ourIdentity.clientId)"

                # Try to get a token to verify it's working
                $testToken = Invoke-RestMethod -Method Get `
                    -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2021-02-01&resource=https://vault.azure.net&client_id=$clientId" `
                    -Headers @{Metadata = "true" } `
                    -TimeoutSec 30

                if ($testToken.access_token) {
                    Write-Log "Managed identity is fully functional"
                    return $true
                }
            } else {
                Write-Log "User-assigned identity not yet available. Available identities: $($identityInfo | ConvertTo-Json -Compress)"
            }
        } catch {
            Write-Log "Identity not ready yet: $($_.Exception.Message)"
        }

        Write-Log "Waiting 15 seconds for identity propagation..."
        Start-Sleep -Seconds 15
    }

    throw "Managed identity did not become available within $MaxWaitMinutes minutes"
}

function Get-KeyVaultSecret {
    param (
        [string]$SecretName,
        [string]$AccessToken,
        [string]$KeyVaultName
    )

    $uri = "https://$KeyVaultName.vault.azure.net/secrets/$SecretName?api-version=7.2"

    return Retry-Operation -OperationName "Getting secret '$SecretName'" -MaxAttempts 5 -DelaySeconds 15 -Operation {
        try {
            $response = Invoke-RestMethod -Method Get -Uri $uri `
                -Headers @{ Authorization = "Bearer $AccessToken" } `
                -TimeoutSec 30

            if (-not $response.value -or $response.value -eq "") {
                throw "Secret '$SecretName' returned empty value"
            }

            return $response.value
        } catch {
            if ($_.Exception.Message -contains "403" -or $_.Exception.Message -contains "Forbidden") {
                Write-Log "Access denied for secret '$SecretName' - Key Vault permissions may not be propagated yet"
            }
            throw
        }
    }
}

function Test-RunnerToken {
    param([string]$Token, [string]$Repository)

    try {
        $headers = @{
            "Authorization" = "token $Token"
            "Accept"        = "application/vnd.github.v3+json"
        }

        $response = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository" `
            -Headers $headers `
            -TimeoutSec 30
        return $true
    } catch {
        Write-Log "Runner token validation failed: $($_.Exception.Message)"
        return $false
    }
}

function Download-WithRetry {
    param(
        [string]$Url,
        [string]$OutputPath,
        [int]$MaxAttempts = 3
    )

    return Retry-Operation -OperationName "Downloading from $Url" -MaxAttempts $MaxAttempts -DelaySeconds 10 -Operation {
        $webClient = New-Object System.Net.WebClient
        $webClient.Timeout = 300000  # 5 minutes
        $webClient.DownloadFile($Url, $OutputPath)

        if (-not (Test-Path $OutputPath)) {
            throw "Downloaded file not found at $OutputPath"
        }

        $fileSize = (Get-Item $OutputPath).Length
        if ($fileSize -lt 1MB) {
            throw "Downloaded file appears to be incomplete (size: $fileSize bytes)"
        }

        Write-Log "Successfully downloaded $fileSize bytes"
    }
}

try {
    Write-Log "=== GitHub Actions Runner Setup Starting ==="
    Write-Log "Machine: $env:COMPUTERNAME"
    Write-Log "PowerShell Version: $($PSVersionTable.PSVersion)"

    # Wait for managed identity to be available
    Wait-ForManagedIdentity -MaxWaitMinutes 5

    # Authenticate using the VM's managed identity with retry
    Write-Log "Authenticating using managed identity..."
    $accessToken = Retry-Operation -OperationName "Getting managed identity token" `
        -MaxAttempts 3 -DelaySeconds 10 -Operation {
        $tokenResponse = Invoke-RestMethod -Method Get `
            -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2021-02-01&resource=https://vault.azure.net&client_id=8f2f754a-181c-4ba3-adc7-886ccd928406' `
            -Headers @{Metadata = "true" } `
            -TimeoutSec 30

        if (-not $tokenResponse.access_token) {
            throw "No access token received from managed identity"
        }

        return $tokenResponse.access_token
    }

    Write-Log "Successfully obtained managed identity token"

    # Set Key Vault name
    $KeyVaultName = "dbatoolsci"

    # Pull required secrets with validation
    Write-Log "Retrieving secrets from Key Vault: $KeyVaultName"
    $env:GITHUB_REPOSITORY = Get-KeyVaultSecret -SecretName "GITHUB-REPOSITORY" -AccessToken $accessToken -KeyVaultName $KeyVaultName
    $env:RUNNER_TOKEN = Get-KeyVaultSecret -SecretName "GITHUB-RUNNER-TOKEN" -AccessToken $accessToken -KeyVaultName $KeyVaultName
    $env:BUILD_ID = Get-KeyVaultSecret -SecretName "GITHUB-BUILD-ID" -AccessToken $accessToken -KeyVaultName $KeyVaultName
    $env:VMSS_NAME = Get-KeyVaultSecret -SecretName "VMSS-NAME" -AccessToken $accessToken -KeyVaultName $KeyVaultName

    # Validate all secrets were retrieved
    $requiredVars = @("GITHUB_REPOSITORY", "RUNNER_TOKEN", "BUILD_ID", "VMSS_NAME")
    foreach ($var in $requiredVars) {
        $value = [System.Environment]::GetEnvironmentVariable($var)
        if (-not $value -or $value -eq "") {
            throw "Required variable '$var' is empty or null"
        }
    }

    Write-Log "Retrieved and validated secrets from Key Vault:"
    Write-Log "GITHUB_REPOSITORY=$env:GITHUB_REPOSITORY"
    Write-Log "BUILD_ID=$env:BUILD_ID"
    Write-Log "VMSS_NAME=$env:VMSS_NAME"
    Write-Log "RUNNER_TOKEN=***REDACTED*** (length: $($env:RUNNER_TOKEN.Length))"

    # Validate runner token
    Write-Log "Validating runner token..."
    if (-not (Test-RunnerToken -Token $env:RUNNER_TOKEN -Repository $env:GITHUB_REPOSITORY)) {
        throw "Runner token validation failed - token may be expired or invalid"
    }
    Write-Log "Runner token validated successfully"

    # Get instance name with retry
    $instanceName = Retry-Operation -OperationName "Getting instance metadata" -MaxAttempts 3 -DelaySeconds 5 -Operation {
        try {
            return (Invoke-RestMethod -Uri "http://169.254.169.254/metadata/instance/compute/name?api-version=2021-02-01" `
                    -Headers @{"Metadata" = "true" } `
                    -TimeoutSec 10)
        } catch {
            Write-Log "Failed to get instance metadata, using computer name as fallback"
            return $env:COMPUTERNAME
        }
    }

    Write-Log "Instance name: $instanceName"

    # Create runner directory
    $runnerDir = "C:\actions-runner"
    if (Test-Path $runnerDir) {
        Write-Log "Removing existing runner directory"
        Set-Location "C:\"

        # Force remove with retry (Windows can be finicky)
        Retry-Operation -OperationName "Removing existing runner directory" -MaxAttempts 3 -DelaySeconds 5 -Operation {
            Remove-Item -Path $runnerDir -Recurse -Force -ErrorAction Stop
            Start-Sleep -Seconds 2

            if (Test-Path $runnerDir) {
                throw "Directory still exists after removal"
            }
        }
    }

    Write-Log "Creating runner directory: $runnerDir"
    New-Item -ItemType Directory -Path $runnerDir -Force | Out-Null
    Set-Location $runnerDir

    # Get latest runner version with retry
    Write-Log "Getting latest GitHub Actions runner version..."
    $runnerVersion = Retry-Operation -OperationName "Getting latest runner version" -MaxAttempts 3 -DelaySeconds 10 -Operation {
        $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/actions/runner/releases/latest" `
            -TimeoutSec 30

        if (-not $latestRelease.tag_name) {
            throw "No tag_name found in latest release"
        }

        return $latestRelease.tag_name.TrimStart('v')
    }

    Write-Log "Latest runner version: $runnerVersion"

    # Download runner with retry
    $runnerUrl = "https://github.com/actions/runner/releases/download/v$runnerVersion/actions-runner-win-x64-$runnerVersion.zip"
    $runnerZip = Join-Path $runnerDir "actions-runner.zip"

    Write-Log "Downloading runner from: $runnerUrl"
    Download-WithRetry -Url $runnerUrl -OutputPath $runnerZip -MaxAttempts 3
    Write-Log "Downloaded runner package successfully"

    # Extract runner with validation
    Write-Log "Extracting runner package..."
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($runnerZip, $runnerDir)

        # Verify extraction worked
        if (-not (Test-Path (Join-Path $runnerDir "config.cmd"))) {
            throw "config.cmd not found after extraction"
        }

        Remove-Item $runnerZip -Force
        Write-Log "Extracted runner package successfully"
    } catch {
        Write-Log "Extraction failed: $($_.Exception.Message)"
        throw
    }

    # Generate runner name and labels
    $runnerName = "$env:VMSS_NAME-$instanceName-$env:BUILD_ID"
    $runnerLabels = "self-hosted,windows,sql-server,$env:VMSS_NAME,build-$env:BUILD_ID,$($instanceName.ToLower())"

    Write-Log "Configuring runner:"
    Write-Log "  Name: $runnerName"
    Write-Log "  Labels: $runnerLabels"

    # Configure runner with retry
    Write-Log "Running runner configuration..."
    Retry-Operation -OperationName "Configuring runner" -MaxAttempts 3 -DelaySeconds 30 -Operation {
        $configArgs = @(
            "--url", "https://github.com/$env:GITHUB_REPOSITORY",
            "--token", $env:RUNNER_TOKEN,
            "--name", $runnerName,
            "--labels", $runnerLabels,
            "--work", "_work",
            "--replace",
            "--ephemeral",
            "--unattended"
        )

        $configProcess = Start-Process -FilePath ".\config.cmd" `
            -ArgumentList $configArgs `
            -WorkingDirectory $runnerDir `
            -Wait -PassThru -NoNewWindow

        if ($configProcess.ExitCode -ne 0) {
            throw "Runner configuration failed with exit code $($configProcess.ExitCode)"
        }

        Write-Log "Runner configured successfully"
    }

    # Start the runner with monitoring
    Write-Log "Starting GitHub Actions runner..."
    $runnerProcess = Start-Process -FilePath ".\run.cmd" `
        -WorkingDirectory $runnerDir `
        -PassThru -WindowStyle Hidden

    if ($runnerProcess) {
        Write-Log "Runner started with Process ID: $($runnerProcess.Id)"

        # Wait and verify the process is stable
        Start-Sleep -Seconds 10

        # Check if process is still running
        $runnerProcess.Refresh()
        if ($runnerProcess.HasExited) {
            throw "Runner process exited unexpectedly with code $($runnerProcess.ExitCode)"
        }

        Write-Log "Runner is running successfully and appears stable"

        # Final verification - check if runner appears in GitHub
        Start-Sleep -Seconds 30
        try {
            $headers = @{ "Authorization" = "token $env:RUNNER_TOKEN" }
            $runners = Invoke-RestMethod -Uri "https://api.github.com/repos/$env:GITHUB_REPOSITORY/actions/runners" `
                -Headers $headers `
                -TimeoutSec 30

            $ourRunner = $runners.runners | Where-Object { $_.name -eq $runnerName }
            if ($ourRunner) {
                Write-Log "SUCCESS: Runner '$runnerName' is registered and online in GitHub"
            } else {
                Write-Log "WARNING: Runner not yet visible in GitHub API (may take a few moments)"
            }
        } catch {
            Write-Log "WARNING: Could not verify runner registration: $($_.Exception.Message)"
        }

    } else {
        throw "Failed to start runner process"
    }

    Write-Log "=== Runner Setup Completed Successfully ==="
    Write-Log "Runner will continue running until the job completes (ephemeral mode)"

} catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)"

    # Enhanced cleanup on error
    try {
        Write-Log "Performing cleanup due to error..."

        # Try to remove any partial runner registration
        if ($env:RUNNER_TOKEN -and $env:GITHUB_REPOSITORY -and $runnerName) {
            Write-Log "Attempting to cleanup runner registration..."
            try {
                .\config.cmd remove --token $env:RUNNER_TOKEN --unattended
            } catch {
                Write-Log "Could not remove runner registration: $($_.Exception.Message)"
            }
        }

        # Cleanup directory
        if (Test-Path $runnerDir) {
            Set-Location "C:\"
            Remove-Item -Path $runnerDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Cleaned up runner directory"
        }
    } catch {
        Write-Log "Failed to cleanup on error: $($_.Exception.Message)"
    }

    # Exit with error code to signal failure to the system
    exit 1
}