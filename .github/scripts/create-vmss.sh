#!/bin/bash
set -e

VMSS_NAME="$1"
CAPACITY="$2"
RESOURCE_GROUP="$3"
CUSTOM_IMAGE_ID="$4"
GITHUB_ACTOR="$5"
BRANCH_NAME="$6"

echo "=== VMSS Creation Script ==="
echo "VMSS Name: $VMSS_NAME"
echo "Capacity: $CAPACITY"
echo "Resource Group: $RESOURCE_GROUP"
echo "Image: $CUSTOM_IMAGE_ID"

# Check if VMSS already exists
if az vmss show --resource-group "$RESOURCE_GROUP" --name "$VMSS_NAME" &>/dev/null; then
    echo "VMSS $VMSS_NAME already exists"

    # Get current capacity
    CURRENT_CAPACITY=$(az vmss show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VMSS_NAME" \
        --query "sku.capacity" \
        --output tsv)

    echo "Current capacity: $CURRENT_CAPACITY"

    if [[ "$CURRENT_CAPACITY" != "$CAPACITY" ]]; then
        echo "Scaling VMSS from $CURRENT_CAPACITY to $CAPACITY"
        az vmss scale \
            --resource-group "$RESOURCE_GROUP" \
            --name "$VMSS_NAME" \
            --new-capacity "$CAPACITY"
    else
        echo "VMSS already at desired capacity ($CAPACITY)"
    fi

    echo "vmss-existed=true" >> $GITHUB_OUTPUT
else
    echo "Creating new VMSS: $VMSS_NAME"

    az vmss create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VMSS_NAME" \
        --image "$CUSTOM_IMAGE_ID" \
        --upgrade-policy-mode automatic \
        --admin-username runneradmin \
        --admin-password "dbatools.I00" \
        --instance-count "$CAPACITY" \
        --vm-sku Standard_D4s_v3 \
        --location eastus2 \
        --license-type Windows_Server \
        --orchestration-mode Flexible \
        --priority Regular \
        --ephemeral-os-disk true \
        --tags \
            owner="$GITHUB_ACTOR" \
            branch="$BRANCH_NAME" \
            purpose="dbatools-ci" \
            created="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    echo "VMSS $VMSS_NAME created successfully"
    echo "vmss-existed=false" >> $GITHUB_OUTPUT
fi