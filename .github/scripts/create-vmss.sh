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
echo "CUSTOM_IMAGE_ID=***MASKED***"
echo "GITHUB_ACTOR=$GITHUB_ACTOR"
echo "BRANCH_NAME=$BRANCH_NAME"
echo "GITHUB_REPOSITORY=$GITHUB_REPOSITORY"
echo "BUILD_ID=$BUILD_ID"

echo "=== VMSS Creation Script ==="
echo "VMSS Name: $VMSS_NAME"
echo "Capacity: $CAPACITY"
echo "Resource Group: $RESOURCE_GROUP"

# Function to mask sensitive data in output
mask_sensitive_output() {
    sed -E '
        s/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/***MASKED-ID***/gi
        s/"systemAssignedIdentity": "[^"]*"/"systemAssignedIdentity": "***MASKED-IDENTITY***"/g
        s/"principalId": "[^"]*"/"principalId": "***MASKED-PRINCIPAL***"/g
        s/"clientId": "[^"]*"/"clientId": "***MASKED-CLIENT***"/g
        s/--assignee [0-9a-f-]{36}/--assignee ***MASKED-ASSIGNEE***/g
        s/object id '\''[0-9a-f-]{36}'\''/object id '\''***MASKED-OBJECT***'\''/g
        s/The client '\''[0-9a-f-]{36}'\''/The client '\''***MASKED-CLIENT***'\''/g
    '
}

# Function to retry Azure operations with output masking
retry_azure_op() {
    local cmd="$1"
    local max_attempts=3
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        echo "Attempt $attempt/$max_attempts for Azure operation"
        if bash -c "$cmd" 2>&1 | mask_sensitive_output; then
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
            echo "Another process is currently modifying this VMSS"
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

echo "Setting modification lock tag"

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
        --assign-identity '/subscriptions/65a430fb-5a9a-49ff-969e-05d1beaa88fb/resourcegroups/dbatools-ci-runners/providers/Microsoft.ManagedIdentity/userAssignedIdentities/dbatools-keyvault-identity' \
        --tags \
            owner='$GITHUB_ACTOR' \
            branch='$BRANCH_NAME' \
            purpose='dbatools-ci' \
            build_id='$BUILD_ID' \
            modifying_process='$MODIFICATION_TAG' \
            created='$(date -u +%Y-%m-%dT%H:%M:%SZ)'"

    echo "vmss-existed=false" >> "$GITHUB_OUTPUT"
fi

echo "Key Vault access pre-configured via user-assigned managed identity"

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