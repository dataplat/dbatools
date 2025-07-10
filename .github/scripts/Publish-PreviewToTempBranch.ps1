<#
.SYNOPSIS
    Publishes a preview version of dbatools.library to templib branch in appveyor-lab
.DESCRIPTION
    This script uploads a preview version of dbatools.library to a temporary branch
    in the appveyor-lab repository for testing in GitHub Actions.
    
    The branch can be deleted after testing to save repository space.
.PARAMETER ModulePath
    Path to the dbatools.library module folder or zip file
.PARAMETER Version
    Version string for the module (e.g., "2024.5.1-preview")
.PARAMETER AppveyorLabPath
    Local path to your cloned appveyor-lab repository
.EXAMPLE
    .\Publish-PreviewToTempBranch.ps1 -ModulePath "C:\modules\dbatools.library" -Version "2024.5.1-preview" -AppveyorLabPath "C:\github\appveyor-lab"
    
    # After testing is complete, delete the branch:
    git push origin --delete templib
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ModulePath,
    
    [Parameter(Mandatory)]
    [string]$Version,
    
    [Parameter(Mandatory)]
    [string]$AppveyorLabPath
)

# Validate paths
if (-not (Test-Path $ModulePath)) {
    throw "Module path not found: $ModulePath"
}

if (-not (Test-Path $AppveyorLabPath)) {
    throw "appveyor-lab path not found: $AppveyorLabPath"
}

# Create modules directory structure
$modulesDir = Join-Path $AppveyorLabPath "modules/dbatools.library"
if (-not (Test-Path $modulesDir)) {
    Write-Host "Creating modules directory structure"
    New-Item -Path $modulesDir -ItemType Directory -Force | Out-Null
}

# Handle zip file creation if needed
if (Test-Path $ModulePath -PathType Container) {
    Write-Host "Creating zip file from module directory"
    $zipPath = Join-Path ([System.IO.Path]::GetTempPath()) "dbatools.library-$Version.zip"
    
    # Create a proper module structure in the zip
    $tempModuleDir = Join-Path ([System.IO.Path]::GetTempPath()) "dbatools.library"
    if (Test-Path $tempModuleDir) {
        Remove-Item $tempModuleDir -Recurse -Force
    }
    Copy-Item -Path $ModulePath -Destination $tempModuleDir -Recurse
    
    Compress-Archive -Path $tempModuleDir -DestinationPath $zipPath -Force
    Remove-Item $tempModuleDir -Recurse -Force
} else {
    $zipPath = $ModulePath
}

# Copy zip to appveyor-lab
$targetZip = Join-Path $modulesDir "$Version.zip"
Write-Host "Copying module zip to: $targetZip"
Copy-Item -Path $zipPath -Destination $targetZip -Force

# Git operations
Push-Location $AppveyorLabPath
try {
    # Ensure we're on master and up to date
    git checkout master
    git pull origin master
    
    # Create/checkout templib branch
    git checkout -b templib 2>$null || git checkout templib
    
    # Merge latest master to ensure branch is up to date
    git merge master
    
    # Add the module file
    git add modules/dbatools.library/
    git commit -m "Add dbatools.library preview version $Version for testing"
    
    # Force push the branch (overwrite if it exists)
    Write-Host "Pushing templib branch..."
    git push origin templib --force
    
    Write-Host "Successfully published dbatools.library $Version to templib branch" -ForegroundColor Green
    
    # Switch back to master
    git checkout master
}
finally {
    Pop-Location
}

# Cleanup temp zip if we created it
if ($zipPath -ne $ModulePath -and (Test-Path $zipPath)) {
    Remove-Item $zipPath -Force
}

Write-Host @"

Next steps:
1. Update .github/dbatools-library-version.json with version: $Version
2. Commit and push the change
3. GitHub Actions will now use this preview version from templib branch

After testing is complete, delete the templib branch:
  git push origin --delete templib

To test immediately without updating the config:
- Go to Actions tab
- Run any workflow manually  
- Enter version: $Version
"@