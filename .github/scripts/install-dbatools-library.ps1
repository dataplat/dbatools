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
            Name               = $ModuleName
            RequiredVersion    = $RequiredVersion
            Scope              = $InstallScope
            Force              = $ForceInstall
            AllowClobber       = $true
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
        # IWR is crazy slow for large downloads
        $currentProgressPref = $ProgressPreference
        $ProgressPreference = "SilentlyContinue"
        Invoke-WebRequest -Uri $releaseUrl -OutFile $downloadPath -ErrorAction Stop
        $ProgressPreference = $currentProgressPref

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
            Write-Log "No 'dbatools.library' subdirectory found, checking if module files are in root..." -Level 'Warning'
            # Check if manifest exists in root
            $rootManifest = Join-Path $extractPath "dbatools.library.psd1"
            if (Test-Path $rootManifest) {
                Write-Log "Found manifest in root, using extract path as module directory"
                $moduleDir = Get-Item $extractPath
            } else {
                Write-Log "No manifest found in root either. Available items:" -Level 'Warning'
                Get-ChildItem -Path $extractPath | ForEach-Object {
                    Write-Log "  $($_.Name) ($($_.GetType().Name))" -Level 'Warning'
                }
                throw "Could not locate dbatools.library module in extracted archive"
            }
        } else {
            Write-Log "Found dbatools.library directory: $($moduleDir.FullName)"
        }

        # Verify manifest exists in module directory
        $manifestInModuleDir = Join-Path $moduleDir.FullName "dbatools.library.psd1"
        if (-not (Test-Path $manifestInModuleDir)) {
            Write-Log "ERROR: No dbatools.library.psd1 manifest found in module directory!" -Level 'Error'
            throw "Module manifest not found in $($moduleDir.FullName)"
        } else {
            Write-Log "Manifest found at: $manifestInModuleDir"
        }

        # Determine installation paths based on scope
        $installBasePaths = @()

        if ($PSVersionTable.Platform -eq 'Unix') {
            # Unix systems - single path based on scope
            if ($Scope -eq 'AllUsers') {
                $installBasePaths += '/usr/local/share/powershell/Modules'
            } else {
                $installBasePaths += "$env:HOME/.local/share/powershell/Modules"
            }
        } else {
            # Windows systems - install to both PowerShell Core and Windows PowerShell paths
            if ($Scope -eq 'AllUsers') {
                # AllUsers scope - Program Files locations
                $installBasePaths += "$env:ProgramFiles\PowerShell\Modules"
                $installBasePaths += "$env:ProgramFiles\WindowsPowerShell\Modules"
            } else {
                # CurrentUser scope - User profile locations
                $installBasePaths += "$env:USERPROFILE\Documents\PowerShell\Modules"
                $installBasePaths += "$env:ProgramFiles\WindowsPowerShell\Modules"
            }
        }

        Write-Log "Will install to the following paths:"
        foreach ($path in $installBasePaths) {
            Write-Log "  $path"
        }

        $success = $false

        # Install to each path
        foreach ($installBasePath in $installBasePaths) {
            # Install directly to module directory without version subdirectory for preview versions
            $finalInstallPath = Join-Path -Path $installBasePath -ChildPath $ModuleName

            # Create installation directory
            Write-Log "Module base path: $installBasePath"
            Write-Log "Installing to: $finalInstallPath"
            if (-not (Test-Path (Split-Path $finalInstallPath))) {
                New-Item -Path (Split-Path $finalInstallPath) -ItemType Directory -Force | Out-Null
            }

            # Remove existing installation if it exists
            if (Test-Path $finalInstallPath) {
                Remove-Item $finalInstallPath -Recurse -Force
            }

            # Copy module files
            Write-Log "Copying from: $($moduleDir.FullName)"
            Write-Log "Copying to: $finalInstallPath"

            # Ensure parent directory exists
            $parentDir = Split-Path $finalInstallPath -Parent
            if (-not (Test-Path $parentDir)) {
                Write-Log "Creating parent directory: $parentDir"
                New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
            }

            Copy-Item -Path $moduleDir.FullName -Destination $finalInstallPath -Recurse -Force

            # Diagnostic: Verify copy results
            Write-Log "Verifying copy operation..."
            if (Test-Path $finalInstallPath) {
                Write-Log "Final installation contents:"

                # Verify manifest exists in final location
                $finalManifest = Join-Path $finalInstallPath "dbatools.library.psd1"
                if (Test-Path $finalManifest) {
                    Write-Log "Manifest confirmed at final location: $finalManifest"
                    try {
                        $manifestTest = Test-ModuleManifest -Path $finalManifest -ErrorAction Stop
                        Write-Log "Manifest validation successful, version: $($manifestTest.Version)"
                        $success = $true
                    } catch {
                        Write-Log "Manifest validation failed: $($_.Exception.Message)" -Level 'Error'
                    }
                } else {
                    Write-Log "ERROR: Manifest missing from final installation location!" -Level 'Error'
                }
            } else {
                Write-Log "ERROR: Installation directory was not created!" -Level 'Error'
                Write-Log "Failed to create installation directory at $finalInstallPath" -Level 'Error'
                # Continue to next path instead of throwing
                continue
            }

            # Add the modules directory to PSModulePath if not already present
            $modulesBasePath = Split-Path $finalInstallPath -Parent
            $currentPSModulePath = $env:PSModulePath -split [System.IO.Path]::PathSeparator

            if ($modulesBasePath -notin $currentPSModulePath) {
                $env:PSModulePath = $modulesBasePath + [System.IO.Path]::PathSeparator + $env:PSModulePath
                Write-Log "Added '$modulesBasePath' to PSModulePath for this session" -Level 'Success'
            }
        }

        # Check if at least one installation succeeded
        if (-not $success) {
            throw "Failed to install module to any of the target paths"
        }

        # Cleanup
        Remove-Item $downloadPath -Force -ErrorAction SilentlyContinue
        Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue

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
    Write-Log "PowerShell Edition: $($PSVersionTable.PSEdition)"
    Write-Log "PowerShell Version: $($PSVersionTable.PSVersion)"

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

    # Diagnostic: Check PSModulePath before verification
    Write-Log "Current PSModulePath before verification:"
    $env:PSModulePath -split [System.IO.Path]::PathSeparator | ForEach-Object {
        Write-Log "  $_"
    }

    # Diagnostic: Force refresh module cache
    Write-Log "Refreshing module cache..."
    Get-Module -Refresh -ListAvailable | Out-Null

    # Diagnostic: Check for any dbatools.library modules first
    Write-Log "Searching for any dbatools.library modules..."
    $allDbaModules = Get-Module -ListAvailable | Where-Object { $_.Name -like "*dbatools*" }
    if ($allDbaModules) {
        Write-Log "Found dbatools-related modules:"
        $allDbaModules | ForEach-Object {
            Write-Log "  $($_.Name) v$($_.Version) at $($_.ModuleBase)"
        }
    } else {
        Write-Log "No dbatools-related modules found at all!" -Level 'Warning'
    }

    # Diagnostic: Try multiple module discovery approaches
    Write-Log "Attempting multiple discovery methods..."

    # Method 1: Standard Get-Module
    $installedModules = Get-Module -ListAvailable -Name 'dbatools.library'
    Write-Log "Method 1 (Get-Module -Name): Found $($installedModules.Count) modules"

    # Method 2: Wildcard search
    $wildcardModules = Get-Module -ListAvailable -Name '*dbatools.library*'
    Write-Log "Method 2 (Wildcard search): Found $($wildcardModules.Count) modules"

    # Method 3: Direct path check if we have the installation path
    if ($finalInstallPath -and (Test-Path $finalInstallPath)) {
        Write-Log "Method 3: Checking direct installation path: $finalInstallPath"
        $manifestPath = Join-Path $finalInstallPath "dbatools.library.psd1"
        if (Test-Path $manifestPath) {
            try {
                $directModule = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
                Write-Log "Method 3 (Direct path): Found module version $($directModule.Version)"
                # Try to import it directly to see if it works
                $importedModule = Import-Module $manifestPath -PassThru -Force -ErrorAction Stop
                Write-Log "Method 3 (Direct import): Successfully imported version $($importedModule.Version)"
                Remove-Module $importedModule -Force -ErrorAction SilentlyContinue
            } catch {
                Write-Log "Method 3 (Direct path): Failed - $($_.Exception.Message)" -Level 'Warning'
            }
        } else {
            Write-Log "Method 3 (Direct path): Manifest not found at $manifestPath" -Level 'Warning'
        }
    }

    if ($installedModules) {
        Write-Log "Found dbatools.library installations:" -Level 'Success'
        foreach ($module in $installedModules) {
            Write-Log "  Version: $($module.Version) | Path: $($module.ModuleBase)"
        }

        # For preview versions, we install without version directory, so just check if any version is available
        if ($installedModules.Count -gt 0) {
            Write-Log "dbatools.library module found and available (version: $($installedModules[0].Version))!" -Level 'Success'
        } else {
            Write-Log "No dbatools.library versions found after installation" -Level 'Warning'
        }
    } else {
        Write-Log "CRITICAL: No dbatools.library module found after installation" -Level 'Error'
        Write-Log "This indicates a problem with module installation or PowerShell module discovery" -Level 'Error'
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
} catch {
    Write-Log "Installation failed: $($_.Exception.Message)" -Level 'Error'
    exit 1
}