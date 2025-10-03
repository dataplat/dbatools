# AppVeyor to GitHub Actions Migration - COMPLETE ✅

## Migration Summary

Successfully migrated from AppVeyor to GitHub Actions with Azure VMSS self-hosted runners.

### Files Created (19 files)

#### Test Runner Scripts (`tests/runner/`)
- ✅ `github-helpers.ps1` - GitHub Actions equivalents of AppVeyor cmdlets
- ✅ `prep.ps1` - Environment preparation
- ✅ `sqlserver.ps1` - SQL Server instance setup orchestration
- ✅ `pester.ps1` - Pester test execution
- ✅ `post.ps1` - Post-test cleanup and coverage upload
- ✅ `common.ps1` - Common test selection functions
- ✅ `setup-sql2008r2sp2.ps1` - SQL 2008R2 instance configuration
- ✅ `setup-sql2016.ps1` - SQL 2016 instance configuration
- ✅ `setup-sql2017.ps1` - SQL 2017 instance configuration

#### Terraform Infrastructure (`gh-runners/`)
- ✅ `.gitignore` - Terraform state exclusions
- ✅ `version.tf` - Provider versions (Azure, GitHub)
- ✅ `variables.tf` - Variable definitions
- ✅ `variables.tfvars` - Your configuration values
- ✅ `vmss.tf` - VMSS, networking, Key Vault integration
- ✅ `github_components.tf` - GitHub runner group
- ✅ `init.ps1` - Runner registration and startup script

#### GitHub Actions Workflows (`.github/workflows/`)
- ✅ `vmss-deploy.yml` - Infrastructure deployment workflow
- ✅ `ci.yml` - Main CI workflow (10-job matrix, max 3 concurrent)

### Files Modified
- ✅ `appveyor.yml` → `appveyor.yml.disabled` (renamed)

### Files Deleted (8 files)
- ✅ `tests/appveyor.prep.ps1`
- ✅ `tests/appveyor.sqlserver.ps1`
- ✅ `tests/appveyor.pester.ps1`
- ✅ `tests/appveyor.post.ps1`
- ✅ `tests/appveyor.common.ps1`
- ✅ `tests/appveyor.SQL2008R2SP2.ps1`
- ✅ `tests/appveyor.SQL2016.ps1`
- ✅ `tests/appveyor.SQL2017.ps1`

---

## Next Steps

### 1. Review Changes
```powershell
git diff --stat
git status
```

### 2. Create Feature Branch and Commit
```powershell
git checkout -b migrate-to-github-actions
git add .
git status  # Verify all files
git commit -m "Migrate from AppVeyor to GitHub Actions with Azure VMSS runners

- Created tests/runner/ directory with migrated test scripts
- Created gh-runners/ Terraform infrastructure
- Created GitHub Actions workflows (vmss-deploy.yml, ci.yml)
- Disabled appveyor.yml
- Removed old AppVeyor test scripts

Infrastructure:
- Azure VMSS with Windows golden image
- Max 3 concurrent runners (ephemeral)
- Self-hosted runners with SQL Server instances
- Key Vault integration for secrets

CI Workflow:
- 10-job matrix (same as AppVeyor)
- Max 3 concurrent jobs
- Triggers on push/PR (except master branch)
- Skip conditions: [skip ci], paths-ignore
"
```

### 3. Push to GitHub
```powershell
git push origin migrate-to-github-actions
```

### 4. Deploy Infrastructure
The `vmss-deploy.yml` workflow will automatically run when you push because it contains `gh-runners/**` files.

**Monitor the workflow:**
1. Go to: https://github.com/dataplat/dbatools/actions
2. Find "Deploy VMSS Infrastructure" workflow
3. Watch it create your Azure resources

### 5. Verify Infrastructure in Azure
```powershell
# Check VMSS was created
az vmss show --resource-group dbatools-ci-runners --name dbatools-runner-vmss

# Check runner group in GitHub
# Go to: https://github.com/dataplat/dbatools/settings/actions/runner-groups
```

### 6. Test Single Runner
```powershell
# Scale VMSS to 1 instance
az vmss scale --resource-group dbatools-ci-runners --name dbatools-runner-vmss --new-capacity 1

# Wait 5-10 minutes, then check GitHub runners
# Go to: https://github.com/dataplat/dbatools/settings/actions/runners
# You should see a runner with labels: self-hosted, azure-vmss, windows, sqlserver
```

### 7. Test Single CI Job
1. Go to: https://github.com/dataplat/dbatools/actions/workflows/ci.yml
2. Click "Run workflow"
3. Select branch: `migrate-to-github-actions`
4. Click "Run workflow"
5. Watch the job execute
6. Verify runner auto-unregisters after job completes

### 8. Test Full Matrix
```powershell
# Make a small test commit
echo "# Test commit" >> README.md
git add README.md
git commit -m "Test: Trigger full CI matrix"
git push
```

**Expected behavior:**
- 10 jobs queued
- First 3 jobs run concurrently
- Remaining 7 jobs wait in queue
- Each job completes and runner self-destructs
- VMSS scales back to 0 when all jobs complete

### 9. Merge to Development
```powershell
# After successful tests
git checkout development
git merge migrate-to-github-actions
git push origin development
```

### 10. Disable AppVeyor
1. Go to: https://ci.appveyor.com/project/dataplat/dbatools/settings
2. Disable builds OR delete the project
3. OR remove webhook from GitHub:
   - https://github.com/dataplat/dbatools/settings/hooks
   - Find AppVeyor webhook
   - Click "Delete"

---

## Configuration Details

### Azure Resources
- **Resource Group:** `dbatools-ci-runners`
- **Location:** `eastus`
- **VMSS Name:** `dbatools-runner-vmss`
- **VM SKU:** `Standard_B4ms` (4 vCPU, 16 GB RAM)
- **Image:** `dbatools-golden-image` (from `dbatools-ci-images` RG)
- **Key Vault:** `dbatoolsci`
- **Min Instances:** 0 (scale to zero when idle)
- **Max Instances:** 3 (max concurrent jobs)

### GitHub Secrets (Already Configured)
- ✅ `VMSS_AZURE_CREDENTIALS` - Service principal credentials
- ✅ `VMSS_GH_PAT` - GitHub Personal Access Token

### Runner Configuration
- **Labels:** `self-hosted`, `azure-vmss`, `windows`, `sqlserver`
- **Runner Group:** `azure-vmss-runners`
- **Mode:** Ephemeral (auto-destroy after each job)
- **Working Directory:** `C:\actions-runner\_work`

### CI Matrix (10 jobs)
1. 2008R2 (1/2)
2. 2008R2 (2/2)
3. 2016 (1/2)
4. 2016 (2/2)
5. service_restarts (1/2)
6. service_restarts (2/2)
7. 2016_2017 (1/2)
8. 2016_2017 (2/2)
9. default (1/2)
10. default (2/2)

**Max 3 concurrent, others queue**

---

## Cost Estimation

### Azure VMSS (Standard_B4ms)
- **Hourly Rate:** ~$0.166/hour per instance
- **Max Cost:** $0.166 × 3 instances = $0.50/hour
- **Typical Test Duration:** 20-30 minutes

### Monthly Cost Estimate
```
100 builds/month × 0.5 hours × $0.50/hour = $25/month
```

**Well within $150/month budget!**

### Cost Optimization Tips
1. **Use Spot Instances** (save ~70%)
2. **Use smaller VMs for lighter tests** (B2ms = $0.08/hr)
3. **Implement auto-scale based on queue depth**

---

## Troubleshooting

### Runner Doesn't Register
```powershell
# Check extension logs
az vmss extension show \
  --resource-group dbatools-ci-runners \
  --vmss-name dbatools-runner-vmss \
  --name CustomScriptExtension

# Check Key Vault access
az role assignment list --scope /subscriptions/{sub-id}/resourceGroups/dbatools-ci-runners
```

### Jobs Stuck in Queue
```powershell
# Check runner status
gh api /repos/dataplat/dbatools/actions/runners

# Manually scale up
az vmss scale --resource-group dbatools-ci-runners --name dbatools-runner-vmss --new-capacity 3
```

### High Costs
```powershell
# Check for stuck VMs
az vmss list-instances --resource-group dbatools-ci-runners --name dbatools-runner-vmss

# Force scale to 0
az vmss scale --resource-group dbatools-ci-runners --name dbatools-runner-vmss --new-capacity 0
```

---

## Success Criteria

✅ All file operations complete (19 created, 8 deleted, 1 renamed)
⏳ Infrastructure deployed via Terraform
⏳ Runners register successfully
⏳ Single test job completes
⏳ Full matrix (10 jobs) completes
⏳ Max 3 concurrent jobs respected
⏳ Jobs queue properly when >3 pending
⏳ AppVeyor disabled

---

## Support

- **GitHub Issues:** https://github.com/dataplat/dbatools/issues
- **Azure Support:** https://portal.azure.com/#blade/Microsoft_Azure_Support/HelpAndSupportBlade
- **Terraform Docs:** https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs

---

**🎉 Migration implementation complete! Ready to push to GitHub.**
