#!/bin/bash
set -euo pipefail

VMSS_NAME="$1"
CAPACITY="$2"
RESOURCE_GROUP="$3"
CUSTOM_IMAGE_ID="$4"
GITHUB_ACTOR="$5"
BRANCH_NAME="$6"
GITHUB_REPOSITORY="$7"
BUILD_ID="$8"

echo "=== VMSS Creation Script ==="
echo "VMSS Name: $VMSS_NAME"
echo "Capacity: $CAPACITY"

# Check if VMSS exists
if az vmss show --resource-group "$RESOURCE_GROUP" --name "$VMSS_NAME" &>/dev/null; then
    echo "VMSS $VMSS_NAME already exists, scaling to $CAPACITY"
    az vmss scale `
        --resource-group "$RESOURCE_GROUP" `
        --name "$VMSS_NAME" `
        --new-capacity "$CAPACITY"
else
    echo "Creating new VMSS: $VMSS_NAME"

    # Create VMSS with system-assigned identity (more reliable)
    az vmss create `
        --resource-group "$RESOURCE_GROUP" `
        --name "$VMSS_NAME" `
        --image "$CUSTOM_IMAGE_ID" `
        --upgrade-policy-mode automatic `
        --admin-username runneradmin `
        --admin-password 'dbatools.I00' `
        --instance-count "$CAPACITY" `
        --vm-sku Standard_B4ms `
        --location eastus2 `
        --license-type Windows_Server `
        --orchestration-mode Uniform `
        --priority Regular `
        --ephemeral-os-disk true `
        --assign-identity `
        --tags `
            owner="$GITHUB_ACTOR" `
            branch="$BRANCH_NAME" `
            purpose='dbatools-ci' `
            build_id="$BUILD_ID" `
            created="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # Get system-assigned identity principal ID
    SYSTEM_PRINCIPAL_ID=$(az vmss show `
        --resource-group "$RESOURCE_GROUP" `
        --name "$VMSS_NAME" `
        --query "identity.principalId" `
        --output tsv)

    echo "System identity principal ID: $SYSTEM_PRINCIPAL_ID"

    # Assign Key Vault permissions to system identity
    az role assignment create `
        --role "Key Vault Secrets User" `
        --assignee "$SYSTEM_PRINCIPAL_ID" `
        --scope "/subscriptions/65a430fb-5a9a-49ff-969e-05d1beaa88fb/resourcegroups/dbatools-ci-runners/providers/Microsoft.KeyVault/vaults/dbatoolsci"

    # Wait for role assignment propagation
    echo "Waiting 30 seconds for role assignment propagation..."
    sleep 30
fi

# Add Custom Script Extension to run setup
echo "Adding Custom Script Extension..."
az vmss extension set `
    --resource-group "$RESOURCE_GROUP" `
    --vmss-name "$VMSS_NAME" `
    --name CustomScriptExtension `
    --publisher Microsoft.Compute `
    --version 1.10 `
    --protected-settings "{
        \"fileUris\": [\"https://raw.githubusercontent.com/dataplat/dbatools/vmss/.github/scripts/runner-setup.ps1\"],
        \"commandToExecute\": \"powershell -ExecutionPolicy Unrestricted -File runner-setup.ps1\",
        \"managedIdentity\": {},
        \"timestamp\": $(date +%s)
    }"

echo "=== VMSS Creation Completed ==="