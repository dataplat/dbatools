[CmdletBinding()]
param(
    [string]$ApiKey,
    [switch]$Push,
    [string]$Version = "1.0.0",
    [string]$Configuration = "Release"
)

$ErrorActionPreference = 'Stop'
$projectDir = $PSScriptRoot
$projectFile = Join-Path $projectDir "Dataplat.Dbatools.Csv.csproj"

Write-Host "Building Dataplat.Dbatools.Csv v$Version..." -ForegroundColor Cyan

# Clean previous builds
$binDir = Join-Path $projectDir "bin"
$objDir = Join-Path $projectDir "obj"
if (Test-Path $binDir) { Remove-Item $binDir -Recurse -Force }
if (Test-Path $objDir) { Remove-Item $objDir -Recurse -Force }

# Build and pack
dotnet pack $projectFile -c $Configuration -p:Version=$Version
if ($LASTEXITCODE -ne 0) {
    Write-Error "Build failed"
    exit 1
}

$nupkgPath = Join-Path $projectDir "bin\$Configuration\Dataplat.Dbatools.Csv.$Version.nupkg"
Write-Host "`nPackage created: $nupkgPath" -ForegroundColor Green

# Push to NuGet if requested
if ($Push) {
    if (-not $ApiKey) {
        Write-Error "ApiKey is required when using -Push"
        exit 1
    }

    Write-Host "`nPushing to NuGet.org..." -ForegroundColor Cyan
    dotnet nuget push $nupkgPath --api-key $ApiKey --source https://api.nuget.org/v3/index.json

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Successfully published to NuGet.org!" -ForegroundColor Green
    } else {
        Write-Error "Push failed"
        exit 1
    }
} else {
    Write-Host "`nTo publish, run:" -ForegroundColor Yellow
    Write-Host "  .\build.ps1 -Push -ApiKey YOUR_API_KEY -Version $Version" -ForegroundColor White
}
