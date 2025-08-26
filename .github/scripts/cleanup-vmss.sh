# In cleanup-vmss.sh, update role cleanup
SYSTEM_PRINCIPAL_ID=$(az vmss show `
    --resource-group "$RESOURCE_GROUP" `
    --name "$VMSS_NAME" `
    --query "identity.principalId" `
    --output tsv 2>/dev/null || echo "")

if [[ -n "$SYSTEM_PRINCIPAL_ID" && "$SYSTEM_PRINCIPAL_ID" != "null" ]]; then
    echo "Removing Key Vault role assignment for system identity"
    az role assignment delete `
        --assignee "$SYSTEM_PRINCIPAL_ID" `
        --role "Key Vault Secrets User" `
        --scope "/subscriptions/65a430fb-5a9a-49ff-969e-05d1beaa88fb/resourcegroups/dbatools-ci-runners/providers/Microsoft.KeyVault/vaults/dbatoolsci" || true
fi