<#
.SYNOPSIS
    Installs dbatools.library module from PowerShell Gallery or GitHub releases

.DESCRIPTION
    This script reads the version configuration from .github/dbatools-library-version.json
    and installs the specified version of dbatools.library module. It first attempts to
    install from PowerShell Gallery, and if not found, downloads from GitHub releases.

    Supports both stable and preview versions and works cross-platform on Windows, Linux, and macOS.

.PARAMETER ConfigPath
    Path to the JSON configuration file containing the version information.
    Defaults to '.github/dbatools-library-version.json' relative to script location.

.PARAMETER Force
    Forces reinstallation even if the module is already installed

.PARAMETER Scope
    Installation scope for PowerShell Gallery installation (CurrentUser or AllUsers).
    Defaults to CurrentUser.

.EXAMPLE
    .\install-dbatools-library.ps1
    Installs the version specified in the JSON config file

.EXAMPLE
    .\install-dbatools-library.ps1 -Force
    Forces reinstallation of the module

.EXAMPLE
    .\install-dbatools-library.ps1 -Scope AllUsers
    Installs the module for all users (requires elevated permissions)

.NOTES
    GitHub Release URL Pattern: https://github.com/dataplat/dbatools.library/releases/download/v{version}/dbatools.library.zip
    Supports preview versions like: 2025.7.12-preview-main-20250712.175548
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "../dbatools-library-version.json"),
    [switch]$Force,
    [ValidateSet('CurrentUser', 'AllUsers')]
    [string]$Scope = 'CurrentUser'
)

function Write-Log {
    param([string]$Message, [string]$Level = 'Info')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $color = switch ($Level) {
        'Error' { 'Red' }
        'Warning' { 'Yellow' }
        'Success' { 'Green' }
        default { 'White' }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Get-CrossPlatformTempPath {
    # Cross-platform temporary directory handling
    if ($PSVersionTable.Platform -eq 'Unix') {
        return '/tmp'
    } else {
        return $env:TEMP
    }
}

function Test-ModuleInstalled {
    param([string]$ModuleName, [string]$RequiredVersion)

    try {
        $installedModule = Get-Module -ListAvailable -Name $ModuleName |
            Where-Object { $_.Version -eq $RequiredVersion }
        return $null -ne $installedModule
    } catch {
        return $false
    }
}

function Install-FromPowerShellGallery {
    param([string]$ModuleName, [string]$RequiredVersion, [string]$InstallScope, [bool]$ForceInstall)

    Write-Log "Attempting to install $ModuleName version $RequiredVersion from PowerShell Gallery..."

    try {
        $installParams = @{
            Name = $ModuleName
            RequiredVersion = $RequiredVersion
            Scope = $InstallScope
            Force = $ForceInstall
            AllowClobber = $true
            SkipPublisherCheck = $true
        }

        # Add AllowPrerelease for preview versions
        if ($RequiredVersion -like "*preview*") {
            $installParams.AllowPrerelease = $true
        }

        Install-Module @installParams -ErrorAction Stop
        Write-Log "Successfully installed $ModuleName version $RequiredVersion from PowerShell Gallery" -Level 'Success'
        return $true
    } catch {
        Write-Log "Failed to install from PowerShell Gallery: $($_.Exception.Message)" -Level 'Warning'
        return $false
    }
}

function Install-FromGitHubRelease {
    param([string]$ModuleName, [string]$RequiredVersion)

    Write-Log "Attempting to download $ModuleName version $RequiredVersion from GitHub releases..."

    try {
        # Construct GitHub release URL
        $releaseUrl = "https://github.com/dataplat/dbatools.library/releases/download/v$RequiredVersion/dbatools.library.zip"
        Write-Log "Download URL: $releaseUrl"

        # Get cross-platform temp directory
        $tempDir = Get-CrossPlatformTempPath
        $downloadPath = Join-Path $tempDir "dbatools.library-$RequiredVersion.zip"
        $extractPath = Join-Path $tempDir "dbatools.library-$RequiredVersion"

        # Download the release
        Write-Log "Downloading to: $downloadPath"
        Invoke-WebRequest -Uri $releaseUrl -OutFile $downloadPath -ErrorAction Stop

        # Extract the archive
        Write-Log "Extracting to: $extractPath"
        if (Test-Path $extractPath) {
            Remove-Item $extractPath -Recurse -Force
        }
        Expand-Archive -Path $downloadPath -DestinationPath $extractPath -ErrorAction Stop

        # Find the module directory
        $moduleDir = Get-ChildItem -Path $extractPath -Directory | Where-Object { $_.Name -eq 'dbatools.library' }
        if (-not $moduleDir) {
            # Sometimes the module is in the root of the extract path
            $moduleDir = Get-Item $extractPath
        }

        # Determine installation path based on scope
        if ($Scope -eq 'AllUsers') {
            if ($PSVersionTable.Platform -eq 'Unix') {
                $installBasePath = '/usr/local/share/powershell/Modules'
            } else {
                $installBasePath = "$env:ProgramFiles\PowerShell\Modules"
            }
        } else {
            if ($PSVersionTable.Platform -eq 'Unix') {
                $installBasePath = "$env:HOME/.local/share/powershell/Modules"
            } else {
                $installBasePath = "$env:USERPROFILE\Documents\PowerShell\Modules"
            }
        }

        $finalInstallPath = Join-Path -Path (Join-Path -Path $installBasePath -ChildPath $ModuleName) -ChildPath $RequiredVersion

        # Create installation directory
        Write-Log "Installing to: $finalInstallPath"
        if (-not (Test-Path (Split-Path $finalInstallPath))) {
            New-Item -Path (Split-Path $finalInstallPath) -ItemType Directory -Force | Out-Null
        }

        # Remove existing installation if it exists
        if (Test-Path $finalInstallPath) {
            Remove-Item $finalInstallPath -Recurse -Force
        }

        # Copy module files
        Copy-Item -Path $moduleDir.FullName -Destination $finalInstallPath -Recurse -Force

        # Add the modules directory to PSModulePath if not already present
        $modulesBasePath = Split-Path $finalInstallPath -Parent
        $modulesRootPath = Split-Path $modulesBasePath -Parent
        $currentPSModulePath = $env:PSModulePath -split [System.IO.Path]::PathSeparator

        if ($modulesRootPath -notin $currentPSModulePath) {
            $env:PSModulePath = $modulesRootPath + [System.IO.Path]::PathSeparator + $env:PSModulePath
            Write-Log "Added '$modulesRootPath' to PSModulePath for this session" -Level 'Success'
        }

        # Cleanup
        Remove-Item $downloadPath -Force -ErrorAction SilentlyContinue
        Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue

        Write-Log "Successfully installed $ModuleName version $RequiredVersion from GitHub releases" -Level 'Success'
        return $true

    } catch {
        Write-Log "Failed to install from GitHub releases: $($_.Exception.Message)" -Level 'Error'

        # Cleanup on failure
        if (Test-Path $downloadPath) { Remove-Item $downloadPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue }

        return $false
    }
}

# Main execution
try {
    Write-Log "Starting dbatools.library installation process..."

    # Validate config file exists
    if (-not (Test-Path $ConfigPath)) {
        throw "Configuration file not found: $ConfigPath"
    }

    # Read version configuration
    Write-Log "Reading version configuration from: $ConfigPath"
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $requiredVersion = $config.version

    Write-Log "Target version: $requiredVersion"
    Write-Log "Installation scope: $Scope"

    # Check if module is already installed (unless Force is specified)
    if (-not $Force) {
        if (Test-ModuleInstalled -ModuleName 'dbatools.library' -RequiredVersion $requiredVersion) {
            Write-Log "dbatools.library version $requiredVersion is already installed. Use -Force to reinstall." -Level 'Success'
            exit 0
        }
    } else {
        Write-Log "Force installation requested, will reinstall if already present"
    }

    # Check if this is a preview version - skip Gallery for these
    $isPreviewVersion = $requiredVersion -match "preview|main-\d+" -or $requiredVersion -match "\d+\.\d+\.\d+-.*"

    if ($isPreviewVersion) {
        Write-Log "Detected preview version '$requiredVersion'. Skipping PowerShell Gallery and attempting GitHub releases directly." -Level 'Warning'
        $githubSuccess = Install-FromGitHubRelease -ModuleName 'dbatools.library' -RequiredVersion $requiredVersion

        if (-not $githubSuccess) {
            throw "Failed to install preview version $requiredVersion from GitHub releases"
        }
    } else {
        # Attempt installation from PowerShell Gallery first for stable versions
        $gallerySuccess = Install-FromPowerShellGallery -ModuleName 'dbatools.library' -RequiredVersion $requiredVersion -InstallScope $Scope -ForceInstall $Force

        if (-not $gallerySuccess) {
            Write-Log "PowerShell Gallery installation failed, attempting GitHub releases..."
            $githubSuccess = Install-FromGitHubRelease -ModuleName 'dbatools.library' -RequiredVersion $requiredVersion

            if (-not $githubSuccess) {
                throw "Failed to install dbatools.library version $requiredVersion from both PowerShell Gallery and GitHub releases"
            }
        }
    }

    # Verify installation and provide debugging information
    Write-Log "Verifying installation..."
    $installedModules = Get-Module -ListAvailable -Name 'dbatools.library'

    if ($installedModules) {
        Write-Log "Found dbatools.library installations:" -Level 'Success'
        foreach ($module in $installedModules) {
            Write-Log "  Version: $($module.Version) | Path: $($module.ModuleBase)"
        }

        # Check if the specific version we wanted is installed
        $targetModule = $installedModules | Where-Object { $_.Version -eq $requiredVersion }
        if ($targetModule) {
            Write-Log "Target version $requiredVersion found and available!" -Level 'Success'
        } else {
            Write-Log "Target version $requiredVersion not found, but other versions are available. This may be acceptable for preview versions." -Level 'Warning'
        }
    } else {
        throw "No dbatools.library module found after installation"
    }

    # Test import to ensure the module works
    Write-Log "Testing module import..."
    try {
        Import-Module dbatools.library -Force -ErrorAction Stop
        Write-Log "Module import test successful" -Level 'Success'
        Remove-Module dbatools.library -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Log "Module import test failed: $($_.Exception.Message)" -Level 'Warning'
        Write-Log "This may be expected if there are version compatibility issues with preview versions"
    }

    # Output PSModulePath for debugging
    Write-Log "Current PSModulePath:"
    $env:PSModulePath -split [System.IO.Path]::PathSeparator | ForEach-Object {
        Write-Log "  $_"
    }

    # For CI/CD scenarios, prepare dbatools manifest for version compatibility
    $prepareScriptPath = Join-Path $PSScriptRoot "prepare-dbatools-for-ci.ps1"
    if (Test-Path $prepareScriptPath) {
        Write-Log "Preparing dbatools manifest for CI/CD compatibility..."
        & $prepareScriptPath
        if ($LASTEXITCODE -eq 0) {
            Write-Log "dbatools manifest preparation completed successfully" -Level 'Success'
        } else {
            Write-Log "dbatools manifest preparation failed, but continuing..." -Level 'Warning'
        }
    } else {
        Write-Log "CI preparation script not found at: $prepareScriptPath" -Level 'Warning'
    }

} catch {
    Write-Log "Installation failed: $($_.Exception.Message)" -Level 'Error'
    exit 1
}