<#
.SYNOPSIS
    Phase 0 Gate B: install and register an ephemeral GitHub Actions runner via az vm run-command.

.DESCRIPTION
    Downloads the actions runner, first verifies the .NET 8 Runner.Listener binary actually
    starts on this OS (the real Gate B question on Server 2012), then registers it as an
    ephemeral service. Mirrors what the production bootstrap script will do on the VMSS.

    The registration token is minted just in time (single use, 1 hour expiry) and never
    stored on the VM:

        TOKEN=$(gh api -X POST repos/dataplat/dbatools/actions/runners/registration-token --jq .token)
        az vm run-command invoke --resource-group dbatools-ci-phase0 --name dbat-phase0 --command-id RunPowerShellScript --scripts "@.github/runners/phase0/install-runner.ps1" --parameters "Token=$TOKEN" "ZipUrl=https://github.com/actions/runner/releases/download/v2.335.1/actions-runner-win-x64-2.335.1.zip"

.NOTES
    Author: the dbatools team + Claude
    PowerShell 3.0 compatible.
#>
param(
    [string]$Token,
    [string]$ZipUrl,
    [string]$RepoUrl = "https://github.com/dataplat/dbatools",
    [string]$RunnerName = "phase0-2012",
    [string]$Labels = "scratch-2012",
    [string]$Root = "C:\gha-runner"
)
$ErrorActionPreference = "Stop"

try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]3072
    "TLS 1.2 enabled for this session"
} catch {
    "[WARN] could not enable TLS 1.2: $($_.Exception.Message)"
}

if (Test-Path -Path $Root) {
    Remove-Item -Path $Root -Recurse -Force
}
$null = New-Item -Path $Root -ItemType Directory -Force

$zipPath = Join-Path $Root "runner.zip"
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$webClient = New-Object -TypeName System.Net.WebClient
$webClient.DownloadFile($ZipUrl, $zipPath)
"downloaded $([math]::Round((Get-Item -Path $zipPath).Length / 1MB, 1)) MB in $([int]$stopwatch.Elapsed.TotalSeconds)s"

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $Root)
"extracted"

Set-Location -Path $Root

# native commands write progress to stderr, which must not become terminating errors
$ErrorActionPreference = "Continue"

# Gate B, part 1: does the .NET 8 runner binary even start on this OS?
try {
    $listenerOutput = & .\bin\Runner.Listener.exe --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        "Runner.Listener.exe version: $listenerOutput"
    } else {
        "[GATE B FAIL] Runner.Listener.exe exit ${LASTEXITCODE}: $listenerOutput"
        exit 1
    }
} catch {
    "[GATE B FAIL] Runner.Listener.exe threw: $($_.Exception.Message)"
    exit 1
}

# Gate B, part 2: register as an ephemeral service, same shape as the production bootstrap
$configArgs = @(
    "--url", $RepoUrl,
    "--token", $Token,
    "--name", $RunnerName,
    "--labels", $Labels,
    "--work", "_work",
    "--unattended",
    "--ephemeral",
    "--disableupdate",
    "--runasservice",
    "--windowslogonaccount", "NT AUTHORITY\SYSTEM"
)
& .\config.cmd @configArgs 2>&1 | ForEach-Object { "$_" }
"config.cmd exit: $LASTEXITCODE"

Get-Service -Name "actions.runner.*" -ErrorAction SilentlyContinue | ForEach-Object {
    "service: $($_.Name) [$($_.Status)]"
}
