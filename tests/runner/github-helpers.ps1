# GitHub Actions helper functions - equivalents of AppVeyor cmdlets
# This file provides compatibility for migrated test scripts

function Add-GitHubTest {
    param(
        [string]$Name,
        [string]$Framework,
        [string]$FileName,
        [string]$Outcome
    )

    if ($Outcome -eq "Running") {
        Write-Host "::group::$Name"
        Write-Host "▶️  Starting: $FileName" -ForegroundColor Cyan
    }
}

function Update-GitHubTest {
    param(
        [string]$Name,
        [string]$Framework,
        [string]$FileName,
        [string]$Outcome,
        [int]$Duration
    )

    if ($Outcome -eq "Passed") {
        Write-Host "✅ Passed: $FileName (${Duration}ms)" -ForegroundColor Green
    } elseif ($Outcome -eq "Failed") {
        Write-Host "::error::❌ Failed: $FileName (${Duration}ms)"
    }
    Write-Host "::endgroup::"
}

function Exit-GitHubBuild {
    Write-Host "::notice::Exiting build early (no tests to run)"
    exit 0
}

function Push-GitHubArtifact {
    param(
        [string]$Path,
        [string]$FileName
    )
    # GitHub Actions artifacts are uploaded via actions/upload-artifact
    # This is a no-op placeholder - actual upload happens in workflow
    Write-Host "📦 Artifact queued: $FileName" -ForegroundColor Yellow
}

# Create aliases for backward compatibility
Set-Alias -Name Add-AppveyorTest -Value Add-GitHubTest
Set-Alias -Name Update-AppveyorTest -Value Update-GitHubTest
Set-Alias -Name Exit-AppveyorBuild -Value Exit-GitHubBuild
Set-Alias -Name Push-AppveyorArtifact -Value Push-GitHubArtifact

Export-ModuleMember -Function * -Alias *
