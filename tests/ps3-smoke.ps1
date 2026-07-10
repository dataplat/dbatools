<#
.SYNOPSIS
    PowerShell 3.0 smoke test for dbatools on the legacy Server 2012 CI image.

.DESCRIPTION
    Pester 6 requires PowerShell 5.1+, so PS 3.0 coverage is a plain script -- no Pester.

    Designed to run "runnerless" via the Azure guest agent, driven from a GitHub-hosted
    ubuntu-latest job (.github/workflows/ps3-smoke.yml, Phase 4):

        az vm run-command invoke --resource-group $rg --name $vm --command-id RunPowerShellScript --scripts "@tests/ps3-smoke.ps1" --parameters "RepoZipUrl=https://codeload.github.com/dataplat/dbatools/zip/refs/heads/development"

    The script:
      1. Enables TLS 1.2 for .NET (Server 2012 ships with weaker client defaults)
      2. Ensures the dbatools repo is on the box (zipball download, no git required)
      3. Ensures dbatools.library is present (direct nupkg download -- PS 3.0 has no Install-Module)
      4. Imports dbatools and sanity-checks the exported command count
      5. Connects to every named SQL instance on the box and runs a battery of core commands
      6. Prints [PASS]/[FAIL] lines and a [SUMMARY] line, exits nonzero on any failure

    Output stays compact on purpose: az vm run-command caps returned stdout at about 4KB.

.NOTES
    Author: the dbatools team + Claude
    Must stay PowerShell 3.0 compatible: New-Object rather than static constructors,
    no Expand-Archive, no Install-Module, no Import-PowerShellDataFile, no class keyword,
    and no version-subfolder module layout (that needs PS 5.0).
#>
param(
    [string]$RepoPath = "C:\github\dbatools",
    [string]$RepoZipUrl = "https://codeload.github.com/dataplat/dbatools/zip/refs/heads/development",
    [string]$LibraryVersion,
    [string[]]$Instance,
    [switch]$SkipConnect
)

$script:passCount = 0
$script:failCount = 0

function Write-SmokeResult {
    param(
        [string]$Name,
        [switch]$Ok,
        [string]$Detail
    )
    if ($Ok) {
        $script:passCount++
        "[PASS] $Name $Detail"
    } else {
        $script:failCount++
        "[FAIL] $Name $Detail"
    }
}

function Get-SmokeInstancePort {
    # named instances need SQL Browser for localhost\NAME resolution, which may be stopped --
    # reading the port from the registry lets us connect as localhost,PORT instead
    param([string]$InstanceName)
    $instanceKey = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL" -ErrorAction SilentlyContinue
    if (-not $instanceKey) { return $null }
    $instanceId = $instanceKey.$InstanceName
    if (-not $instanceId) { return $null }
    $tcpKey = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceId\MSSQLServer\SuperSocketNetLib\Tcp\IPAll" -ErrorAction SilentlyContinue
    if ($tcpKey.TcpPort) { return ($tcpKey.TcpPort -split ",")[0] }
    if ($tcpKey.TcpDynamicPorts) { return ($tcpKey.TcpDynamicPorts -split ",")[0] }
    return $null
}

"ps3-smoke starting: PS $($PSVersionTable.PSVersion) on $env:COMPUTERNAME"

# Server 2012-era .NET does not offer TLS 1.2 to clients by default and github.com requires it
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]3072
} catch {
    "[WARN] could not enable TLS 1.2: $($_.Exception.Message)"
}

$tempDir = "C:\temp\ps3-smoke"
if (-not (Test-Path -Path $tempDir)) {
    $null = New-Item -Path $tempDir -ItemType Directory -Force
}

# --- Step 1: ensure the dbatools repo is on the box ---
if (Test-Path -Path (Join-Path $RepoPath "dbatools.psd1")) {
    Write-SmokeResult -Name "Fetch repo" -Ok -Detail "(already present at $RepoPath)"
} else {
    try {
        $zipPath = Join-Path $tempDir "dbatools.zip"
        $webClient = New-Object -TypeName System.Net.WebClient
        $webClient.DownloadFile($RepoZipUrl, $zipPath)
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $extractDir = Join-Path $tempDir "repo"
        if (Test-Path -Path $extractDir) {
            Remove-Item -Path $extractDir -Recurse -Force
        }
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractDir)
        # the zipball contains a single dbatools-<ref> folder
        $innerDir = Get-ChildItem -Path $extractDir -Directory | Select-Object -First 1
        $parentDir = Split-Path -Path $RepoPath -Parent
        if (-not (Test-Path -Path $parentDir)) {
            $null = New-Item -Path $parentDir -ItemType Directory -Force
        }
        if (Test-Path -Path $RepoPath) {
            Remove-Item -Path $RepoPath -Recurse -Force
        }
        Move-Item -Path $innerDir.FullName -Destination $RepoPath
        Write-SmokeResult -Name "Fetch repo" -Ok -Detail "(zipball to $RepoPath)"
    } catch {
        Write-SmokeResult -Name "Fetch repo" -Detail $_.Exception.Message
        "[SUMMARY] pass=$($script:passCount) fail=$($script:failCount)"
        exit 1
    }
}

# --- Step 2: ensure dbatools.library is available ---
if (-not $LibraryVersion) {
    $versionFile = Join-Path $RepoPath ".github\dbatools-library-version.json"
    if (Test-Path -Path $versionFile) {
        $LibraryVersion = (Get-Content -Path $versionFile -Raw | ConvertFrom-Json).version
    }
}
$library = Get-Module -Name dbatools.library -ListAvailable | Select-Object -First 1
if ($library) {
    Write-SmokeResult -Name "dbatools.library" -Ok -Detail "(v$($library.Version) already installed)"
} else {
    try {
        $nupkgUrl = "https://www.powershellgallery.com/api/v2/package/dbatools.library/$LibraryVersion"
        $nupkgPath = Join-Path $tempDir "dbatools.library.zip"
        $webClient = New-Object -TypeName System.Net.WebClient
        $webClient.DownloadFile($nupkgUrl, $nupkgPath)
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        # PS 3.0 cannot discover version-subfolder module layouts, so extract flat
        $moduleDir = Join-Path $env:ProgramFiles "WindowsPowerShell\Modules\dbatools.library"
        if (Test-Path -Path $moduleDir) {
            Remove-Item -Path $moduleDir -Recurse -Force
        }
        [System.IO.Compression.ZipFile]::ExtractToDirectory($nupkgPath, $moduleDir)
        Write-SmokeResult -Name "dbatools.library" -Ok -Detail "(v$LibraryVersion from PSGallery)"
    } catch {
        Write-SmokeResult -Name "dbatools.library" -Detail $_.Exception.Message
    }
}

# --- Step 3: import dbatools ---
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
try {
    Import-Module -Name (Join-Path $RepoPath "dbatools.psd1") -ErrorAction Stop
    $stopwatch.Stop()
    Write-SmokeResult -Name "Import-Module dbatools" -Ok -Detail "($([int]$stopwatch.Elapsed.TotalSeconds)s)"
} catch {
    Write-SmokeResult -Name "Import-Module dbatools" -Detail $_.Exception.Message
    "[SUMMARY] pass=$($script:passCount) fail=$($script:failCount)"
    exit 1
}

$commandCount = (Get-Command -Module dbatools -CommandType Function, Cmdlet).Count
Write-SmokeResult -Name "Command count" -Ok:($commandCount -gt 600) -Detail "($commandCount exported)"

# these are ancient lab instances without TLS 1.2 support, so do not require encryption
if (Get-Command -Name Set-DbatoolsInsecureConnection -ErrorAction SilentlyContinue) {
    $null = Set-DbatoolsInsecureConnection
}

# --- Step 4: connect to each instance and run the command battery ---
if ($SkipConnect) {
    "[SKIP] instance battery (SkipConnect)"
} else {
    if (-not $Instance) {
        $Instance = Get-Service -Name "MSSQL`$*" -ErrorAction SilentlyContinue | ForEach-Object { $_.Name.Split("$")[1] }
    }
    if (-not $Instance) {
        Write-SmokeResult -Name "Instance discovery" -Detail "(no named MSSQL services found)"
    }
    foreach ($instanceName in $Instance) {
        $serviceName = "MSSQL`$$instanceName"
        try {
            $service = Get-Service -Name $serviceName -ErrorAction Stop
            if ($service.Status -ne "Running") {
                Set-Service -Name $serviceName -StartupType Manual -ErrorAction SilentlyContinue
                Start-Service -Name $serviceName -ErrorAction Stop
                $deadline = (Get-Date).AddSeconds(90)
                while ((Get-Service -Name $serviceName).Status -ne "Running" -and (Get-Date) -lt $deadline) {
                    Start-Sleep -Seconds 3
                }
                # give the engine a moment to finish recovery before connecting
                Start-Sleep -Seconds 5
            }
        } catch {
            Write-SmokeResult -Name "$instanceName service" -Detail $_.Exception.Message
            continue
        }

        $port = Get-SmokeInstancePort -InstanceName $instanceName
        if ($port) {
            $target = "localhost,$port"
        } else {
            $target = "localhost\$instanceName"
        }

        try {
            $splatConnect = @{
                SqlInstance            = $target
                TrustServerCertificate = $true
                ErrorAction            = "Stop"
            }
            $server = Connect-DbaInstance @splatConnect
            Write-SmokeResult -Name "$instanceName connect" -Ok -Detail "($target is v$($server.VersionString))"
        } catch {
            Write-SmokeResult -Name "$instanceName connect" -Detail "($target) $($_.Exception.Message)"
            continue
        }

        try {
            $databases = Get-DbaDatabase -SqlInstance $server -ErrorAction Stop
            $hasMaster = ($databases | Where-Object Name -eq "master").Count -eq 1
            Write-SmokeResult -Name "$instanceName Get-DbaDatabase" -Ok:$hasMaster -Detail "($($databases.Count) databases)"
        } catch {
            Write-SmokeResult -Name "$instanceName Get-DbaDatabase" -Detail $_.Exception.Message
        }

        try {
            $splatQuery = @{
                SqlInstance = $server
                Query       = "SELECT @@VERSION AS Version"
                ErrorAction = "Stop"
            }
            $queryResult = Invoke-DbaQuery @splatQuery
            $versionLine = ("$($queryResult.Version)" -split "\r?\n")[0]
            Write-SmokeResult -Name "$instanceName Invoke-DbaQuery" -Ok:($null -ne $queryResult.Version) -Detail "($versionLine)"
        } catch {
            Write-SmokeResult -Name "$instanceName Invoke-DbaQuery" -Detail $_.Exception.Message
        }

        try {
            $logins = Get-DbaLogin -SqlInstance $server -ErrorAction Stop
            Write-SmokeResult -Name "$instanceName Get-DbaLogin" -Ok:($logins.Count -gt 0) -Detail "($($logins.Count) logins)"
        } catch {
            Write-SmokeResult -Name "$instanceName Get-DbaLogin" -Detail $_.Exception.Message
        }

        try {
            $processes = Get-DbaProcess -SqlInstance $server -ErrorAction Stop
            Write-SmokeResult -Name "$instanceName Get-DbaProcess" -Ok:($processes.Count -gt 0) -Detail "($($processes.Count) spids)"
        } catch {
            Write-SmokeResult -Name "$instanceName Get-DbaProcess" -Detail $_.Exception.Message
        }
    }
}

"[SUMMARY] pass=$($script:passCount) fail=$($script:failCount)"
if ($script:failCount -gt 0) {
    exit 1
}
exit 0
