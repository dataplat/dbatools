<#
.SYNOPSIS
    Builds the dbatools-modern-image golden image (Server 2022 + SQL 2017/2019/2022).

.DESCRIPTION
    One-command, fully scripted image build -- no Packer, just az CLI plus the step
    scripts in .github/runners/image-scripts/, so every stage can be rerun or debugged
    by hand with az vm run-command. This is also how a future instance (say sql2025)
    gets added: extend the $instances list, bump -ImageVersion, rerun.

    Flow:
      1. Scratch RG + Server 2022 (Gen1) build VM with a managed OS disk (ephemeral
         disks cannot be captured)
      2. step1-tools: git, chocolatey, NuGet provider, Pester 6, PSScriptAnalyzer,
         dbatools.library, dbatools clone, staged actions runner, WinRM, Defender
         exclusions
      3. step2-sqlinstance x3: SQL 2017/2019/2022 Developer named instances, static
         ports 14334/14335/14336 (matching tests/appveyor.SQL*.ps1), services stopped
         and Manual, mixed auth with the AppVeyor-convention sa password
      4. step3-sysprep: cleanup, generalize, shutdown
      5. Deallocate + generalize + capture into the compute gallery, 2 replicas
      6. Delete the scratch RG

    Steps run asynchronously in-guest (scheduled tasks) and are polled, because SQL
    installs outlast comfortable run-command round trips.

.PARAMETER Branch
    Repo branch the build VM downloads the step scripts from.

.PARAMETER ImageVersion
    Gallery image version to publish, e.g. 1.0.0.

.NOTES
    Author: the dbatools team + Claude
    Requires: az CLI logged in to the sponsorship subscription.

.EXAMPLE
    ./.github/runners/build-modern-image.ps1 -ImageVersion 1.0.0 -Branch development
#>
param(
    [string]$Branch = "development",
    [Parameter(Mandatory)]
    [string]$ImageVersion,
    [string]$ResourceGroup = "dbatools-ci-imagebuild",
    [string]$VmName = "dbat-imgbuild",
    [string]$Location = "eastus",
    [string]$GalleryResourceGroup = "DBATOOLS-CI-IMAGES",
    [string]$GalleryName = "dbatoolsGallery",
    [string]$ImageDefinition = "dbatools-modern-image",
    [int]$ReplicaCount = 2,
    [switch]$SkipVmCreate,
    [switch]$KeepBuildVm
)

$ErrorActionPreference = "Stop"
$rawBase = "https://raw.githubusercontent.com/dataplat/dbatools/$Branch"

$instances = @(
    [PSCustomObject]@{
        Instance      = "SQL2017"
        Port          = "14334"
        LogDirVersion = "140"
        MediaUrl      = "https://go.microsoft.com/fwlink/?linkid=853016"
    }
    [PSCustomObject]@{
        Instance      = "SQL2019"
        Port          = "14335"
        LogDirVersion = "150"
        MediaUrl      = "https://download.microsoft.com/download/8/4/c/84c6c430-e0f5-476d-bf43-eaaa222a72e0/SQLServer2019-x64-ENU-Dev.iso"
    }
    [PSCustomObject]@{
        Instance      = "SQL2022"
        Port          = "14336"
        LogDirVersion = "160"
        MediaUrl      = "https://download.microsoft.com/download/3/8/d/38de7036-2433-4207-8eae-06e247e17b25/SQLServer2022-x64-ENU-Dev.iso"
    }
)

function Invoke-BuildStep {
    param(
        [Parameter(Mandatory)]
        [string]$Step,
        [string]$ArgsJson,
        [int]$TimeoutMinutes = 45,
        [switch]$NoWaitForStatus
    )
    Write-Host "== launching $Step" -ForegroundColor Cyan
    $launchArgs = @(
        "vm", "run-command", "invoke",
        "--resource-group", $ResourceGroup,
        "--name", $VmName,
        "--command-id", "RunPowerShellScript",
        "--scripts", "@.github/runners/image-scripts/invoke-step-async.ps1",
        "--parameters", "RawBase=$rawBase", "Step=$Step"
    )
    if ($ArgsJson) {
        $launchArgs += "ArgsJson=$ArgsJson"
    }
    $null = az @launchArgs --only-show-errors
    if ($NoWaitForStatus) {
        return
    }
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 60
        $pollArgs = @(
            "vm", "run-command", "invoke",
            "--resource-group", $ResourceGroup,
            "--name", $VmName,
            "--command-id", "RunPowerShellScript",
            "--scripts", "@.github/runners/image-scripts/poll-step.ps1",
            "--parameters", "Step=$Step",
            "--query", "value[0].message",
            "--output", "tsv"
        )
        $status = az @pollArgs --only-show-errors
        $firstLine = ($status -split "\r?\n")[0]
        Write-Host "   $Step : $firstLine"
        if ($firstLine -match "STATUS: done") {
            return
        }
        if ($firstLine -match "STATUS: fail") {
            Write-Host ($status | Out-String)
            throw "$Step failed -- see log tail above and C:\imagebuild\$Step.log on the VM"
        }
    }
    throw "$Step timed out after $TimeoutMinutes minutes"
}

if (-not $SkipVmCreate) {
    Write-Host "== creating build RG + VM" -ForegroundColor Cyan
    $null = az group create --name $ResourceGroup --location $Location --tags purpose=modern-image-build --output none --only-show-errors
    $password = "Db" + (-join ((65..90) + (97..122) + (48..57) | Get-Random -Count 16 | ForEach-Object { [char]$_ })) + "!7q"
    $createArgs = @(
        "vm", "create",
        "--resource-group", $ResourceGroup,
        "--name", $VmName,
        "--image", "MicrosoftWindowsServer:WindowsServer:2022-datacenter-smalldisk:latest",
        "--size", "Standard_D4ds_v5",
        "--admin-username", "dbatools",
        "--admin-password", $password,
        "--nsg-rule", "NONE",
        "--public-ip-sku", "Standard",
        "--os-disk-size-gb", "64",
        "--storage-sku", "StandardSSD_LRS",
        "--output", "none"
    )
    az @createArgs --only-show-errors
}

Invoke-BuildStep -Step "step1-tools" -TimeoutMinutes 30
foreach ($sql in $instances) {
    $argsJson = ConvertTo-Json -InputObject @{
        instance      = $sql.Instance
        port          = $sql.Port
        logDirVersion = $sql.LogDirVersion
        mediaUrl      = $sql.MediaUrl
    } -Compress
    Invoke-BuildStep -Step "step2-sqlinstance" -ArgsJson $argsJson -TimeoutMinutes 60
}
Invoke-BuildStep -Step "step3-sysprep" -NoWaitForStatus

Write-Host "== waiting for sysprep shutdown" -ForegroundColor Cyan
$deadline = (Get-Date).AddMinutes(20)
do {
    Start-Sleep -Seconds 30
    $powerState = az vm show -d --resource-group $ResourceGroup --name $VmName --query powerState --output tsv --only-show-errors
    Write-Host "   power state: $powerState"
} while ($powerState -ne "VM stopped" -and (Get-Date) -lt $deadline)
if ($powerState -ne "VM stopped") {
    throw "VM did not shut down after sysprep"
}

Write-Host "== deallocate + generalize + capture" -ForegroundColor Cyan
az vm deallocate --resource-group $ResourceGroup --name $VmName --only-show-errors
az vm generalize --resource-group $ResourceGroup --name $VmName --only-show-errors

$definitionExists = az sig image-definition show --resource-group $GalleryResourceGroup --gallery-name $GalleryName --gallery-image-definition $ImageDefinition --only-show-errors 2>$null
if (-not $definitionExists) {
    $definitionArgs = @(
        "sig", "image-definition", "create",
        "--resource-group", $GalleryResourceGroup,
        "--gallery-name", $GalleryName,
        "--gallery-image-definition", $ImageDefinition,
        "--publisher", "dbatools",
        "--offer", "dbatools-ci",
        "--sku", "modern-sql2017-2019-2022",
        "--os-type", "Windows",
        "--os-state", "Generalized",
        "--hyper-v-generation", "V1",
        "--output", "none"
    )
    az @definitionArgs --only-show-errors
}

$vmId = az vm show --resource-group $ResourceGroup --name $VmName --query id --output tsv --only-show-errors
$versionArgs = @(
    "sig", "image-version", "create",
    "--resource-group", $GalleryResourceGroup,
    "--gallery-name", $GalleryName,
    "--gallery-image-definition", $ImageDefinition,
    "--gallery-image-version", $ImageVersion,
    "--virtual-machine", $vmId,
    "--replica-count", $ReplicaCount,
    "--storage-account-type", "Standard_LRS",
    "--output", "none"
)
az @versionArgs --only-show-errors

Write-Host "== image published: $ImageDefinition $ImageVersion" -ForegroundColor Green
if (-not $KeepBuildVm) {
    Write-Host "== deleting build RG" -ForegroundColor Cyan
    az group delete --name $ResourceGroup --yes --no-wait --only-show-errors
}
