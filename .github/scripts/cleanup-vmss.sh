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
echo "PR Closed: $IS_PR_CLOSED"

# Set up gh CLI authentication
export GH_TOKEN="$GITHUB_PAT"

# Function to retry operations
retry_operation() {
    local cmd="$1"
    local max_attempts=3
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        echo "Attempt $attempt/$max_attempts: Running operation"
        if eval "$cmd"; then
            return 0
        fi

        if [ $attempt -lt $max_attempts ]; then
            echo "Operation failed, retrying in 5 seconds..."
            sleep 5
        fi
        ((attempt++))
    done

    echo "Operation failed after $max_attempts attempts"
    return 1
}

# Check if VMSS exists
if ! az vmss show --resource-group "$RESOURCE_GROUP" --name "$VMSS_NAME" &>/dev/null; then
    echo "VMSS $VMSS_NAME does not exist, checking for runners only..."
else
    # Set cleanup tag to coordinate with other processes
    CLEANUP_TIME=$(date +%s)
    echo "Marking VMSS for cleanup..."
    az vmss update \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VMSS_NAME" \
        --set tags.cleanup_in_progress="$CLEANUP_TIME" || echo "Failed to set cleanup tag, continuing..."

    # Get current instance count
    CURRENT_COUNT=$(az vmss show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VMSS_NAME" \
        --query "sku.capacity" \
        --output tsv 2>/dev/null || echo "0")

    echo "Current VMSS capacity: $CURRENT_COUNT"

    if [ "$CURRENT_COUNT" -gt 0 ]; then
        # Force delete all instances first (most aggressive approach)
        echo "Force terminating all VMSS instances..."
        INSTANCE_IDS=$(az vmss list-instances \
            --resource-group "$RESOURCE_GROUP" \
            --name "$VMSS_NAME" \
            --query "[].instanceId" \
            --output tsv 2>/dev/null || echo "")

        if [[ -n "$INSTANCE_IDS" ]]; then
            echo "Found instances to delete: $INSTANCE_IDS"
            # Delete all instances in parallel for speed
            for instance_id in $INSTANCE_IDS; do
                {
                    echo "Force deleting instance: $instance_id"
                    retry_operation "az vmss delete-instances \
                        --resource-group '$RESOURCE_GROUP' \
                        --name '$VMSS_NAME' \
                        --instance-ids '$instance_id' \
                        --force-deletion true"
                } &
            done

            # Wait for all background deletions to complete
            wait
            echo "All instance deletions initiated"
        fi

        # Scale to 0 as backup (synchronous)
        echo "Scaling VMSS to 0 instances..."
        retry_operation "az vmss scale \
            --resource-group '$RESOURCE_GROUP' \
            --name '$VMSS_NAME' \
            --new-capacity 0"

        # Aggressive verification with shorter timeout
        echo "Verifying all instances are terminated..."
        for i in {1..20}; do
            RUNNING_COUNT=$(az vmss list-instances \
                --resource-group "$RESOURCE_GROUP" \
                --name "$VMSS_NAME" \
                --query "length(@)" \
                --output tsv 2>/dev/null || echo "0")

            if [[ "$RUNNING_COUNT" == "0" ]]; then
                echo "All instances confirmed terminated"
                break
            fi

            echo "Still have $RUNNING_COUNT instances, waiting... ($i/20)"

            # Emergency cleanup on final attempt
            if [[ $i == 20 ]]; then
                echo "EMERGENCY: Force deleting any remaining instances"
                REMAINING_IDS=$(az vmss list-instances \
                    --resource-group "$RESOURCE_GROUP" \
                    --name "$VMSS_NAME" \
                    --query "[].instanceId" \
                    --output tsv 2>/dev/null || echo "")

                for instance_id in $REMAINING_IDS; do
                    echo "EMERGENCY: Force delete instance $instance_id"
                    az vmss delete-instances \
                        --resource-group "$RESOURCE_GROUP" \
                        --name "$VMSS_NAME" \
                        --instance-ids "$instance_id" \
                        --force-deletion true \
                        --no-wait || echo "Emergency delete failed for $instance_id"
                done

                # Final wait
                sleep 30
            else
                sleep 5
            fi
        done
    fi
fi

# Clean up GitHub runners aggressively with better error handling
echo "=== GitHub Runner Cleanup ==="
for attempt in {1..3}; do
    echo "Runner cleanup attempt $attempt/3"

    # Get all runners with multiple filtering approaches
    echo "Fetching registered runners..."
    ALL_RUNNERS=$(gh api repos/$REPOSITORY/actions/runners --jq '.runners[]' 2>/dev/null || echo '[]')

    if [[ "$ALL_RUNNERS" == "[]" || -z "$ALL_RUNNERS" ]]; then
        echo "No runners found in repository"
        break
    fi

    # Filter runners by multiple criteria for thorough cleanup
    VMSS_RUNNERS=$(echo "$ALL_RUNNERS" | jq -r "
        select(
            (.labels[]?.name // \"\" | contains(\"$VMSS_NAME\")) or
            (.name // \"\" | contains(\"$VMSS_NAME\")) or
            (.labels[]?.name // \"\" | test(\"build-.*\")) or
            (.labels[]?.name // \"\" | contains(\"$RESOURCE_GROUP\"))
        ) | .id" 2>/dev/null || echo "")

    RUNNER_COUNT=$(echo "$VMSS_RUNNERS" | wc -w)
    echo "Found $RUNNER_COUNT runners to remove"

    if [[ -n "$VMSS_RUNNERS" && "$VMSS_RUNNERS" != "" ]]; then
        echo "Removing runners: $VMSS_RUNNERS"

        # Remove runners in parallel for speed
        for runner_id in $VMSS_RUNNERS; do
            if [[ -n "$runner_id" && "$runner_id" != "null" ]]; then
                {
                    echo "Removing runner ID: $runner_id"
                    retry_operation "gh api --method DELETE repos/$REPOSITORY/actions/runners/$runner_id"
                } &
            fi
        done

        # Wait for all removals to complete
        wait
        echo "All runner removals initiated"

        # Short wait before next attempt
        if [[ $attempt -lt 3 ]]; then
            sleep 10
        fi
    else
        echo "No runners found matching VMSS: $VMSS_NAME"
        break
    fi
done

# Final VMSS state verification
if az vmss show --resource-group "$RESOURCE_GROUP" --name "$VMSS_NAME" &>/dev/null; then
    FINAL_COUNT=$(az vmss show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VMSS_NAME" \
        --query "sku.capacity" \
        --output tsv 2>/dev/null || echo "0")

    if [[ "$FINAL_COUNT" == "0" ]]; then
        echo "SUCCESS: VMSS $VMSS_NAME has 0 instances"

        # Remove cleanup tag
        az vmss update \
            --resource-group "$RESOURCE_GROUP" \
            --name "$VMSS_NAME" \
            --remove tags.cleanup_in_progress || echo "Failed to remove cleanup tag"
    else
        echo "WARNING: VMSS still has $FINAL_COUNT instances after cleanup"
    fi

    # Delete VMSS entirely for closed PRs or if requested
    if [[ "$IS_PR_CLOSED" == "true" ]]; then
        echo "PR closed - deleting VMSS entirely"
        retry_operation "az vmss delete \
            --resource-group '$RESOURCE_GROUP' \
            --name '$VMSS_NAME' \
            --no-wait"
        echo "VMSS deletion initiated"
    fi
else
    echo "VMSS $VMSS_NAME does not exist (may have been deleted)"
fi

# Final verification - ensure no runners remain
echo "=== Final Runner Verification ==="
REMAINING_RUNNERS=$(gh api repos/$REPOSITORY/actions/runners --jq "[.runners[] | select(.labels[].name | contains(\"$VMSS_NAME\") or test(\"build-.*\"))] | length" 2>/dev/null || echo "0")

if [ "$REMAINING_RUNNERS" -gt 0 ]; then
    echo "WARNING: $REMAINING_RUNNERS runners may still be registered"
else
    echo "SUCCESS: No matching runners found in repository"
fi

echo "=== Cleanup completed ==="