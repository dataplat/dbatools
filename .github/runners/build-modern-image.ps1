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

    The build VM needs 4 free cores in the region, the same Standard_DDSv5 family the CI
    fleet runs on. The build checks for them first and stops when the fleet holds them;
    rerun it once the fleet has scaled down. Every az call that changes something is checked,
    so a failed step stops the build instead of publishing nothing and deleting the VM.

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

function Assert-AzSuccess {
    # az is a native command: a failure sets $LASTEXITCODE and never trips
    # $ErrorActionPreference, so each call that changes something is checked by hand
    param(
        [Parameter(Mandatory)]
        [string]$Action
    )
    if ($LASTEXITCODE -ne 0) {
        throw "az could not $Action (exit code $LASTEXITCODE); see the az error above"
    }
}

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
        # Base64, because the JSON would not survive the trip as text: on Windows az is
        # az.cmd, and pwsh hands a batch file its arguments without escaping the inner
        # quotes, so the build VM received {instance:SQL2017,...} and step2 could not parse it
        $argsBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($ArgsJson))
        $launchArgs += "ArgsBase64=$argsBase64"
    }
    $null = az @launchArgs --only-show-errors
    Assert-AzSuccess -Action "launch $Step on $VmName"
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
    Write-Host "== checking cores in $Location" -ForegroundColor Cyan
    # Standard_D4ds_v5 counts against both the regional total and the DDSv5 family; the
    # CI fleet runs on the same size, so a busy fleet can hold every core
    $usage = az vm list-usage --location $Location --query "[?name.value=='cores' || name.value=='standardDDSv5Family'].{name:name.value, current:currentValue, limit:limit}" --output json --only-show-errors | ConvertFrom-Json
    Assert-AzSuccess -Action "read the core usage in $Location"
    foreach ($quota in $usage) {
        $freeCores = [int]$quota.limit - [int]$quota.current
        if ($freeCores -lt 4) {
            throw "$Location has $freeCores free $($quota.name) core(s) of $($quota.limit) and the build VM needs 4. The CI fleet holds them; rerun once it has scaled down."
        }
    }

    Write-Host "== creating build RG + VM" -ForegroundColor Cyan
    $null = az group create --name $ResourceGroup --location $Location --tags purpose=modern-image-build --output none --only-show-errors
    Assert-AzSuccess -Action "create resource group $ResourceGroup"
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
    Assert-AzSuccess -Action "create the build VM $VmName"
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
Assert-AzSuccess -Action "deallocate $VmName"
az vm generalize --resource-group $ResourceGroup --name $VmName --only-show-errors
Assert-AzSuccess -Action "generalize $VmName"

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
    Assert-AzSuccess -Action "create the image definition $ImageDefinition"
}

$vmId = az vm show --resource-group $ResourceGroup --name $VmName --query id --output tsv --only-show-errors
Assert-AzSuccess -Action "read the id of $VmName"
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
Assert-AzSuccess -Action "create image version $ImageVersion"
$versionState = az sig image-version show --resource-group $GalleryResourceGroup --gallery-name $GalleryName --gallery-image-definition $ImageDefinition --gallery-image-version $ImageVersion --query provisioningState --output tsv --only-show-errors
Assert-AzSuccess -Action "read image version $ImageVersion"
if ($versionState -ne "Succeeded") {
    throw "image version $ImageVersion is $versionState, not Succeeded; the build VM in $ResourceGroup is kept"
}

Write-Host "== image published: $ImageDefinition $ImageVersion" -ForegroundColor Green
if (-not $KeepBuildVm) {
    Write-Host "== deleting build RG" -ForegroundColor Cyan
    az group delete --name $ResourceGroup --yes --no-wait --only-show-errors
}
