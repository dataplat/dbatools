#!/bin/bash
set -e

VMSS_NAME="$1"
RESOURCE_GROUP="$2"
GITHUB_PAT="$3"
REPOSITORY="$4"
IS_PR_CLOSED="$5"

echo "=== VMSS Cleanup Script ==="
echo "VMSS Name: $VMSS_NAME"
echo "Resource Group: $RESOURCE_GROUP"
echo "Repository: $REPOSITORY"

# Set up gh CLI authentication
export GH_TOKEN="$GITHUB_PAT"

# Force delete all instances immediately
echo "Force deleting all VMSS instances immediately"
INSTANCE_IDS=$(az vmss list-instances \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VMSS_NAME" \
    --query "[].instanceId" \
    --output tsv 2>/dev/null || echo "")

if [[ -n "$INSTANCE_IDS" ]]; then
    echo "Found instances to delete: $INSTANCE_IDS"
    for instance_id in $INSTANCE_IDS; do
        echo "Force deleting instance: $instance_id"
        az vmss delete-instances \
            --resource-group "$RESOURCE_GROUP" \
            --name "$VMSS_NAME" \
            --instance-ids "$instance_id" \
            --no-wait || echo "Failed to delete instance $instance_id, continuing..."
    done
else
    echo "No instances found to delete"
fi

# Scale to 0 as backup
echo "Setting VMSS capacity to 0 as backup"
az vmss scale \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VMSS_NAME" \
    --new-capacity 0 \
    --no-wait || echo "Scale command failed, continuing..."

# Clean up runners using gh CLI
echo "Removing GitHub runners for VMSS: $VMSS_NAME"
for attempt in {1..5}; do
    echo "Runner cleanup attempt $attempt/5"

    # Get all runners and filter for our VMSS
    RUNNERS=$(gh api repos/$REPOSITORY/actions/runners --jq ".runners[] | select(.labels[].name | contains(\"$VMSS_NAME\") or .name | contains(\"$VMSS_NAME\")) | .id" 2>/dev/null || echo "")

    if [[ -n "$RUNNERS" ]]; then
        echo "Found runners to remove:"
        echo "$RUNNERS"

        for runner_id in $RUNNERS; do
            if [[ -n "$runner_id" && "$runner_id" != "null" ]]; then
                echo "Removing runner ID: $runner_id"
                gh api --method DELETE repos/$REPOSITORY/actions/runners/$runner_id || echo "Failed to remove runner $runner_id"
                sleep 1
            fi
        done
    else
        echo "No runners found for cleanup"
        break
    fi

    if [[ $attempt -lt 5 ]]; then
        echo "Waiting 15 seconds before next attempt..."
        sleep 15
    fi
done

# Wait for instances to actually be deleted
echo "Waiting for instances to be fully deleted..."
for i in {1..20}; do
    REMAINING_COUNT=$(az vmss list-instances \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VMSS_NAME" \
        --query "length(@)" \
        --output tsv 2>/dev/null || echo "0")

    echo "Remaining instances: $REMAINING_COUNT"

    if [[ "$REMAINING_COUNT" == "0" ]]; then
        echo "All instances deleted successfully"
        break
    fi

    if [[ $i == 20 ]]; then
        echo "WARNING: Some instances may still be running after cleanup timeout"
    fi

    sleep 10
done

echo "VMSS $VMSS_NAME cleanup completed"

# Delete VMSS entirely for closed PRs
if [[ "$IS_PR_CLOSED" == "true" ]]; then
    echo "PR closed - deleting VMSS entirely"
    az vmss delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VMSS_NAME" \
        --no-wait || echo "VMSS deletion failed, but continuing..."
    echo "VMSS deletion initiated"
fi