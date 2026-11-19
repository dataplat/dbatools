function Wait-MsiInstall {
    <#
    .SYNOPSIS
        Waits for all MSI installations to complete before proceeding.

    .DESCRIPTION
        This function monitors the Windows Installer service and waits for all MSI installations
        to complete. It prevents overlapping installations which can cause failures.

    .PARAMETER TimeoutMinutes
        Maximum time to wait in minutes. Default is 30 minutes.

    .PARAMETER CheckIntervalSeconds
        How often to check for running installations in seconds. Default is 5 seconds.

    .EXAMPLE
        Wait-MsiInstall

        Waits for all MSI installations to complete with default timeout.

    .EXAMPLE
        Wait-MsiInstall -TimeoutMinutes 60 -CheckIntervalSeconds 10

        Waits up to 60 minutes, checking every 10 seconds.
    #>
    [CmdletBinding()]
    param(
        [int]$TimeoutMinutes = 30,
        [int]$CheckIntervalSeconds = 5
    )

    $timeoutTime = (Get-Date).AddMinutes($TimeoutMinutes)
    $msiexecRunning = $true

    Write-Host "Checking for running MSI installations..." -ForegroundColor Yellow

    while ($msiexecRunning -and (Get-Date) -lt $timeoutTime) {
        # Check for msiexec processes
        $msiProcesses = Get-Process -Name "msiexec" -ErrorAction SilentlyContinue

        # Check Windows Installer service status
        $installerService = Get-Service -Name "msiserver" -ErrorAction SilentlyContinue

        # Check for installation mutex (Windows Installer global mutex)
        $mutex = $null
        try {
            $mutex = [System.Threading.Mutex]::OpenExisting("Global\_MSIExecute")
            $mutexExists = $true
        }
        catch {
            $mutexExists = $false
        }
        finally {
            if ($mutex) {
                $mutex.Dispose()
            }
        }

        if ($msiProcesses -or ($installerService -and $installerService.Status -eq "Running") -or $mutexExists) {
            Write-Host "MSI installation in progress... waiting $CheckIntervalSeconds seconds" -ForegroundColor Yellow
            Start-Sleep -Seconds $CheckIntervalSeconds
        }
        else {
            $msiexecRunning = $false
            Write-Host "No MSI installations detected. Safe to proceed." -ForegroundColor Green
        }
    }

    if ((Get-Date) -ge $timeoutTime) {
        Write-Warning "Timeout reached while waiting for MSI installations to complete."
        return $false
    }

    # Additional safety wait to ensure installer has fully released resources
    Start-Sleep -Seconds 2
    return $true
}

function Wait-SpecificMsiProcess {
    <#
    .SYNOPSIS
        Waits for a specific MSI installation process to complete by monitoring its process ID.

    .DESCRIPTION
        This function waits for a specific msiexec process to complete based on its process ID.
        Useful when you start an MSI installation and want to wait for that specific installation.

    .PARAMETER ProcessId
        The process ID of the msiexec process to monitor.

    .PARAMETER TimeoutMinutes
        Maximum time to wait in minutes. Default is 30 minutes.

    .EXAMPLE
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i", "package.msi", "/quiet" -PassThru
        Wait-SpecificMsiProcess -ProcessId $process.Id
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$ProcessId,
        [int]$TimeoutMinutes = 30
    )

    Write-Host "Waiting for MSI process $ProcessId to complete..." -ForegroundColor Yellow

    try {
        # Wait for the process using a different approach that preserves exit code
        $process = $null
        $attempts = 0
        while (-not $process -and $attempts -lt 5) {
            $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
            if (-not $process) {
                Start-Sleep -Milliseconds 500
                $attempts++
            }
        }

        if (-not $process) {
            Write-Host "MSI process $ProcessId not found or already completed." -ForegroundColor Green
            return 0
        }

        # Wait for process to exit
        $process.WaitForExit(($TimeoutMinutes * 60 * 1000))

        if ($process.HasExited) {
            # Get exit code using WMI for reliability
            $exitCode = (Get-WmiObject Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue).ExitCode
            if ($null -eq $exitCode) {
                # Fallback to process ExitCode if available
                $exitCode = $process.ExitCode
            }
            Write-Host "MSI process $ProcessId completed with exit code: $exitCode" -ForegroundColor Green
            return $exitCode
        }
        else {
            Write-Warning "Timeout reached waiting for MSI process $ProcessId"
            return -1
        }
    }
    catch {
        Write-Host "MSI process $ProcessId completed or error occurred: $_" -ForegroundColor Yellow
        return 0
    }
}

function Install-MsiPackageWithWait {
    <#
    .SYNOPSIS
        Installs an MSI package and waits for completion.

    .DESCRIPTION
        This function installs an MSI package with proper waiting and error handling.
        It ensures no other MSI installations are running before starting.

    .PARAMETER MsiPath
        Path to the MSI file to install.

    .PARAMETER Arguments
        Additional arguments to pass to msiexec. Default is "/quiet /norestart".

    .PARAMETER TimeoutMinutes
        Maximum time to wait for installation. Default is 30 minutes.

    .EXAMPLE
        Install-MsiPackageWithWait -MsiPath "C:\temp\package.msi"

        Installs the MSI package quietly and waits for completion.

    .EXAMPLE
        Install-MsiPackageWithWait -MsiPath "C:\temp\package.msi" -Arguments "/quiet /log C:\temp\install.log"

        Installs with custom arguments including logging.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MsiPath,
        [string]$Arguments = "/quiet /norestart",
        [int]$TimeoutMinutes = 30
    )

    if (-not (Test-Path $MsiPath)) {
        throw "MSI file not found: $MsiPath"
    }

    # Wait for any existing MSI installations to complete
    Write-Host "Ensuring no other MSI installations are running..." -ForegroundColor Yellow
    if (-not (Wait-MsiInstall -TimeoutMinutes 10)) {
        throw "Timeout waiting for existing MSI installations to complete"
    }

    # Start the installation
    Write-Host "Starting MSI installation: $MsiPath" -ForegroundColor Green
    $fullArguments = "/i `"$MsiPath`" $Arguments"

    try {
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $fullArguments -PassThru -Wait

        Write-Host "MSI installation completed with exit code: $($process.ExitCode)" -ForegroundColor Green

        # Common MSI exit codes
        switch ($process.ExitCode) {
            0 { Write-Host "Installation successful" -ForegroundColor Green }
            1641 { Write-Host "Installation successful, restart required" -ForegroundColor Yellow }
            3010 { Write-Host "Installation successful, restart required" -ForegroundColor Yellow }
            1618 { Write-Warning "Another installation is already in progress" }
            1619 { Write-Warning "Installation package could not be opened" }
            1620 { Write-Warning "Installation package could not be opened" }
            1633 { Write-Warning "This installation package is not supported on this platform" }
            default { Write-Warning "Installation completed with exit code: $($process.ExitCode)" }
        }

        return $process.ExitCode
    }
    catch {
        Write-Error "Failed to start MSI installation: $($_.Exception.Message)"
        throw
    }
}

# Functions are automatically available when dot-sourced