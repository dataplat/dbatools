<#
.SYNOPSIS
    Provisions (idempotently) the Azure-native fleet controller that replaces the
    GitHub-Actions-hosted reconcile workflow.

.DESCRIPTION
    Creates everything the Function App controller needs, safe to rerun any time:

      - Storage account dbatoolsfleetsa (Functions host storage + the fleet-nudge queue)
      - Log Analytics workspace + Application Insights (structured pass logs, alerts)
      - Key Vault dbatools-fleet-kv (RBAC mode) holding the GitHub App private key and
        the webhook secret -- the two values the controller cannot run without
      - Function App dbatools-fleet-controller on Flex Consumption (FC1, PowerShell 7.6)
        with a system-assigned identity, capped at one instance so reconcile passes
        serialize the way the old runner-fleet concurrency group did
      - Role assignments for that identity: dbatools-ci-operator on the RG (the same
        least-privilege role the OIDC app and the janitor already hold) and Key Vault
        Secrets User on the vault
      - App settings, including Key Vault references once the secrets exist

    Order of operations: run this first so the Function App exists, hand the operator the
    GitHub App checklist in .github/runners/README.md, then rerun with -GitHubAppId and
    -GitHubInstallationId to finish the wiring. Both runs are safe.

    This script touches only the NEW controller resources. It never modifies the VMSS,
    the janitor, the OIDC app, or anything the existing fleet path depends on.

.PARAMETER GitHubAppId
    App ID of the dbatools-fleet-controller GitHub App. Supply on the second run.

.PARAMETER GitHubInstallationId
    Installation ID of that App on dataplat/dbatools. Supply on the second run.

.PARAMETER DryRun
    Value for the controller's DRY_RUN app setting. Defaults to true: the controller
    computes and logs every decision but performs no Azure or GitHub mutation.

.NOTES
    Author: the dbatools team + Claude
    Requires: az CLI logged in with Owner rights on the subscription.

.EXAMPLE
    ./.github/runners/controller-infra.ps1

    First run. Creates all resources; the GitHub App can then point at the webhook.

.EXAMPLE
    ./.github/runners/controller-infra.ps1 -GitHubAppId 1234567 -GitHubInstallationId 87654321

    Second run, after the App exists and its secrets are in Key Vault. Completes the
    app settings so the controller can authenticate.
#>
param(
    [string]$SubscriptionId = "fda988ac-f308-440e-ad06-ad1c3f026218",
    [string]$ResourceGroup = "dbatools-ci",
    [string]$Location = "eastus",
    [string]$FunctionAppName = "dbatools-fleet-controller",
    [string]$StorageAccount = "dbatoolsfleetsa",
    [string]$KeyVaultName = "dbatools-fleet-kv",
    [string]$InsightsName = "dbatools-fleet-insights",
    [string]$WorkspaceName = "dbatools-fleet-logs",
    [string]$QueueName = "fleet-nudge",
    [string]$Repo = "dataplat/dbatools",
    [string]$VmssName = "dbatools-runners",
    [string]$GitHubAppId,
    [string]$GitHubInstallationId,
    [ValidateSet("true", "false")]
    [string]$DryRun = "true"
)

$ErrorActionPreference = "Stop"
# Built-in role: Key Vault Secrets User. Referenced by ID because the display name is
# localized in some tenants and az matches it literally.
$keyVaultSecretsUserRoleId = "4633458b-17de-408a-b874-0445c86b69e6"
$keyVaultSecretsOfficerRoleId = "b86a8fe4-44ce-4948-aee5-eccb2c155cd7"
$operatorRoleId = "c1ff6fe2-a25f-415b-bfb8-852a9c81cbfc"
$rgScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup"

Write-Host "== storage account $StorageAccount" -ForegroundColor Cyan
$storageExists = az storage account show --name $StorageAccount --resource-group $ResourceGroup --subscription $SubscriptionId --only-show-errors 2>$null
if (-not $storageExists) {
    $splatStorageArgs = @(
        "storage", "account", "create",
        "--name", $StorageAccount,
        "--resource-group", $ResourceGroup,
        "--location", $Location,
        "--sku", "Standard_LRS",
        "--min-tls-version", "TLS1_2",
        "--allow-blob-public-access", "false",
        "--subscription", $SubscriptionId,
        "--output", "none"
    )
    az @splatStorageArgs --only-show-errors
}

Write-Host "== queue $QueueName" -ForegroundColor Cyan
$splatKeyArgs = @(
    "storage", "account", "keys", "list",
    "--account-name", $StorageAccount,
    "--resource-group", $ResourceGroup,
    "--subscription", $SubscriptionId,
    "--query", "[0].value",
    "--output", "tsv"
)
$storageKey = az @splatKeyArgs --only-show-errors
$splatQueueArgs = @(
    "storage", "queue", "create",
    "--name", $QueueName,
    "--account-name", $StorageAccount,
    "--account-key", $storageKey,
    "--output", "none"
)
az @splatQueueArgs --only-show-errors

Write-Host "== Log Analytics workspace $WorkspaceName" -ForegroundColor Cyan
$splatWorkspaceArgs = @(
    "monitor", "log-analytics", "workspace", "create",
    "--resource-group", $ResourceGroup,
    "--workspace-name", $WorkspaceName,
    "--location", $Location,
    "--subscription", $SubscriptionId,
    "--query", "id",
    "--output", "tsv"
)
$workspaceId = az @splatWorkspaceArgs --only-show-errors

Write-Host "== Application Insights $InsightsName" -ForegroundColor Cyan
# Deliberately ARM rather than `az monitor app-insights component create`: that command
# lives in the application-insights CLI extension, which is not installed by default and
# was found corrupt on a maintainer workstation. The PUT is idempotent.
$insightsUri = "https://management.azure.com$rgScope/providers/Microsoft.Insights/components/$InsightsName" + "?api-version=2020-02-02"
$insightsJson = @"
{
  "location": "$Location",
  "kind": "web",
  "properties": {
    "Application_Type": "web",
    "WorkspaceResourceId": "$workspaceId",
    "IngestionMode": "LogAnalytics"
  }
}
"@
$insightsPath = Join-Path ([System.IO.Path]::GetTempPath()) "dbatools-fleet-insights.json"
Set-Content -Path $insightsPath -Value $insightsJson
$null = az rest --method put --uri $insightsUri --body "@$insightsPath" --only-show-errors
Remove-Item -Path $insightsPath -Force
$splatConnectionArgs = @(
    "rest", "--method", "get",
    "--uri", $insightsUri,
    "--query", "properties.ConnectionString",
    "--output", "tsv"
)
$insightsConnection = az @splatConnectionArgs --only-show-errors
if (-not $insightsConnection) {
    throw "Application Insights $InsightsName has no connection string"
}

Write-Host "== Key Vault $KeyVaultName (RBAC authorization)" -ForegroundColor Cyan
$vaultExists = az keyvault show --name $KeyVaultName --resource-group $ResourceGroup --subscription $SubscriptionId --only-show-errors 2>$null
if (-not $vaultExists) {
    $splatVaultArgs = @(
        "keyvault", "create",
        "--name", $KeyVaultName,
        "--resource-group", $ResourceGroup,
        "--location", $Location,
        "--enable-rbac-authorization", "true",
        "--subscription", $SubscriptionId,
        "--output", "none"
    )
    az @splatVaultArgs --only-show-errors
}

Write-Host "== Function App $FunctionAppName (Flex Consumption, PowerShell 7.6)" -ForegroundColor Cyan
$functionExists = az functionapp show --name $FunctionAppName --resource-group $ResourceGroup --subscription $SubscriptionId --only-show-errors 2>$null
if (-not $functionExists) {
    # maximum-instance-count 1 is the serialization guarantee. It replaces the
    # runner-fleet concurrency group, so two reconcile passes can never race.
    $splatFunctionArgs = @(
        "functionapp", "create",
        "--name", $FunctionAppName,
        "--resource-group", $ResourceGroup,
        "--flexconsumption-location", $Location,
        "--runtime", "powershell",
        "--runtime-version", "7.6",
        "--instance-memory", "2048",
        "--maximum-instance-count", "1",
        "--storage-account", $StorageAccount,
        "--disable-app-insights", "true",
        "--assign-identity", "[system]",
        "--subscription", $SubscriptionId,
        "--output", "none"
    )
    az @splatFunctionArgs --only-show-errors
}

$splatIdentityArgs = @(
    "functionapp", "identity", "show",
    "--name", $FunctionAppName,
    "--resource-group", $ResourceGroup,
    "--subscription", $SubscriptionId,
    "--query", "principalId",
    "--output", "tsv"
)
$principalId = az @splatIdentityArgs --only-show-errors
if (-not $principalId) {
    throw "Function App $FunctionAppName has no system-assigned identity"
}
Write-Host "   identity principalId = $principalId"

Write-Host "== role assignments" -ForegroundColor Cyan
$vaultScope = "$rgScope/providers/Microsoft.KeyVault/vaults/$KeyVaultName"
$assignments = @(
    @{
        Principal = $principalId
        Type      = "ServicePrincipal"
        Role      = $operatorRoleId
        Scope     = $rgScope
        Label     = "controller identity: dbatools-ci-operator on $ResourceGroup"
    },
    @{
        Principal = $principalId
        Type      = "ServicePrincipal"
        Role      = $keyVaultSecretsUserRoleId
        Scope     = $vaultScope
        Label     = "controller identity: Key Vault Secrets User on $KeyVaultName"
    }
)

# The vault is RBAC-authorized, and subscription Owner carries no data-plane rights, so
# the human who has to put the App private key in the vault needs an explicit grant.
#
# Graph is queried with a token minted for THIS subscription rather than through
# `az ad signed-in-user show`. That command follows the CLI's default subscription, and
# on a workstation whose default lives in another tenant it returns a guest object ID
# that this directory has never heard of -- the role assignment then fails with
# PrincipalNotFound naming an ID that looks perfectly valid.
$graphToken = az account get-access-token --subscription $SubscriptionId --resource "https://graph.microsoft.com" --query accessToken --output tsv --only-show-errors
$signedInUserId = $null
if ($graphToken) {
    $splatGraph = @{
        Uri        = "https://graph.microsoft.com/v1.0/me"
        Headers    = @{ Authorization = "Bearer $graphToken" }
        TimeoutSec = 30
    }
    $signedInUserId = (Invoke-RestMethod @splatGraph).id
}
if ($signedInUserId) {
    $assignments += @{
        Principal = $signedInUserId
        Type      = "User"
        Role      = $keyVaultSecretsOfficerRoleId
        Scope     = $vaultScope
        Label     = "operator: Key Vault Secrets Officer on $KeyVaultName"
    }
} else {
    Write-Warning "could not resolve the signed-in user; grant yourself Key Vault Secrets Officer on $KeyVaultName before setting secrets"
}

foreach ($assignment in $assignments) {
    # Filtered client-side rather than with --assignee: that flag makes az resolve the
    # principal through Graph, which fails for a managed identity the CLI's default
    # tenant cannot see even though the assignment itself is pure ARM.
    $splatExistingArgs = @(
        "role", "assignment", "list",
        "--scope", $assignment.Scope,
        "--subscription", $SubscriptionId,
        "--query", "[].{principal:principalId,role:roleDefinitionId}",
        "--output", "tsv"
    )
    $existingRows = @(az @splatExistingArgs --only-show-errors)
    $existing = @($existingRows | Where-Object { $PSItem -match [regex]::Escape($assignment.Principal) -and $PSItem -match [regex]::Escape($assignment.Role) })
    if ($existing) {
        Write-Host "   have $($assignment.Label)"
        continue
    }
    $splatAssignArgs = @(
        "role", "assignment", "create",
        "--assignee-object-id", $assignment.Principal,
        "--assignee-principal-type", $assignment.Type,
        "--role", $assignment.Role,
        "--scope", $assignment.Scope,
        "--subscription", $SubscriptionId,
        "--output", "none"
    )
    az @splatAssignArgs --only-show-errors
    if ($LASTEXITCODE -ne 0) {
        throw "role assignment failed -- $($assignment.Label)"
    }
    Write-Host "   added $($assignment.Label)"
}

Write-Host "== app settings" -ForegroundColor Cyan
# Deliberately no pool policy numbers here. Those live in controller/fleet-config.psd1,
# where the mirror tests can read them; an app setting of the same name overrides one at
# runtime and is the emergency lever, so setting any of them up front would quietly
# disconnect the committed file from the running fleet.
$settings = @(
    "REPO=$Repo",
    "RG=$ResourceGroup",
    "VMSS=$VmssName",
    "SUBSCRIPTION_ID=$SubscriptionId",
    "FLEET_QUEUE=$QueueName",
    "DRY_RUN=$DryRun",
    "APPLICATIONINSIGHTS_CONNECTION_STRING=$insightsConnection",
    # A reconcile pass runs for minutes. The HTTP webhook must still answer inside
    # GitHub's 10 second delivery timeout while one is running, so worker concurrency
    # stays above one even though the instance count does not.
    "PSWorkerInProcConcurrencyUpperBound=10"
)
if ($GitHubAppId) {
    $settings += "GITHUB_APP_ID=$GitHubAppId"
}
if ($GitHubInstallationId) {
    $settings += "GITHUB_INSTALLATION_ID=$GitHubInstallationId"
}

# Key Vault references are wired only once the secrets exist. Pointing a reference at a
# missing secret leaves the literal @Microsoft.KeyVault(...) string in the environment,
# which fails HMAC validation silently rather than loudly.
$settingBySecret = @{
    "github-app-private-key" = "GITHUB_APP_PRIVATE_KEY"
    "github-webhook-secret"  = "GITHUB_WEBHOOK_SECRET"
}
foreach ($secretName in @("github-app-private-key", "github-webhook-secret")) {
    $splatSecretArgs = @(
        "keyvault", "secret", "show",
        "--vault-name", $KeyVaultName,
        "--name", $secretName,
        "--subscription", $SubscriptionId,
        "--query", "id",
        "--output", "tsv"
    )
    $secretId = az @splatSecretArgs --only-show-errors 2>$null
    if (-not $secretId) {
        Write-Warning "secret $secretName is not in $KeyVaultName yet; $($settingBySecret[$secretName]) left unset. Rerun after the GitHub App exists."
        continue
    }
    # Version-less SecretUri so a rotated secret is picked up without a redeploy.
    $secretUri = $secretId -replace "/[^/]+$", ""
    $settings += "$($settingBySecret[$secretName])=@Microsoft.KeyVault(SecretUri=$secretUri/)"
}

$splatSettingsArgs = @(
    "functionapp", "config", "appsettings", "set",
    "--name", $FunctionAppName,
    "--resource-group", $ResourceGroup,
    "--subscription", $SubscriptionId,
    "--settings"
) + $settings + @("--output", "none")
az @splatSettingsArgs --only-show-errors

$splatHostArgs = @(
    "functionapp", "show",
    "--name", $FunctionAppName,
    "--resource-group", $ResourceGroup,
    "--subscription", $SubscriptionId,
    # az 2.80 returns the ARM-shaped body for Flex apps, older builds flatten it
    "--query", "properties.defaultHostName || defaultHostName",
    "--output", "tsv"
)
$hostName = az @splatHostArgs --only-show-errors

Write-Host ""
Write-Host "== done" -ForegroundColor Green
Write-Host "Function App : https://$hostName"
Write-Host "Identity     : $principalId"
Write-Host "Key Vault    : $KeyVaultName"
Write-Host "Nudge queue  : $QueueName on $StorageAccount"
Write-Host ""
Write-Host "Next: pwsh .github/runners/deploy-controller.ps1"
Write-Host "Then: pwsh .github/runners/deploy-controller.ps1 -ShowWebhookUrl  (the URL the GitHub App posts to)"
