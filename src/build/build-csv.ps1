param(
    [string]$Version,
    [switch]$Sign,
    [switch]$Publish,
    [string]$NuGetApiKey
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Get script root and project root
$scriptroot = $PSScriptRoot
if (-not $scriptroot) {
    $scriptroot = Split-Path -Path $MyInvocation.MyCommand.Path
}
$root = Split-Path -Path $scriptroot
$csvProjectPath = Join-Path $root "project\Dataplat.Dbatools.Csv"
$csvCsproj = Join-Path $csvProjectPath "Dataplat.Dbatools.Csv.csproj"
$artifactsDir = Join-Path $root "artifacts"
$csvArtifacts = Join-Path $artifactsDir "csv"

Write-Host "=== Dataplat.Dbatools.Csv Build Script ===" -ForegroundColor Cyan
Write-Host ""

# Update or read version using XML parsing (safer than regex)
[xml]$csproj = Get-Content $csvCsproj
$propertyGroup = $csproj.Project.PropertyGroup | Where-Object { $_.Version } | Select-Object -First 1

if ($Version) {
    Write-Host "Updating version to: $Version" -ForegroundColor Yellow
    $propertyGroup.Version = $Version
    $csproj.Save($csvCsproj)
} else {
    $Version = $propertyGroup.Version
    Write-Host "Building version: $Version" -ForegroundColor Yellow
}

# Clean and create artifacts directory
if (Test-Path $csvArtifacts) {
    Remove-Item $csvArtifacts -Recurse -Force
}
$null = New-Item -ItemType Directory -Path $csvArtifacts -Force

# Clean previous builds (including obj folder to clear cached pack settings)
Write-Host "Cleaning previous builds..." -ForegroundColor Yellow
$cleanBinPath = Join-Path $csvProjectPath "bin"
$cleanObjPath = Join-Path $csvProjectPath "obj"
if (Test-Path $cleanBinPath) { Remove-Item $cleanBinPath -Recurse -Force }
if (Test-Path $cleanObjPath) { Remove-Item $cleanObjPath -Recurse -Force }

# Build first (without packing) so we can sign the DLLs
Write-Host "Building project..." -ForegroundColor Yellow
Push-Location $csvProjectPath
try {
    dotnet build -c Release --nologo
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet build failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

# Sign the DLLs BEFORE packing if requested
if ($Sign) {
    if (Get-Command Invoke-DbatoolsTrustedSigning -ErrorAction SilentlyContinue) {
        Write-Host ""
        Write-Host "=== Signing with Azure Trusted Signing ===" -ForegroundColor Cyan

        # Find built DLLs in the bin/Release folders
        $binPath = Join-Path $csvProjectPath "bin\Release"
        $dllsToSign = Get-ChildItem -Path $binPath -Filter "*.dll" -Recurse |
            Where-Object { $_.Name -like "*Dbatools*" -or $_.Name -like "*Dataplat*" }

        if ($dllsToSign) {
            Write-Host "Signing $($dllsToSign.Count) DLL(s)..." -ForegroundColor Yellow

            foreach ($dll in $dllsToSign) {
                Write-Host "  Signing: $($dll.Name)" -ForegroundColor Gray
                $result = $dll.FullName | Invoke-DbatoolsTrustedSigning
                if ($result.Status -ne 'Valid') {
                    throw "Signing failed for $($dll.Name): Status '$($result.Status)'. Cannot continue with unsigned DLLs."
                }
                Write-Host "    Signed (Thumbprint: $($result.Thumbprint))" -ForegroundColor Green
            }
        } else {
            Write-Host "No DLLs found to sign" -ForegroundColor Yellow
        }
    } else {
        Write-Warning "Invoke-DbatoolsTrustedSigning not found - skipping signing"
    }
}

# Now pack (will include the signed DLLs)
Write-Host "Packing NuGet package..." -ForegroundColor Yellow
Push-Location $csvProjectPath
try {
    dotnet pack -c Release --nologo --no-build -o $csvArtifacts
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet pack failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

# Find the generated package (no snupkg - we use embedded PDBs)
$nupkg = Get-ChildItem -Path $csvArtifacts -Filter "*.nupkg" | Select-Object -First 1

if (-not $nupkg) {
    throw "No .nupkg file found in $csvArtifacts"
}

# Remove any snupkg that might have been generated (shouldn't happen with current settings)
Get-ChildItem -Path $csvArtifacts -Filter "*.snupkg" | Remove-Item -Force

Write-Host "Package created: $($nupkg.Name)" -ForegroundColor Green

# Publish to NuGet if requested
if ($Publish) {
    if (-not $NuGetApiKey) {
        $NuGetApiKey = $env:NUGET_API_KEY
    }

    if (-not $NuGetApiKey) {
        Write-Warning "No NuGet API key provided. Set -NuGetApiKey or `$env:NUGET_API_KEY"
    } else {
        Write-Host ""
        Write-Host "=== Publishing to NuGet ===" -ForegroundColor Cyan

        dotnet nuget push $nupkg.FullName --api-key $NuGetApiKey --source https://api.nuget.org/v3/index.json --skip-duplicate

        if ($LASTEXITCODE -eq 0) {
            Write-Host "Published to NuGet!" -ForegroundColor Green
        }
    }
}

Write-Host ""
Write-Host "=== Build Complete ===" -ForegroundColor Cyan
Write-Host "Output: $csvArtifacts" -ForegroundColor White
Get-ChildItem $csvArtifacts | ForEach-Object {
    Write-Host "  $($_.Name)" -ForegroundColor Gray
}
