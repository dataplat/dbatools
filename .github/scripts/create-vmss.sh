#!/bin/bash
set -euo pipefail

VMSS_NAME="$1"
CAPACITY="$2"
RESOURCE_GROUP="$3"
CUSTOM_IMAGE_ID="$4"
GITHUB_ACTOR="$5"
BRANCH_NAME="$6"
RUNNER_TOKEN="$7"
GITHUB_REPOSITORY="$8"
BUILD_ID="$9"

echo "[DEBUG] Arguments:"
echo "VMSS_NAME=$VMSS_NAME"
echo "CAPACITY=$CAPACITY"
echo "RESOURCE_GROUP=$RESOURCE_GROUP"
echo "CUSTOM_IMAGE_ID=$CUSTOM_IMAGE_ID"
echo "GITHUB_ACTOR=$GITHUB_ACTOR"
echo "BRANCH_NAME=$BRANCH_NAME"
echo "GITHUB_REPOSITORY=$GITHUB_REPOSITORY"
echo "BUILD_ID=$BUILD_ID"

echo "=== VMSS Creation Script ==="
echo "VMSS Name: $VMSS_NAME"
echo "Capacity: $CAPACITY"
echo "Resource Group: $RESOURCE_GROUP"
echo "Image: $CUSTOM_IMAGE_ID"

# Create protected settings with environment variables
PROTECTED_SETTINGS=$(cat <<EOF
{
  "environmentVariables": {
    "GITHUB_REPOSITORY": "$GITHUB_REPOSITORY",
    "RUNNER_TOKEN": "$RUNNER_TOKEN",
    "BUILD_ID": "$BUILD_ID",
    "VMSS_NAME": "$VMSS_NAME"
  }
}
EOF
)

# Check if VMSS exists
if az vmss show --resource-group "$RESOURCE_GROUP" --name "$VMSS_NAME" &>/dev/null; then
    echo "VMSS $VMSS_NAME already exists"

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

        echo "Setting environment variables for scaled instances..."
        az vmss extension set \
            --resource-group "$RESOURCE_GROUP" \
            --vmss-name "$VMSS_NAME" \
            --name CustomScriptExtension \
            --publisher Microsoft.Compute \
            --version 1.10 \
            --protected-settings "$PROTECTED_SETTINGS"
    else
        echo "VMSS already at desired capacity ($CAPACITY)"
    fi

    echo "vmss-existed=true" >> "$GITHUB_OUTPUT"
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
        --vm-sku Standard_B4ms \
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

    # Set environment variables for the newly created VMSS
    echo "Setting environment variables for new VMSS instances..."
    az vmss extension set \
        --resource-group "$RESOURCE_GROUP" \
        --vmss-name "$VMSS_NAME" \
        --name CustomScriptExtension \
        --publisher Microsoft.Compute \
        --version 1.10 \
        --protected-settings "$PROTECTED_SETTINGS"
fi