<#
.SYNOPSIS
    Image-build step 2: unattended install of one SQL Server Developer named instance.

.DESCRIPTION
    Parameterized via the step args json written by invoke-step-async.ps1:

        { "instance": "SQL2022", "port": "14336", "logDirVersion": "160",
          "mediaUrl": "https://download.microsoft.com/...Dev.iso" }

    mediaUrl may be a direct ISO or an SSEI bootstrapper exe (SQL 2017 has no stable
    direct ISO link); SSEI downloads the ISO itself. After install the instance gets
    the static port from tests/appveyor.SQL*.ps1 baked into the registry, and both the
    engine and Agent services are stopped and set to Manual -- the per-build scripts
    start and configure them, exactly like on AppVeyor. Mixed auth with the AppVeyor
    convention sa password keeps test expectations identical.

.NOTES
    Author: the dbatools team + Claude
    Runs as SYSTEM via run-step.ps1 on the image-build VM.
#>
param(
    [Parameter(Mandatory)]
    [string]$ArgsPath
)

$ErrorActionPreference = "Stop"
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]3072

$stepArgs = Get-Content -Path $ArgsPath -Raw | ConvertFrom-Json
$instance = $stepArgs.instance
$port = $stepArgs.port
$logDirVersion = $stepArgs.logDirVersion
$mediaUrl = $stepArgs.mediaUrl
$saPassword = "Password12!"

$mediaDir = "C:\media"
if (-not (Test-Path -Path $mediaDir)) {
    $null = New-Item -Path $mediaDir -ItemType Directory -Force
}

$webClient = New-Object -TypeName System.Net.WebClient
$isoPath = $null
if ($mediaUrl -match "\.iso$") {
    Write-Output "== downloading ISO for $instance"
    $isoPath = Join-Path $mediaDir "$instance.iso"
    $webClient.DownloadFile($mediaUrl, $isoPath)
} else {
    Write-Output "== downloading SSEI bootstrapper for $instance and pulling the ISO"
    $sseiPath = Join-Path $mediaDir "$instance-ssei.exe"
    $webClient.DownloadFile($mediaUrl, $sseiPath)
    $sseiArgs = "/ACTION=Download", "/MEDIAPATH=$mediaDir", "/MEDIATYPE=ISO", "/QUIET"
    Start-Process -FilePath $sseiPath -ArgumentList $sseiArgs -Wait
    $isoPath = (Get-ChildItem -Path $mediaDir -Filter "*.iso" | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
    Remove-Item -Path $sseiPath -Force
}
if (-not $isoPath -or -not (Test-Path -Path $isoPath)) {
    throw "no ISO found for $instance"
}
Write-Output "ISO: $isoPath ($([math]::Round((Get-Item -Path $isoPath).Length / 1GB, 2)) GB)"

Write-Output "== mounting ISO"
$mount = Mount-DiskImage -ImagePath $isoPath -PassThru
$driveLetter = ($mount | Get-Volume).DriveLetter
$setupExe = "${driveLetter}:\setup.exe"
if (-not (Test-Path -Path $setupExe)) {
    throw "setup.exe not found on mounted ISO at $setupExe"
}

$iniPath = "C:\imagebuild\$instance.ini"
$iniContent = @"
[OPTIONS]
ACTION="Install"
QUIET="True"
FEATURES=SQLENGINE
INSTANCENAME="$instance"
SQLSYSADMINACCOUNTS="BUILTIN\Administrators" "NT AUTHORITY\SYSTEM"
SECURITYMODE="SQL"
TCPENABLED="1"
NPENABLED="0"
UPDATEENABLED="False"
SQLSVCINSTANTFILEINIT="True"
IACCEPTSQLSERVERLICENSETERMS="True"
INDICATEPROGRESS="False"
"@
Set-Content -Path $iniPath -Value $iniContent

Write-Output "== running setup for $instance (this takes a while)"
$setupArgs = "/ConfigurationFile=$iniPath", "/SAPWD=$saPassword"
$process = Start-Process -FilePath $setupExe -ArgumentList $setupArgs -Wait -PassThru
Write-Output "setup exit code: $($process.ExitCode)"
if ($process.ExitCode -notin 0, 3010) {
    $summaryPath = "C:\Program Files\Microsoft SQL Server\$logDirVersion\Setup Bootstrap\Log\Summary.txt"
    if (Test-Path -Path $summaryPath) {
        Write-Output "--- Summary.txt tail ---"
        Get-Content -Path $summaryPath -Tail 25 | ForEach-Object { $_ }
    }
    throw "SQL setup for $instance failed with exit code $($process.ExitCode)"
}

Write-Output "== baking static port $port into the registry"
$instanceKey = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL"
$instanceId = $instanceKey.$instance
$tcpPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceId\MSSQLServer\SuperSocketNetLib\Tcp\IPAll"
Set-ItemProperty -Path $tcpPath -Name TcpPort -Value "$port"
Set-ItemProperty -Path $tcpPath -Name TcpDynamicPorts -Value ""

Write-Output "== stopping services and setting Manual start"
foreach ($serviceName in "SQLAgent`$$instance", "MSSQL`$$instance") {
    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
    Set-Service -Name $serviceName -StartupType Manual
}

Write-Output "== cleanup"
Dismount-DiskImage -ImagePath $isoPath
Remove-Item -Path $isoPath -Force
Get-PSDrive -Name C | ForEach-Object { "C: free $([math]::Round($_.Free / 1GB, 1)) GB" }
Write-Output "$instance installed: id=$instanceId port=$port"
