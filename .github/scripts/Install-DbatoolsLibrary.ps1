<#
.SYNOPSIS
    Installs dbatools.library from PowerShell Gallery or fallback location
.DESCRIPTION
    This script attempts to install dbatools.library from:
    1. PowerShell Gallery (if version exists there)
    2. appveyor-lab repository (if version doesn't exist in gallery)
    
    This allows testing preview versions before they're published to the gallery.
.PARAMETER Version
    The version of dbatools.library to install
.PARAMETER AppveyorLabPath
    Local path to cloned appveyor-lab repository (default: /tmp/appveyor-lab)
.PARAMETER ModulePath
    Where to install the module (defaults to first path in $env:PSModulePath)
.EXAMPLE
    .\Install-DbatoolsLibrary.ps1 -Version "2024.5.1-preview"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Version,
    
    [string]$DownloadUrl,
    
    [string]$AppveyorLabPath = "/tmp/appveyor-lab",
    
    [string]$ModulePath = ($env:PSModulePath -split [IO.Path]::PathSeparator)[0]
)

Write-Host "Attempting to install dbatools.library version: $Version"

# First, check if version exists in PowerShell Gallery
try {
    $galleryModule = Find-Module -Name dbatools.library -RequiredVersion $Version -ErrorAction Stop
    Write-Host "Found version $Version in PowerShell Gallery"
    
    # Install from gallery
    Install-Module -Name dbatools.library -RequiredVersion $Version -Scope CurrentUser -Force -AllowPrerelease
    Write-Host "Successfully installed from PowerShell Gallery"
    return
}
catch {
    Write-Host "Version $Version not found in PowerShell Gallery, checking appveyor-lab..."
}

# If direct download URL is provided, use it
if ($DownloadUrl) {
    Write-Host "Using provided download URL: $DownloadUrl"
    $tempZip = Join-Path ([System.IO.Path]::GetTempPath()) "dbatools.library-$Version.zip"
    
    try {
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $tempZip -ErrorAction Stop
        $zipSource = $tempZip
        Write-Host "Successfully downloaded module zip"
    }
    catch {
        throw "Failed to download from URL: $_"
    }
} else {
    # Legacy path - check appveyor-lab
    if (-not (Test-Path $AppveyorLabPath)) {
        throw "appveyor-lab not found at $AppveyorLabPath. Please clone it first."
    }

    # Look for module zip in appveyor-lab
    $moduleZipPath = Join-Path $AppveyorLabPath "modules/dbatools.library/$Version.zip"
    $moduleZipUrl = "https://github.com/dataplat/appveyor-lab/raw/master/modules/dbatools.library/$Version.zip"

    # Try local file first, then URL
    if (Test-Path $moduleZipPath) {
        Write-Host "Found local module zip at: $moduleZipPath"
        $zipSource = $moduleZipPath
    } else {
        Write-Host "Attempting to download from: $moduleZipUrl"
        $tempZip = Join-Path ([System.IO.Path]::GetTempPath()) "dbatools.library-$Version.zip"
        
        try {
            Invoke-WebRequest -Uri $moduleZipUrl -OutFile $tempZip -ErrorAction Stop
            $zipSource = $tempZip
            Write-Host "Successfully downloaded module zip"
        }
        catch {
            throw "Could not find dbatools.library $Version in gallery or appveyor-lab: $_"
        }
    }
}

# Extract and install module
$targetPath = Join-Path $ModulePath "dbatools.library"
if (Test-Path $targetPath) {
    Write-Host "Removing existing dbatools.library installation"
    Remove-Item -Path $targetPath -Recurse -Force
}

Write-Host "Extracting module to: $targetPath"
Expand-Archive -Path $zipSource -DestinationPath $ModulePath -Force

# Verify installation
if (Get-Module -ListAvailable -Name dbatools.library | Where-Object Version -eq $Version) {
    Write-Host "Successfully installed dbatools.library $Version from appveyor-lab"
} else {
    # Sometimes the version in the zip doesn't match the filename, so just verify it exists
    if (Get-Module -ListAvailable -Name dbatools.library) {
        Write-Host "Installed dbatools.library from appveyor-lab (version may differ from filename)"
    } else {
        throw "Failed to install dbatools.library"
    }
}

# Cleanup temp file if we downloaded it
if ($tempZip -and (Test-Path $tempZip)) {
    Remove-Item $tempZip -Force
}