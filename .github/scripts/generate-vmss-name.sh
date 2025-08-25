#!/bin/bash
set -e

GITHUB_ACTOR="$1"
GITHUB_EVENT_NAME="$2"
BRANCH_NAME="$3"

# Clean username - remove special chars, lowercase, max 10 chars
CLEAN_USER=$(echo "$GITHUB_ACTOR" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g' | cut -c1-10)

# Clean branch name - remove special chars, lowercase, max 15 chars
if [[ "$GITHUB_EVENT_NAME" == "pull_request" ]]; then
    PREFIX="pr"
else
    PREFIX="push"
fi

CLEAN_BRANCH=$(echo "$BRANCH_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g' | cut -c1-15)

# Create VMSS name: dbatools-{user}-{branch}-{type}
VMSS_NAME="dbatools-${CLEAN_USER}-${CLEAN_BRANCH}-${PREFIX}"

# In generate-vmss-name.sh, after creating VMSS_NAME:
if [[ ${#VMSS_NAME} -gt 50 ]]; then
    # Truncate and add hash for uniqueness
    HASH=$(echo "$GITHUB_ACTOR-$BRANCH_NAME-$GITHUB_EVENT_NAME" | sha256sum | cut -c1-8)
    VMSS_NAME="dbatools-${CLEAN_USER:0:8}-${HASH}"
fi

echo "vmss-name=$VMSS_NAME" >> $GITHUB_OUTPUT
echo "VMSS name: $VMSS_NAME"
echo "Full mapping: $GITHUB_ACTOR/$BRANCH_NAME -> $VMSS_NAME"