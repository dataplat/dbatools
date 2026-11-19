# Test script to verify assembly loading with the new directory structure
param (
    [string]$ModulePath = $null
)

# If no module path provided, use the current directory
if (-not $ModulePath) {
    $ModulePath = Join-Path $PSScriptRoot ".."
    $ModulePath = Resolve-Path $ModulePath
}

Write-Host "Testing assembly loading from: $ModulePath" -ForegroundColor Cyan

# Import the module
try {
    Import-Module $ModulePath -Force -ErrorAction Stop
    Write-Host "Module imported successfully" -ForegroundColor Green
} catch {
    Write-Host "Failed to import module: $_" -ForegroundColor Red
    exit 1
}

# Test Get-DbatoolsLibraryPath function
try {
    $libraryPath = Get-DbatoolsLibraryPath
    Write-Host "Library path: $libraryPath" -ForegroundColor Green

    # Verify core directory structure
    $corePath = Join-Path $libraryPath "core"
    $desktopPath = Join-Path $libraryPath "desktop"

    if (Test-Path $corePath) {
        Write-Host "Core path exists: $corePath" -ForegroundColor Green
    } else {
        Write-Host "Core path does not exist: $corePath" -ForegroundColor Red
        exit 1
    }

    if (Test-Path $desktopPath) {
        Write-Host "Desktop path exists: $desktopPath" -ForegroundColor Green
    } else {
        Write-Host "Desktop path does not exist: $desktopPath" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "Failed to get library path: $_" -ForegroundColor Red
    exit 1
}

# Test loading critical assemblies
$criticalAssemblies = @(
    'Microsoft.Data.SqlClient',
    'dbatools'
)

foreach ($assembly in $criticalAssemblies) {
    try {
        $result = Test-DbatoolsAssemblyLoading -AssemblyName $assembly
        if ($result) {
            Write-Host "Assembly $assembly can be loaded" -ForegroundColor Green
        } else {
            Write-Host "Assembly $assembly cannot be loaded" -ForegroundColor Red
            exit 1
        }
    } catch {
        Write-Host "Error testing assembly $assembly : $_" -ForegroundColor Red
        exit 1
    }
}

# Get platform info
try {
    $platformInfo = Get-DbatoolsPlatformInfo
    Write-Host "Platform: $($platformInfo.Platform)" -ForegroundColor Green
    Write-Host "Architecture: $($platformInfo.Architecture)" -ForegroundColor Green
    Write-Host "Runtime: $($platformInfo.Runtime)" -ForegroundColor Green
} catch {
    Write-Host "Failed to get platform info: $_" -ForegroundColor Red
    exit 1
}

# Test loading all assemblies
try {
    $loadedAssemblies = Get-DbatoolsLoadedAssembly
    Write-Host "Loaded assemblies:" -ForegroundColor Green
    $loadedAssemblies | Format-Table -AutoSize
} catch {
    Write-Host "Failed to get loaded assemblies: $_" -ForegroundColor Red
    exit 1
}

Write-Host "All tests passed successfully!" -ForegroundColor Green