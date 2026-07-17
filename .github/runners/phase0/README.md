# Phase 0 — feasibility gates for self-hosted CI on Azure VMSS

Everything here runs against a **throwaway VM** booted from the legacy golden image
(`dbatoolsGallery/dbatools-golden-image` v1.0.0, RG `DBATOOLS-CI-IMAGES`, eastus).
All in-guest access goes through the Azure guest agent (`az vm run-command`) — no open
inbound ports, no RDP. That same channel is the production troubleshooting story, so
proving it here is Gate A.

## The gates

| Gate | Question | Proven by |
|---|---|---|
| A | Does the image boot and does the guest agent answer? | `az vm run-command invoke` returns output |
| B | Does the .NET 8 actions runner run on Server 2012? | `Runner.Listener.exe --version` + an ephemeral runner completing `runner-gate-hello.yml` |
| C | Does the runnerless pattern work end to end? | `tests/ps3-smoke.ps1` executed via run-command |

## Runbook

```bash
# 1. scratch RG + VM from the golden image (ephemeral OS disk on the 150GB local disk)
az group create --name dbatools-ci-phase0 --location eastus --tags purpose=phase0-scratch
az vm create --resource-group dbatools-ci-phase0 --name dbat-phase0 \
  --image "/subscriptions/<sub>/resourceGroups/DBATOOLS-CI-IMAGES/providers/Microsoft.Compute/galleries/dbatoolsGallery/images/dbatools-golden-image/versions/1.0.0" \
  --size Standard_D4ds_v5 --admin-username dbatools --admin-password "<random>" \
  --nsg-rule NONE --public-ip-sku Standard \
  --ephemeral-os-disk true --ephemeral-os-disk-placement ResourceDisk --os-disk-caching ReadOnly

# 2. Gate A + inventory
az vm run-command invoke --resource-group dbatools-ci-phase0 --name dbat-phase0 \
  --command-id RunPowerShellScript --scripts "@.github/runners/phase0/inventory.ps1"

# 3. Gate B: ephemeral runner (token is single-use, expires in 1h, never stored on the VM)
TOKEN=$(gh api -X POST repos/dataplat/dbatools/actions/runners/registration-token --jq .token)
az vm run-command invoke --resource-group dbatools-ci-phase0 --name dbat-phase0 \
  --command-id RunPowerShellScript --scripts "@.github/runners/phase0/install-runner.ps1" \
  --parameters "Token=$TOKEN" "ZipUrl=<actions-runner-win-x64 zip url>"
gh workflow run runner-gate-hello.yml --ref <branch> -R dataplat/dbatools

# 4. Gate C: runnerless PS3 smoke
az vm run-command invoke --resource-group dbatools-ci-phase0 --name dbat-phase0 \
  --command-id RunPowerShellScript --scripts "@tests/ps3-smoke.ps1" \
  --parameters "RepoZipUrl=https://codeload.github.com/dataplat/dbatools/zip/refs/heads/<branch>"

# 5. boot problems? screenshot + serial log without any inbound access
az vm boot-diagnostics get-boot-log --resource-group dbatools-ci-phase0 --name dbat-phase0

# 6. tear down (the VM is disposable; recreating takes ~5 minutes)
az group delete --name dbatools-ci-phase0 --yes --no-wait
```

## Notes

- `az vm create --security-type Standard` fails on this subscription until the
  `Microsoft.Compute/UseStandardSecurityType` feature is registered — omit the flag and
  the platform picks Standard implicitly for Gen1 images.
- run-command output is capped at ~4KB per stream; keep in-guest scripts terse.
- Registration tokens come from `gh api` locally today; in production (Phase 3) a
  fine-grained PAT (`CI_RUNNER_PAT`, Administration R/W) mints them inside workflows,
  because `GITHUB_TOKEN` cannot.
