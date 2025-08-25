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

# Remove GitHub runners
echo "Removing GitHub runners for VMSS: $VMSS_NAME"
RUNNERS=$(curl -s -H "Authorization: token $GITHUB_PAT" \
    "https://api.github.com/repos/$REPOSITORY/actions/runners" | \
    jq -r ".runners[] | select(.labels[].name | contains(\"$VMSS_NAME\")) | .id")

if [[ -n "$RUNNERS" ]]; then
    echo "Found runners to remove:"
    echo "$RUNNERS"

    for runner_id in $RUNNERS; do
        echo "Removing runner ID: $runner_id"
        curl -X DELETE \
            -H "Authorization: token $GITHUB_PAT" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/$REPOSITORY/actions/runners/$runner_id" || true
        sleep 2
    done
else
    echo "No runners found for cleanup"
fi

# Scale down VMSS
echo "Scaling down $VMSS_NAME to 0 instances"
az vmss scale \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VMSS_NAME" \
    --new-capacity 0

echo "VMSS $VMSS_NAME scaled down successfully"

# Delete VMSS entirely for closed PRs
if [[ "$IS_PR_CLOSED" == "true" ]]; then
    echo "PR closed - deleting VMSS entirely"
    az vmss delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VMSS_NAME" \
        --no-wait
    echo "VMSS deletion initiated"
fi