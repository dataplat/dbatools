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

Write-Output "== firewall off (AppVeyor parity; the NSG still denies all inbound)"
Set-NetFirewallProfile -Profile Domain, Private, Public -Enabled False

Write-Output "== local appveyor admin user (runner service account, AppVeyor parity)"
if (-not (Get-LocalUser -Name appveyor -ErrorAction SilentlyContinue)) {
    $securePass = ConvertTo-SecureString -String "Password12!" -AsPlainText -Force
    $splatUser = @{
        Name                 = "appveyor"
        Password             = $securePass
        PasswordNeverExpires = $true
        AccountNeverExpires  = $true
        FullName             = "CI runner user"
    }
    $null = New-LocalUser @splatUser
    Add-LocalGroupMember -Group Administrators -Member appveyor
}
$null = New-Item -Path "C:\Users\appveyor\Documents\DbatoolsExport" -ItemType Directory -Force -ErrorAction SilentlyContinue

Write-Output "== Windows Update service to Manual (parity with appveyor build_script)"
Set-Service -Name wuauserv -StartupType Manual

Write-Output "== Defender exclusions for hot paths"
Add-MpPreference -ExclusionPath "C:\github", "C:\Temp", "C:\github-runner", "C:\Program Files\Microsoft SQL Server"

Write-Output "== Git for Windows"
if (-not (Test-Path -Path "C:\Program Files\Git\cmd\git.exe")) {
    $gitExe = "C:\Temp\git-setup.exe"
    $webClient.DownloadFile($gitUrl, $gitExe)
    $gitArgs = "/VERYSILENT", "/NORESTART", "/NOCANCEL", "/SP-"
    Start-Process -FilePath $gitExe -ArgumentList $gitArgs -Wait
    Remove-Item -Path $gitExe -Force
}
$machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
if ($machinePath -notlike "*Git\usr\bin*") {
    # unix2dos and friends live in usr\bin; appveyor.yml before_test uses unix2dos
    [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;C:\Program Files\Git\usr\bin", "Machine")
}
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
git --version

Write-Output "== Chocolatey (prep installs codecov through it)"
if (-not (Test-Path -Path "C:\ProgramData\chocolatey\bin\choco.exe")) {
    Invoke-Expression -Command $webClient.DownloadString("https://community.chocolatey.org/install.ps1")
}

Write-Output "== NuGet provider + trusted PSGallery (so Install-Module never prompts)"
$null = Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

Write-Output "== Pester 6.0.0 + PSScriptAnalyzer 1.18.2"
Install-Module -Name Pester -RequiredVersion 6.0.0 -Force -SkipPublisherCheck -Scope AllUsers
Install-Module -Name PSScriptAnalyzer -MaximumVersion 1.18.2 -Force -SkipPublisherCheck -Scope AllUsers

Write-Output "== dbatools clone (development) + dbatools.library"
if (-not (Test-Path -Path "C:\github\dbatools\dbatools.psd1")) {
    if (Test-Path -Path "C:\github\dbatools") {
        Remove-Item -Path "C:\github\dbatools" -Recurse -Force
    }
    # git writes progress to stderr, which must not become a terminating error
    $ErrorActionPreference = "Continue"
    git clone --quiet --branch development https://github.com/dataplat/dbatools.git C:\github\dbatools 2>&1 | Out-Null
    $ErrorActionPreference = "Stop"
    if (-not (Test-Path -Path "C:\github\dbatools\dbatools.psd1")) {
        throw "dbatools clone failed"
    }
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
