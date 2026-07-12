<#
.SYNOPSIS
    Provisions (idempotently) the Azure fleet infrastructure for self-hosted CI runners.

.DESCRIPTION
    Creates everything the runner fleet needs, safe to rerun any time:

      - Resource group dbatools-ci (eastus)
      - VNet + subnet with a default-deny-inbound NSG (runners only need outbound)
      - VMSS dbatools-runners: Flexible orchestration, D4ds_v5, ephemeral OS disk on
        the local SSD (zero disk cost, factory-fresh on every reimage), instance-level
        public IPs (outbound to GitHub), capacity 0 -- the scale-up/reconcile workflows
        own capacity from then on
      - Entra app dbatools-ci-github + GitHub OIDC federated credential for the default
        branch (no client secrets anywhere) + least-privilege custom role on the RG,
        Reader on the image gallery RG, Cost Management Reader for spend reports
      - Monthly budget on the RG with 50/80/100 percent email alerts

    GitHub-side configuration (repo variables, CI_RUNNER_PAT secret) is documented in
    .github/runners/README.md -- this script touches only Azure.

.PARAMETER ImageId
    Resource ID of the gallery image version (or image definition for latest) the VMSS
    boots from. Omit together with -SkipVmss before the modern image exists.

.NOTES
    Author: the dbatools team + Claude
    Requires: az CLI logged in with Owner rights on the subscription.

.EXAMPLE
    ./.github/runners/infra.ps1 -SkipVmss -BudgetEmail clemaire@gmail.com

.EXAMPLE
    ./.github/runners/infra.ps1 -ImageId "/subscriptions/.../galleries/dbatoolsGallery/images/dbatools-modern-image" -BudgetEmail clemaire@gmail.com
#>
param(
    [string]$ResourceGroup = "dbatools-ci",
    [string]$Location = "eastus",
    [string]$VmssName = "dbatools-runners",
    [string]$VnetName = "dbatools-ci-vnet",
    [string]$SubnetName = "runners",
    [string]$NsgName = "dbatools-ci-nsg",
    [string]$VmSku = "Standard_D4ds_v5",
    [int]$MaxInstances = 10,
    [string]$AppName = "dbatools-ci-github",
    [string]$Repo = "dataplat/dbatools",
    [string]$DefaultBranch = "development",
    [string]$GalleryResourceGroup = "DBATOOLS-CI-IMAGES",
    [string]$ImageId,
    [int]$BudgetAmount = 600,
    [string]$BudgetEmail = "clemaire@gmail.com",
    [switch]$SkipVmss
)

$ErrorActionPreference = "Stop"
$subscriptionId = az account show --query id --output tsv --only-show-errors
$tenantId = az account show --query tenantId --output tsv --only-show-errors

Write-Host "== resource group $ResourceGroup" -ForegroundColor Cyan
$null = az group create --name $ResourceGroup --location $Location --tags project=dbatools purpose=ci-runners --output none --only-show-errors

Write-Host "== NSG $NsgName (default deny inbound, no allow rules)" -ForegroundColor Cyan
$nsgExists = az network nsg show --resource-group $ResourceGroup --name $NsgName --only-show-errors 2>$null
if (-not $nsgExists) {
    $null = az network nsg create --resource-group $ResourceGroup --name $NsgName --output none --only-show-errors
}

Write-Host "== VNet $VnetName / subnet $SubnetName" -ForegroundColor Cyan
$vnetExists = az network vnet show --resource-group $ResourceGroup --name $VnetName --only-show-errors 2>$null
if (-not $vnetExists) {
    $splatVnetArgs = @(
        "network", "vnet", "create",
        "--resource-group", $ResourceGroup,
        "--name", $VnetName,
        "--address-prefixes", "10.10.0.0/16",
        "--subnet-name", $SubnetName,
        "--subnet-prefixes", "10.10.0.0/24",
        "--network-security-group", $NsgName,
        "--output", "none"
    )
    az @splatVnetArgs --only-show-errors
}

if (-not $SkipVmss) {
    if (-not $ImageId) {
        throw "provide -ImageId (gallery image resource id) or use -SkipVmss"
    }
    Write-Host "== VMSS $VmssName (Flexible, capacity 0, ephemeral OS)" -ForegroundColor Cyan
    $vmssExists = az vmss show --resource-group $ResourceGroup --name $VmssName --only-show-errors 2>$null
    if (-not $vmssExists) {
        $password = "Db" + (-join ((65..90) + (97..122) + (48..57) | Get-Random -Count 16 | ForEach-Object { [char]$_ })) + "!3z"
        $splatVmssArgs = @(
            "vmss", "create",
            "--resource-group", $ResourceGroup,
            "--name", $VmssName,
            "--orchestration-mode", "Flexible",
            "--platform-fault-domain-count", "1",
            "--image", $ImageId,
            "--vm-sku", $VmSku,
            "--instance-count", "0",
            "--admin-username", "dbatools",
            "--admin-password", $password,
            "--vnet-name", $VnetName,
            "--subnet", $SubnetName,
            "--public-ip-per-vm",
            "--load-balancer", "",
            "--ephemeral-os-disk", "true",
            "--ephemeral-os-disk-placement", "ResourceDisk",
            "--os-disk-caching", "ReadOnly",
            "--output", "none"
        )
        az @splatVmssArgs --only-show-errors
    }
}

Write-Host "== Entra app $AppName + OIDC federated credential" -ForegroundColor Cyan
$appId = az ad app list --display-name $AppName --query "[0].appId" --output tsv --only-show-errors
if (-not $appId) {
    $appId = az ad app create --display-name $AppName --query appId --output tsv --only-show-errors
}
$spId = az ad sp show --id $appId --query id --output tsv --only-show-errors 2>$null
if (-not $spId) {
    $spId = az ad sp create --id $appId --query id --output tsv --only-show-errors
}
$fedName = "github-$($DefaultBranch)"
$fedNames = az ad app federated-credential list --id $appId --query "[].name" --output tsv --only-show-errors
if ($fedNames -notcontains $fedName) {
    $fedJson = @"
{
  "name": "$fedName",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:$Repo`:ref:refs/heads/$DefaultBranch",
  "audiences": ["api://AzureADTokenExchange"]
}
"@
    $fedPath = Join-Path $env:TEMP "dbatools-fed.json"
    Set-Content -Path $fedPath -Value $fedJson
    $null = az ad app federated-credential create --id $appId --parameters "@$fedPath" --output none --only-show-errors
    Remove-Item -Path $fedPath -Force
}

Write-Host "== custom role dbatools-ci-operator" -ForegroundColor Cyan
$roleName = "dbatools-ci-operator"
$roleExists = az role definition list --name $roleName --query "[0].roleName" --output tsv --only-show-errors
if (-not $roleExists) {
    $roleJson = @"
{
  "Name": "$roleName",
  "Description": "Scale and manage dbatools CI runner VMs: capacity, instance lifecycle, run-command.",
  "Actions": [
    "Microsoft.Compute/virtualMachineScaleSets/read",
    "Microsoft.Compute/virtualMachineScaleSets/write",
    "Microsoft.Compute/virtualMachineScaleSets/scale/action",
    "Microsoft.Compute/virtualMachineScaleSets/virtualMachines/read",
    "Microsoft.Compute/virtualMachineScaleSets/virtualMachines/write",
    "Microsoft.Compute/virtualMachineScaleSets/virtualMachines/delete",
    "Microsoft.Compute/virtualMachines/read",
    "Microsoft.Compute/virtualMachines/write",
    "Microsoft.Compute/virtualMachines/delete",
    "Microsoft.Compute/virtualMachines/start/action",
    "Microsoft.Compute/virtualMachines/restart/action",
    "Microsoft.Compute/virtualMachines/deallocate/action",
    "Microsoft.Compute/virtualMachines/runCommand/action",
    "Microsoft.Compute/virtualMachines/runCommands/read",
    "Microsoft.Compute/virtualMachines/runCommands/write",
    "Microsoft.Compute/virtualMachines/runCommands/delete",
    "Microsoft.Compute/virtualMachines/instanceView/read",
    "Microsoft.Compute/disks/read",
    "Microsoft.Compute/disks/write",
    "Microsoft.Compute/disks/delete",
    "Microsoft.Network/networkInterfaces/read",
    "Microsoft.Network/networkInterfaces/write",
    "Microsoft.Network/networkInterfaces/delete",
    "Microsoft.Network/networkInterfaces/join/action",
    "Microsoft.Network/publicIPAddresses/read",
    "Microsoft.Network/publicIPAddresses/write",
    "Microsoft.Network/publicIPAddresses/delete",
    "Microsoft.Network/publicIPAddresses/join/action",
    "Microsoft.Network/virtualNetworks/read",
    "Microsoft.Network/virtualNetworks/subnets/read",
    "Microsoft.Network/virtualNetworks/subnets/join/action",
    "Microsoft.Network/networkSecurityGroups/read",
    "Microsoft.Network/networkSecurityGroups/join/action",
    "Microsoft.Resources/subscriptions/resourceGroups/read",
    "Microsoft.Resources/deployments/read",
    "Microsoft.Resources/deployments/write",
    "Microsoft.Resources/deployments/operationStatuses/read"
  ],
  "AssignableScopes": ["/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup"]
}
"@
    $rolePath = Join-Path $env:TEMP "dbatools-role.json"
    Set-Content -Path $rolePath -Value $roleJson
    $null = az role definition create --role-definition "@$rolePath" --only-show-errors
    Remove-Item -Path $rolePath -Force
    Start-Sleep -Seconds 15
}

Write-Host "== role assignments" -ForegroundColor Cyan
$rgScope = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup"
$galleryScope = "/subscriptions/$subscriptionId/resourceGroups/$GalleryResourceGroup"
$assignments = @(
    [PSCustomObject]@{ Role = $roleName; Scope = $rgScope }
    [PSCustomObject]@{ Role = "Reader"; Scope = $galleryScope }
    [PSCustomObject]@{ Role = "Cost Management Reader"; Scope = "/subscriptions/$subscriptionId" }
)
foreach ($assignment in $assignments) {
    $existing = az role assignment list --assignee $appId --role $assignment.Role --scope $assignment.Scope --query "[0].id" --output tsv --only-show-errors
    if (-not $existing) {
        $null = az role assignment create --assignee-object-id $spId --assignee-principal-type ServicePrincipal --role $assignment.Role --scope $assignment.Scope --output none --only-show-errors
    }
}

Write-Host "== monthly budget $BudgetAmount on $ResourceGroup" -ForegroundColor Cyan
$startDate = (Get-Date -Day 1).ToString("yyyy-MM-01")
$endDate = (Get-Date -Day 1).AddYears(5).ToString("yyyy-MM-01")
$budgetJson = @"
{
  "properties": {
    "category": "Cost",
    "amount": $BudgetAmount,
    "timeGrain": "Monthly",
    "timePeriod": { "startDate": "$startDate", "endDate": "$endDate" },
    "notifications": {
      "actual50": { "enabled": true, "operator": "GreaterThan", "threshold": 50, "contactEmails": ["$BudgetEmail"], "thresholdType": "Actual" },
      "actual80": { "enabled": true, "operator": "GreaterThan", "threshold": 80, "contactEmails": ["$BudgetEmail"], "thresholdType": "Actual" },
      "actual100": { "enabled": true, "operator": "GreaterThan", "threshold": 100, "contactEmails": ["$BudgetEmail"], "thresholdType": "Actual" }
    }
  }
}
"@
$budgetPath = Join-Path $env:TEMP "dbatools-budget.json"
Set-Content -Path $budgetPath -Value $budgetJson
$budgetUri = "https://management.azure.com$rgScope/providers/Microsoft.Consumption/budgets/dbatools-ci-budget?api-version=2023-05-01"
$null = az rest --method put --uri $budgetUri --body "@$budgetPath" --only-show-errors
Remove-Item -Path $budgetPath -Force

Write-Host ""
Write-Host "== done. GitHub OIDC values for repo variables:" -ForegroundColor Green
Write-Host "AZURE_CLIENT_ID       = $appId"
Write-Host "AZURE_TENANT_ID       = $tenantId"
Write-Host "AZURE_SUBSCRIPTION_ID = $subscriptionId"
