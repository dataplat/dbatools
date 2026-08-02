#Requires -Version 7.0
<#
.SYNOPSIS
    Packages and deploys the fleet controller Function App.

.DESCRIPTION
    Stages controller/ into a ready-to-run .zip and pushes it with one deploy, which is
    the only deployment technology a Flex Consumption plan supports.

    Staging is not a straight copy. runner-policy.ps1, bootstrap-runner.ps1 and
    fleet-config.psd1 live at .github/runners/ in the repo, where the mirror tests and
    runner-scale-up.yml expect them, but FleetCore resolves all three from its own
    $PSScriptRoot. They are copied into Modules/FleetCore/ here so the module stays
    self-contained at runtime and the repo keeps one copy of each file.

.PARAMETER DryRun
    Sets the DRY_RUN app setting as part of the deployment. Left alone when not passed,
    so a routine redeploy cannot silently arm a shadowing controller.

.EXAMPLE
    PS C:\> ./deploy-controller.ps1

    Packages and deploys, leaving DRY_RUN as it is.

.EXAMPLE
    PS C:\> ./deploy-controller.ps1 -DryRun false

    Deploys and takes the controller live.

.NOTES
    Author: the dbatools team + Claude
#>
[CmdletBinding()]
param(
    [string]$SubscriptionId = "fda988ac-f308-440e-ad06-ad1c3f026218",
    [string]$ResourceGroup = "dbatools-ci",
    [string]$FunctionAppName = "dbatools-fleet-controller",
    [ValidateSet("true", "false")]
    [string]$DryRun
)

$ErrorActionPreference = "Stop"

$runnerRoot = $PSScriptRoot
$controllerRoot = Join-Path -Path $runnerRoot -ChildPath "controller"
if (-not (Test-Path -Path $controllerRoot)) {
    throw "No controller directory beside this script at $controllerRoot"
}

$staging = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "dbatools-fleet-controller-package"
if (Test-Path -Path $staging) {
    Remove-Item -Path $staging -Recurse -Force
}
$null = New-Item -Path $staging -ItemType Directory

$splatCopy = @{
    Path        = (Join-Path -Path $controllerRoot -ChildPath "*")
    Destination = $staging
    Recurse     = $true
    Force       = $true
}
Copy-Item @splatCopy

$fleetCoreDir = Join-Path -Path $staging -ChildPath "Modules/FleetCore"
$bundled = @(
    "runner-policy.ps1",
    "bootstrap-runner.ps1"
)
foreach ($fileName in $bundled) {
    $source = Join-Path -Path $runnerRoot -ChildPath $fileName
    if (-not (Test-Path -Path $source)) {
        throw "Cannot bundle $fileName; expected it at $source"
    }
    Copy-Item -Path $source -Destination $fleetCoreDir -Force
}
Move-Item -Path (Join-Path -Path $staging -ChildPath "fleet-config.psd1") -Destination $fleetCoreDir -Force

$expected = @(
    "host.json",
    "profile.ps1",
    "GithubWebhook/function.json",
    "GithubWebhook/run.ps1",
    "ReconcileQueue/function.json",
    "ReconcileQueue/run.ps1",
    "SafetyTick/function.json",
    "SafetyTick/run.ps1",
    "SpendReport/function.json",
    "SpendReport/run.ps1",
    "Modules/GitHubAppAuth/GitHubAppAuth.psm1",
    "Modules/FleetCore/FleetCore.psm1",
    "Modules/FleetCore/fleet-config.psd1",
    "Modules/FleetCore/runner-policy.ps1",
    "Modules/FleetCore/bootstrap-runner.ps1"
)
$missing = @($expected | Where-Object { -not (Test-Path -Path (Join-Path -Path $staging -ChildPath $PSItem)) })
if ($missing) {
    throw "Package is incomplete: $($missing -join ", ")"
}

$zipPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "dbatools-fleet-controller.zip"
if (Test-Path -Path $zipPath) {
    Remove-Item -Path $zipPath -Force
}
# Not Compress-Archive: it has written Windows path separators into entry names, and a
# Linux Functions host then unpacks the whole tree as flat files with backslashes in
# their names. ZipFile always writes forward slashes.
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($staging, $zipPath)
Write-Host "packaged $([math]::Round((Get-Item -Path $zipPath).Length / 1KB)) KB from $staging"

if ($PSBoundParameters.ContainsKey("DryRun")) {
    $splatDryRun = @(
        "functionapp", "config", "appsettings", "set",
        "--subscription", $SubscriptionId,
        "--resource-group", $ResourceGroup,
        "--name", $FunctionAppName,
        "--settings", "DRY_RUN=$DryRun",
        "--only-show-errors", "--output", "none"
    )
    az @splatDryRun
    if ($LASTEXITCODE -ne 0) {
        throw "failed to set DRY_RUN=$DryRun"
    }
    Write-Host "DRY_RUN=$DryRun"
}

$splatDeploy = @(
    "functionapp", "deployment", "source", "config-zip",
    "--subscription", $SubscriptionId,
    "--resource-group", $ResourceGroup,
    "--name", $FunctionAppName,
    "--src", $zipPath,
    "--only-show-errors", "--output", "none"
)
az @splatDeploy
if ($LASTEXITCODE -ne 0) {
    throw "one deploy failed for $FunctionAppName"
}
Write-Host "deployed $FunctionAppName"

$splatHostName = @(
    "functionapp", "show",
    "--subscription", $SubscriptionId,
    "--resource-group", $ResourceGroup,
    "--name", $FunctionAppName,
    "--query", "properties.defaultHostName || defaultHostName",
    "--output", "tsv", "--only-show-errors"
)
$hostName = az @splatHostName

# Trigger sync is asynchronous, so the webhook function may not be listed for a few
# seconds after the deploy returns.
$webhookKey = $null
foreach ($attempt in 1..6) {
    $splatKey = @(
        "functionapp", "function", "keys", "list",
        "--subscription", $SubscriptionId,
        "--resource-group", $ResourceGroup,
        "--name", $FunctionAppName,
        "--function-name", "GithubWebhook",
        "--query", "default",
        "--output", "tsv", "--only-show-errors"
    )
    $webhookKey = az @splatKey 2>$null
    if ($LASTEXITCODE -eq 0 -and $webhookKey) {
        break
    }
    Start-Sleep -Seconds 10
}

if ($webhookKey) {
    Write-Host ""
    Write-Host "Webhook URL for the GitHub App:"
    Write-Host "  https://$hostName/api/github-webhook?code=$webhookKey"
} else {
    Write-Warning "The GithubWebhook function is not listed yet. Once it is, read its URL with: az functionapp function keys list --subscription $SubscriptionId --resource-group $ResourceGroup --name $FunctionAppName --function-name GithubWebhook --query default --output tsv"
}
