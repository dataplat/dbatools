<#
.SYNOPSIS
    Image-build step 1: tooling and modules on the Server 2022 base.

.DESCRIPTION
    Installs everything appveyor.prep.ps1 expects to find on a worker so per-build prep
    behaves identically to AppVeyor: Git for Windows (full, so usr\bin has unix2dos),
    Chocolatey (prep runs choco install codecov), the NuGet package provider (so
    Install-Module never prompts), Pester 6 / PSScriptAnalyzer / dbatools.library,
    a full dbatools clone at C:\github\dbatools, the pinned actions runner staged at
    C:\github-runner, WinRM enabled, and Defender exclusions for the hot paths.

.NOTES
    Author: the dbatools team + Claude
    Runs as SYSTEM via run-step.ps1 on the image-build VM.
#>
param(
    [string]$ArgsPath
)

$ErrorActionPreference = "Stop"
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]3072
$webClient = New-Object -TypeName System.Net.WebClient

$gitUrl = "https://github.com/git-for-windows/git/releases/download/v2.55.0.windows.2/Git-2.55.0.2-64-bit.exe"
$runnerUrl = "https://github.com/actions/runner/releases/download/v2.335.1/actions-runner-win-x64-2.335.1.zip"

foreach ($dir in "C:\Temp", "C:\github", "C:\github-runner") {
    if (-not (Test-Path -Path $dir)) {
        $null = New-Item -Path $dir -ItemType Directory -Force
    }
}

Write-Output "== network profile + WinRM (prep runs Set-WSManQuickConfig)"
Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private
Enable-PSRemoting -Force -SkipNetworkProfileCheck

Write-Output "== Windows Update service to Manual (parity with appveyor build_script)"
Set-Service -Name wuauserv -StartupType Manual

Write-Output "== Defender exclusions for hot paths"
Add-MpPreference -ExclusionPath "C:\github", "C:\Temp", "C:\github-runner", "C:\Program Files\Microsoft SQL Server"

Write-Output "== Git for Windows"
$gitExe = "C:\Temp\git-setup.exe"
$webClient.DownloadFile($gitUrl, $gitExe)
$gitArgs = "/VERYSILENT", "/NORESTART", "/NOCANCEL", "/SP-"
Start-Process -FilePath $gitExe -ArgumentList $gitArgs -Wait
Remove-Item -Path $gitExe -Force
$machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
if ($machinePath -notlike "*Git\usr\bin*") {
    # unix2dos and friends live in usr\bin; appveyor.yml before_test uses unix2dos
    [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;C:\Program Files\Git\usr\bin", "Machine")
}
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
git --version

Write-Output "== Chocolatey (prep installs codecov through it)"
Invoke-Expression -Command $webClient.DownloadString("https://community.chocolatey.org/install.ps1")

Write-Output "== NuGet provider + trusted PSGallery (so Install-Module never prompts)"
$null = Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

Write-Output "== Pester 6.0.0 + PSScriptAnalyzer 1.18.2"
Install-Module -Name Pester -RequiredVersion 6.0.0 -Force -SkipPublisherCheck -Scope AllUsers
Install-Module -Name PSScriptAnalyzer -MaximumVersion 1.18.2 -Force -SkipPublisherCheck -Scope AllUsers

Write-Output "== dbatools clone (development) + dbatools.library"
if (-not (Test-Path -Path "C:\github\dbatools\dbatools.psd1")) {
    git clone --branch development https://github.com/dataplat/dbatools.git C:\github\dbatools 2>&1 | Select-Object -Last 2
}
& C:\github\dbatools\.github\scripts\install-dbatools-library.ps1 -Scope AllUsers
$library = Get-Module -Name dbatools.library -ListAvailable | Select-Object -First 1
Write-Output "dbatools.library installed: v$($library.Version)"

Write-Output "== actions runner 2.335.1 staged at C:\github-runner"
$runnerZip = "C:\Temp\runner.zip"
$webClient.DownloadFile($runnerUrl, $runnerZip)
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($runnerZip, "C:\github-runner")
Remove-Item -Path $runnerZip -Force

Write-Output "== summary"
$runnerStaged = Test-Path -Path "C:\github-runner\config.cmd"
Write-Output "git: $(git --version)"
Write-Output "choco: $(choco --version)"
Write-Output "Pester: $((Get-Module -Name Pester -ListAvailable | Select-Object -First 1).Version)"
Write-Output "PSScriptAnalyzer: $((Get-Module -Name PSScriptAnalyzer -ListAvailable | Select-Object -First 1).Version)"
Write-Output "runner staged: $runnerStaged"
Get-PSDrive -Name C | ForEach-Object { "C: free $([math]::Round($_.Free / 1GB, 1)) GB" }
