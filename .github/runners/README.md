# dbatools self-hosted CI on Azure VM Scale Sets

Replaces AppVeyor with disposable Azure VMs: every job runs on a factory-fresh
ephemeral VM booted from a golden image with SQL Server preinstalled, registered as a
single-use GitHub runner, and deleted afterwards. Activity heats three independent
AppVeyor-style lanes for two hours: ten runners each for `potatoqualitee` and
`andreasjordan`, plus five shared community runners. With no activity, capacity is zero.

```
GitHub (public repo)                          Azure (eastus)
├─ ci-azure.yml          10-job matrix   ──►  VMSS dbatools-runners (Flexible, D4ds_v5)
├─ runner-reconcile.yml  event + hourly       ├─ ephemeral OS disk on local SSD ($0)
├─ runner-scale-up.yml    manual recovery     ├─ instance public IPs, NSG deny inbound
└─ ps3-smoke.yml          nightly PS 3.0      └─ image: dbatoolsGallery/dbatools-modern-image
                                              RG dbatools-ci, budget $600/mo + alerts
```

## Key facts

| Thing | Value |
|---|---|
| Runner labels | Base `dbatools-modern` plus exactly one pool label: `dbatools-pool-potatoqualitee`, `dbatools-pool-andreasjordan`, or `dbatools-pool-community` |
| Golden image | `dbatoolsGallery/dbatools-modern-image` — Server 2022, SQL 2017/2019/2022 Developer (instances `SQL2017/SQL2019/SQL2022`, ports 14334/14335/14336, Manual start, mixed auth sa=AppVeyor convention) |
| Legacy image | `dbatoolsGallery/dbatools-golden-image` v1.0.0 — Server 2012, PS 3.0, SQL 2008R2/2012/2014/2016/2017 (used by nightly `ps3-smoke.yml`, runnerless); v2.0.0 adds WMF 5.1 (PS 5.1) for a future legacy runner pool |
| Runner execution | **interactive autologon session** as local admin `appveyor` (AppVeyor parity: BITS transfers, `$env:USERNAME`, `C:\Users\appveyor\Documents\DbatoolsExport`); bootstrap registers the ephemeral runner, arms autologon + a logon task, reboots |
| Instance parity knobs | firewall off, `LocalAccountTokenFilterPolicy=1`, pagefile setting on D:, `@@SERVERNAME` repaired per job (all NSG-shielded) |
| Harness | untouched `tests/appveyor.*.ps1` via `tests/gha.shim.ps1` (`APPVEYOR=True` drives Get-TestConfig) |
| Scaling controls | Each lane heats on a commit or queued build and cools to zero after `BOOST_HOURS`; repo variable `MAX_RUNNERS=25` is the hard VMSS ceiling |
| Build queue | Workflow concurrency uses `queue: max`: one matrix build per lane consumes that lane's workers while later builds wait FIFO, matching AppVeyor account concurrency |
| Pool sizes | Repo variables `BOOST_USERS` / `BOOST_COUNT` / `BOOST_HOURS`; maintainers receive ten dedicated workers each and non-maintainers share five |
| Azure auth | OIDC only — Entra app `dbatools-ci-github`, federated for the default branch, custom role `dbatools-ci-operator` scoped to RG `dbatools-ci` |
| Runner registration | `CI_RUNNER_PAT` secret mints single-use tokens; tokens are never stored on VMs |

## Security model (public repo + self-hosted)

1. Ephemeral single-job runners; the VM is deleted after every job — nothing persists.
2. Runner VMs hold **no Azure identity, no PAT, no secrets**; scale-up/reconcile run on
   GitHub-hosted runners in default-branch context only.
3. NSG default-denies inbound; `debug.ps1 -Action open-rdp` opens 3389 to your current
   IP only, `close-rdp` removes it.
4. Repo setting "require approval for outside collaborators" gates fork PRs before they
   can touch a runner.
5. `CI_RUNNER_PAT` should be a fine-grained PAT: repo `dataplat/dbatools`, permission
   Administration (read/write), nothing else. **Stopgap note:** during initial rollout it
   was seeded from a personal OAuth token — replace it (github.com → Settings →
   Developer settings → fine-grained tokens), then `gh secret set CI_RUNNER_PAT`.

## Operations

```bash
# fleet state at a glance (instances + registered runners)
pwsh .github/runners/debug.ps1 -Action list

# logs from a specific instance (no RDP, works with deny-all NSG)
pwsh .github/runners/debug.ps1 -Action tail-runner -InstanceName dbatools-runners_xxxxxx
pwsh .github/runners/debug.ps1 -Action tail-sql    -InstanceName dbatools-runners_xxxxxx
pwsh .github/runners/debug.ps1 -Action run -InstanceName dbatools-runners_xxxxxx -Script "Get-Service MSSQL*"

# manually reconcile now, optionally heating one maintainer lane immediately
gh workflow run runner-scale-up.yml -f boost_user=potatoqualitee

# rebuild the modern golden image (new SQL CU, new tooling, or adding sql2025)
pwsh .github/runners/build-modern-image.ps1 -ImageVersion 1.0.1 -Branch development
# then point the VMSS at the new version:
az vmss update -g dbatools-ci -n dbatools-runners --set virtualMachineProfile.storageProfile.imageReference.id=<new image version id>

# provision/repair all infrastructure (idempotent)
pwsh .github/runners/infra.ps1 -ImageId <gallery image id>
```

## How a CI run flows

1. Push/PR triggers `ci-azure.yml`; its build waits in the actor's FIFO concurrency
   lane, then its matrix queues on that lane's pool-specific runner label.
2. `runner-reconcile.yml` reacts to the requested CI run, raises that logical pool to
   five or ten workers (total cap `MAX_RUNNERS=25`), tags each Flexible VMSS instance
   with its pool, and registers an ephemeral runner on every new instance via
   `az vm run-command` + `bootstrap-runner.ps1` (which then reboots the VM into the
   appveyor autologon session where run.cmd picks up the job). `runner-scale-up.yml`
   remains as a manual recovery tool.
3. Each job: sync repo at `C:\github\dbatools` → CRLF tests → one PowerShell session
   runs prep → instance setup (`appveyor.SQL*.ps1` set static ports, start services,
   EKM/HADR/master key) → `@@SERVERNAME` repair → Pester 6 → finalize → post.
4. Every matrix job nudges reconcile as it finishes. The ephemeral runner unregisters,
   its spent VM is deleted, and a pristine replacement restores that lane's hot size.
   A lane cools to zero two hours after its last commit once no build remains queued.

## Cost guardrails

- Budget `dbatools-ci-budget`: $600/month on RG `dbatools-ci`, email at 50/80/100%.
- Dead-runner cleanup: reconcile deletes never-registered and offline instances;
  healthy online hot-pool runners are not evicted merely because of age.
- Community activity heats a five-runner shared lane for `BOOST_HOURS`; it is zero
  during inactive weeks. Each maintainer independently heats ten dedicated runners.
- Maximum capacity is 25 only when both maintainers and community are active together;
  otherwise the VMSS scales to the sum of the active lanes, including zero.
- Weekly month-to-date spend lands on the "CI cost tracker" issue (Mondays).
- Ephemeral OS disks cost nothing; the only storage bill is the gallery replicas.
- Dead man's switch (last ditch): Azure Automation account `dbatools-ci-janitor`
  runs the `Remove-RunawayRunner` runbook every 6 hours, entirely independent
  of GitHub Actions (source: `janitor-runbook.ps1`, deployed manually). It always
  preserves the desired 0/5/10/15/20/25-runner total. Excess runners older than 2h
  are deleted; if GitHub is unreachable, conservative age caps apply to all capacity.
  ps3smoke VMs past 2h and orphaned CI NICs/public IPs
  die in every mode. Its managed identity holds
  only the `dbatools-ci-operator` role on RG `dbatools-ci` -- no storage, no
  other resource groups. There is no all-day baseline; the switch caps runaway cost.

## Phase 0 gate results (2026-07-10)

- Azure guest agent answers run-command on the legacy image (the entire debug story).
- The .NET 8 runner 2.335.1 **works on Server 2012**: registered ephemeral, ran a job
  under PS 3.0, self-unregistered (see `phase0/README.md`).
- dbatools imports on PS 3.0 (718 commands) and the core battery passed 15/15 against
  SQL 2008 R2 and SQL 2017 via the runnerless pattern.
