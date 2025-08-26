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

# Function to retry Azure operations
retry_azure_op() {
    local cmd="$1"
    local max_attempts=3
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        echo "Attempt $attempt/$max_attempts: $cmd"
        if eval "$cmd"; then
            return 0
        fi

        if [ $attempt -lt $max_attempts ]; then
            echo "Operation failed, retrying in 10 seconds..."
            sleep 10
        fi
        ((attempt++))
    done

    echo "Operation failed after $max_attempts attempts"
    return 1
}

# Check if VMSS exists and handle coordination
VMSS_EXISTS=false
CURRENT_CAPACITY=0

if az vmss show --resource-group "$RESOURCE_GROUP" --name "$VMSS_NAME" &>/dev/null; then
    echo "VMSS $VMSS_NAME already exists"
    VMSS_EXISTS=true

    CURRENT_CAPACITY=$(az vmss show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VMSS_NAME" \
        --query "sku.capacity" \
        --output tsv)

    echo "Current capacity: $CURRENT_CAPACITY"

    # Check if another process is modifying this VMSS
    MODIFICATION_TAG=$(az vmss show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VMSS_NAME" \
        --query "tags.modifying_process" \
        --output tsv 2>/dev/null || echo "null")

    if [[ "$MODIFICATION_TAG" != "null" && "$MODIFICATION_TAG" != "" ]]; then
        TIMESTAMP=$(date +%s)
        TAG_TIMESTAMP=$(echo "$MODIFICATION_TAG" | cut -d':' -f2)
        TIME_DIFF=$((TIMESTAMP - TAG_TIMESTAMP))

        # If another process has been modifying for more than 10 minutes, assume it's stale
        if [ $TIME_DIFF -lt 600 ]; then
            echo "Another process is currently modifying this VMSS (started $(date -d @$TAG_TIMESTAMP))"
            echo "Waiting up to 5 minutes for it to complete..."

            for i in {1..30}; do
                sleep 10
                MODIFICATION_TAG=$(az vmss show \
                    --resource-group "$RESOURCE_GROUP" \
                    --name "$VMSS_NAME" \
                    --query "tags.modifying_process" \
                    --output tsv 2>/dev/null || echo "null")

                if [[ "$MODIFICATION_TAG" == "null" || "$MODIFICATION_TAG" == "" ]]; then
                    echo "Other process completed, proceeding..."
                    break
                fi

                if [ $i -eq 30 ]; then
                    echo "Timeout waiting for other process. Proceeding anyway (may be stale lock)."
                fi
            done
        else
            echo "Stale modification tag detected, proceeding..."
        fi
    fi
fi

# Set modification tag to coordinate with other processes
CURRENT_TIME=$(date +%s)
MODIFICATION_TAG="$BUILD_ID:$CURRENT_TIME"

echo "Setting modification lock tag: $MODIFICATION_TAG"

if [ "$VMSS_EXISTS" = true ]; then
    # Update existing VMSS with coordination tag
    retry_azure_op "az vmss update \
        --resource-group '$RESOURCE_GROUP' \
        --name '$VMSS_NAME' \
        --set tags.modifying_process='$MODIFICATION_TAG' \
        --set tags.last_modified='$(date -u +%Y-%m-%dT%H:%M:%SZ)' \
        --set tags.modified_by='$GITHUB_ACTOR'"

    if [[ "$CURRENT_CAPACITY" != "$CAPACITY" ]]; then
        echo "Scaling VMSS from $CURRENT_CAPACITY to $CAPACITY"
        retry_azure_op "az vmss scale \
            --resource-group '$RESOURCE_GROUP' \
            --name '$VMSS_NAME' \
            --new-capacity '$CAPACITY'"

        # Wait for scaling to complete
        echo "Waiting for scaling operation to complete..."
        for i in {1..30}; do
            ACTUAL_CAPACITY=$(az vmss show \
                --resource-group "$RESOURCE_GROUP" \
                --name "$VMSS_NAME" \
                --query "sku.capacity" \
                --output tsv)

            if [ "$ACTUAL_CAPACITY" -eq "$CAPACITY" ]; then
                echo "Scaling completed successfully"
                break
            fi

            echo "Current capacity: $ACTUAL_CAPACITY, target: $CAPACITY (attempt $i/30)"
            sleep 10
        done
    else
        echo "VMSS already at desired capacity ($CAPACITY)"
    fi

    echo "vmss-existed=true" >> "$GITHUB_OUTPUT"
else
    echo "Creating new VMSS: $VMSS_NAME"

    # Ensure Key Vault permissions are set BEFORE creating VMSS
    # Create a temporary managed identity to get the object ID format
    echo "Pre-configuring Key Vault access pattern..."

    retry_azure_op "az vmss create \
        --resource-group '$RESOURCE_GROUP' \
        --name '$VMSS_NAME' \
        --image '$CUSTOM_IMAGE_ID' \
        --upgrade-policy-mode automatic \
        --admin-username runneradmin \
        --admin-password 'dbatools.I00' \
        --instance-count '$CAPACITY' \
        --vm-sku Standard_B4ms \
        --location eastus2 \
        --license-type Windows_Server \
        --orchestration-mode Uniform \
        --priority Regular \
        --ephemeral-os-disk true \
        --assign-identity \
        --tags \
            owner='$GITHUB_ACTOR' \
            branch='$BRANCH_NAME' \
            purpose='dbatools-ci' \
            build_id='$BUILD_ID' \
            modifying_process='$MODIFICATION_TAG' \
            created='$(date -u +%Y-%m-%dT%H:%M:%SZ)'"

    # Grant Key Vault access immediately after creation
    echo "Setting up Key Vault permissions..."
    IDENTITY_PRINCIPAL_ID=$(retry_azure_op "az vmss show \
        --resource-group '$RESOURCE_GROUP' \
        --name '$VMSS_NAME' \
        --query 'identity.principalId' \
        --output tsv")

    if [[ -n "$IDENTITY_PRINCIPAL_ID" && "$IDENTITY_PRINCIPAL_ID" != "null" ]]; then
        KEYVAULT_NAME="dbatoolsci"
        retry_azure_op "az keyvault set-policy \
            --name '$KEYVAULT_NAME' \
            --object-id '$IDENTITY_PRINCIPAL_ID' \
            --secret-permissions get"
        echo "Key Vault permissions configured"
    else
        echo "WARNING: Could not retrieve managed identity, Key Vault access may not work"
    fi

    echo "vmss-existed=false" >> "$GITHUB_OUTPUT"
fi

# Remove modification lock tag
echo "Removing modification lock tag..."
retry_azure_op "az vmss update \
    --resource-group '$RESOURCE_GROUP' \
    --name '$VMSS_NAME' \
    --remove tags.modifying_process"

# Final verification
FINAL_CAPACITY=$(az vmss show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VMSS_NAME" \
    --query "sku.capacity" \
    --output tsv)

echo "=== VMSS Creation Completed ==="
echo "Final capacity: $FINAL_CAPACITY"
echo "VMSS is ready for use"