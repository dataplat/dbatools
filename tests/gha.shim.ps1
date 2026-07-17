<#
.SYNOPSIS
    AppVeyor compatibility shim for running the untouched appveyor.*.ps1 harness on
    GitHub Actions self-hosted runners.

.DESCRIPTION
    Dot-source this at the start of the CI step, then run stages through
    Invoke-GhaStage. It provides:

      - The APPVEYOR_* environment variables the harness reads. APPVEYOR=True also
        steers Get-TestConfig into its AppVeyor branch (COMPUTERNAME\INSTANCE mapping,
        C:\github\appveyor-lab, C:\Temp), which is exactly right on the golden image.
      - Add-AppveyorTest / Update-AppveyorTest -> log lines plus a markdown table in
        the GitHub step summary, with ::error annotations on failures.
      - Push-AppveyorArtifact -> copies into C:\Temp\gha-artifacts and notes it in
        the summary.
      - Exit-AppveyorBuild -> drops a flag that makes later Invoke-GhaStage calls
        no-ops (prep uses this to exit early when a build has nothing to run).
      - Invoke-GhaStage -> runs one appveyor.*.ps1 stage in THIS session, mirroring
        AppVeyor keeping a single PowerShell session across build script lines
        (imported modules persist from prep into the later stages).
      - Repair-GhaSqlServerName -> after instance startup, aligns @@SERVERNAME with
        the actual computer name (golden-image instances were installed on the build
        VM, so the first boot on a fresh VM carries a stale name).

    AppVeyor itself never loads this file, so AppVeyor behavior cannot change.

.NOTES
    Author: the dbatools team + Claude
#>

$global:GhaArtifactDir = "C:\Temp\gha-artifacts"
$global:GhaExitFlag = "C:\Temp\gha-exit-build.flag"
$global:GhaSummaryStarted = $false

if (-not (Test-Path -Path "C:\Temp")) {
    $null = New-Item -Path "C:\Temp" -ItemType Directory -Force
}
Remove-Item -Path $global:GhaExitFlag -Force -ErrorAction SilentlyContinue

# prep installs dbatools.library WITHOUT -Force (unlike its Pester/PSScriptAnalyzer
# installs), so an untrusted PSGallery turns that install into a silent no-op in a
# non-interactive session ("User declined to install module") and the golden image
# keeps serving whatever library version it was baked with
try {
    if ((Get-PSRepository -Name PSGallery -ErrorAction Stop).InstallationPolicy -ne "Trusted") {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        Write-Host -Object "[gha] PSGallery marked trusted for module installs" -ForegroundColor DarkCyan
    }
} catch {
    Write-Host -Object "[gha] PSGallery trust setup skipped: $($_.Exception.Message)" -ForegroundColor Yellow
}

# ---- environment mapping (idempotent, only fills what is not already set) ----
if (-not $env:APPVEYOR) {
    $env:APPVEYOR = "True"
}
if (-not $env:APPVEYOR_BUILD_FOLDER) {
    $env:APPVEYOR_BUILD_FOLDER = "C:\github\dbatools"
}
if (-not $env:APPVEYOR_REPO_BRANCH) {
    if ($env:GITHUB_BASE_REF) {
        $env:APPVEYOR_REPO_BRANCH = $env:GITHUB_BASE_REF
    } else {
        $env:APPVEYOR_REPO_BRANCH = $env:GITHUB_REF_NAME
    }
}
if (-not $env:APPVEYOR_BUILD_VERSION) {
    $env:APPVEYOR_BUILD_VERSION = "2.1.$env:GITHUB_RUN_NUMBER"
}
if (-not $env:APPVEYOR_REPO_COMMIT_MESSAGE) {
    $fullMessage = $env:DBATOOLS_COMMIT_MESSAGE
    if (-not $fullMessage) {
        $fullMessage = (git -C $env:APPVEYOR_BUILD_FOLDER log -1 --pretty=%B 2>$null | Out-String)
    }
    $messageLines = "$fullMessage" -split "\r?\n"
    $env:APPVEYOR_REPO_COMMIT_MESSAGE = $messageLines[0]
    if ($messageLines.Count -gt 1) {
        $env:APPVEYOR_REPO_COMMIT_MESSAGE_EXTENDED = ($messageLines[1..($messageLines.Count - 1)] -join "`n").Trim()
    }
}

function Write-GhaSummary {
    param([string]$Line)
    if ($env:GITHUB_STEP_SUMMARY) {
        Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $Line
    }
}

function Add-AppveyorTest {
    param(
        [string]$Name,
        [string]$Framework,
        [string]$FileName,
        [string]$Outcome,
        [double]$Duration,
        [string]$ErrorMessage,
        [string]$ErrorStackTrace,
        [string]$StdOut,
        [string]$StdErr
    )
    Write-Host -Object "[gha] test started: $Name" -ForegroundColor DarkCyan
}

function Update-AppveyorTest {
    param(
        [string]$Name,
        [string]$Framework,
        [string]$FileName,
        [string]$Outcome,
        [double]$Duration,
        [string]$ErrorMessage,
        [string]$ErrorStackTrace,
        [string]$StdOut,
        [string]$StdErr
    )
    $seconds = [math]::Round($Duration / 1000, 1)
    Write-Host -Object "[gha] test $($Outcome.ToLower()): $Name (${seconds}s)" -ForegroundColor DarkCyan
    if (-not $global:GhaSummaryStarted) {
        Write-GhaSummary -Line "| Test | Outcome | Duration |"
        Write-GhaSummary -Line "| --- | --- | --- |"
        $global:GhaSummaryStarted = $true
    }
    Write-GhaSummary -Line "| $Name | $Outcome | ${seconds}s |"
    if ($Outcome -eq "Failed") {
        $singleLineError = "$ErrorMessage" -replace "\r?\n", " -- "
        if ($singleLineError.Length -gt 900) {
            $singleLineError = $singleLineError.Substring(0, 900)
        }
        Write-Output "::error title=$Name::$singleLineError"
    }
}

function Push-AppveyorArtifact {
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,
        [string]$FileName
    )
    if (-not (Test-Path -Path $global:GhaArtifactDir)) {
        $null = New-Item -Path $global:GhaArtifactDir -ItemType Directory -Force
    }
    if (-not $FileName) {
        $FileName = Split-Path -Path $Path -Leaf
    }
    if (Test-Path -Path $Path) {
        Copy-Item -Path $Path -Destination (Join-Path $global:GhaArtifactDir $FileName) -Force
        Write-Host -Object "[gha] artifact staged: $FileName" -ForegroundColor DarkCyan
    } else {
        Write-Host -Object "[gha] artifact missing, skipped: $Path" -ForegroundColor Yellow
    }
}

function Exit-AppveyorBuild {
    Set-Content -Path $global:GhaExitFlag -Value "requested at $(Get-Date -Format o)"
    Write-Host -Object "[gha] Exit-AppveyorBuild: remaining stages will be skipped" -ForegroundColor Yellow
    Write-GhaSummary -Line "Build exited early: nothing to run for this change."
}

function Invoke-GhaStage {
    param(
        [Parameter(Mandatory)]
        [string]$Script,
        [hashtable]$Arguments
    )
    if (Test-Path -Path $global:GhaExitFlag) {
        Write-Host -Object "[gha] skipping $Script (build exited early)" -ForegroundColor Yellow
        return
    }
    $fullPath = Join-Path $env:APPVEYOR_BUILD_FOLDER $Script
    Write-Host -Object "`n===== stage: $Script =====" -ForegroundColor Green
    $stageWatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        if ($Arguments) {
            & $fullPath @Arguments
        } else {
            & $fullPath
        }
    } catch {
        # AppVeyor parity: a build-script line that throws fails the build right
        # there -- later lines never run. Without this, a dead prep stage lets the
        # instance setup run without dbatools and the suite fails in confusing ways.
        $stageWatch.Stop()
        Write-Output "::error title=$Script::stage threw: $($_.Exception.Message)"
        Write-Host -Object "===== stage FAILED: $Script ($([int]$stageWatch.Elapsed.TotalSeconds)s) =====" -ForegroundColor Red
        exit 1
    }
    $stageWatch.Stop()
    # GitHub's PowerShell wrapper exits with a stale native command status even
    # after the AppVeyor stage itself succeeds. A thrown stage still exits above.
    $global:LASTEXITCODE = 0
    Write-Host -Object "===== stage done: $Script ($([int]$stageWatch.Elapsed.TotalSeconds)s) =====" -ForegroundColor Green
}

function Assert-GhaDbatoolsLoaded {
    # the harness only WARNS when the manifest cannot load (EAP=Continue), so a
    # library/manifest version mismatch would otherwise surface minutes later as
    # CommandNotFoundException noise inside the instance setup scripts
    if (Test-Path -Path $global:GhaExitFlag) {
        return
    }
    if (-not (Get-Module -Name dbatools)) {
        Write-Output "::error title=dbatools import::dbatools is not loaded after prep -- check the dbatools.library install/version (image vs .github/dbatools-library-version.json)"
        exit 1
    }
    $libraryModule = Get-Module -Name dbatools.library
    Write-Host -Object "[gha] dbatools $((Get-Module -Name dbatools).Version) loaded with dbatools.library $($libraryModule.Version)" -ForegroundColor DarkCyan
}

function Repair-GhaSqlServerName {
    # golden-image instances remember the build VM name until repaired; several
    # dbatools tests expect @@SERVERNAME to match the actual host
    if (Test-Path -Path $global:GhaExitFlag) {
        return
    }
    $runningEngines = Get-Service -Name "MSSQL`$*" -ErrorAction SilentlyContinue | Where-Object Status -eq "Running"
    foreach ($engineService in $runningEngines) {
        $instanceName = $engineService.Name.Split("$")[1]
        $expectedName = "$env:COMPUTERNAME\$instanceName"
        try {
            $connection = New-Object -TypeName System.Data.SqlClient.SqlConnection
            $connection.ConnectionString = "Server=localhost\$instanceName;Integrated Security=true;TrustServerCertificate=true;Connect Timeout=30"
            $connection.Open()
            $command = $connection.CreateCommand()
            $command.CommandText = "SELECT @@SERVERNAME"
            $currentName = "$($command.ExecuteScalar())"
            if ($currentName -and $currentName -ne $expectedName) {
                Write-Host -Object "[gha] repairing @@SERVERNAME on ${instanceName}: $currentName -> $expectedName" -ForegroundColor Yellow
                $command.CommandText = "EXEC sp_dropserver @old"
                $null = $command.Parameters.AddWithValue("@old", $currentName)
                $null = $command.ExecuteNonQuery()
                $command.Parameters.Clear()
                $command.CommandText = "EXEC sp_addserver @new, @loc"
                $null = $command.Parameters.AddWithValue("@new", $expectedName)
                $null = $command.Parameters.AddWithValue("@loc", "local")
                $null = $command.ExecuteNonQuery()
                $connection.Close()
                $agentService = Get-Service -Name "SQLAgent`$$instanceName" -ErrorAction SilentlyContinue
                $agentWasRunning = $agentService -and $agentService.Status -eq "Running"
                Restart-Service -Name $engineService.Name -Force
                if ($agentWasRunning) {
                    Start-Service -Name "SQLAgent`$$instanceName" -ErrorAction SilentlyContinue
                }
            } else {
                $connection.Close()
            }
        } catch {
            Write-Host -Object "[gha] servername repair skipped for ${instanceName}: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}
