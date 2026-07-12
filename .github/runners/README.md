# dbatools self-hosted CI on Azure VM Scale Sets

Replaces AppVeyor with disposable Azure VMs: every job runs on a factory-fresh
ephemeral VM booted from a golden image with SQL Server preinstalled, registered as a
single-use GitHub runner, and deleted afterwards. Nights and weekends the fleet scales
to zero; during Paris business hours a small standby pool keeps queue times low.

```
GitHub (public repo)                          Azure (eastus)
├─ ci-azure.yml           8-job matrix   ──►  VMSS dbatools-runners (Flexible, D4ds_v5)
├─ runner-scale-up.yml    on demand +1..N     ├─ ephemeral OS disk on local SSD ($0)
├─ runner-reconcile.yml   */10 min janitor    ├─ instance public IPs, NSG deny inbound
└─ ps3-smoke.yml          nightly PS 3.0      └─ image: dbatoolsGallery/dbatools-modern-image
                                              RG dbatools-ci, budget $600/mo + alerts
```

## Key facts

| Thing | Value |
|---|---|
| Runner label | `dbatools-modern` (`runs-on: [self-hosted, dbatools-modern]`) |
| Golden image | `dbatoolsGallery/dbatools-modern-image` — Server 2022, SQL 2017/2019/2022 Developer (instances `SQL2017/SQL2019/SQL2022`, ports 14334/14335/14336, Manual start, mixed auth sa=AppVeyor convention) |
| Legacy image | `dbatoolsGallery/dbatools-golden-image` v1.0.0 — Server 2012, PS 3.0, SQL 2008R2/2012/2014/2016/2017 (used by nightly `ps3-smoke.yml`, runnerless); v2.0.0 adds WMF 5.1 (PS 5.1) for a future legacy runner pool |
| Runner execution | **interactive autologon session** as local admin `appveyor` (AppVeyor parity: BITS transfers, `$env:USERNAME`, `C:\Users\appveyor\Documents\DbatoolsExport`); bootstrap registers the ephemeral runner, arms autologon + a logon task, reboots |
| Instance parity knobs | firewall off, `LocalAccountTokenFilterPolicy=1`, pagefile setting on D:, `@@SERVERNAME` repaired per job (all NSG-shielded) |
| Harness | untouched `tests/appveyor.*.ps1` via `tests/gha.shim.ps1` (`APPVEYOR=True` drives Get-TestConfig) |
| Scaling controls | repo variables `STANDBY_COUNT` / `STANDBY_HOURS` / `STANDBY_TZ` / `MAX_RUNNERS` |
| Maintainer boost | repo variables `BOOST_USERS` / `BOOST_COUNT` / `BOOST_HOURS` / `BOOST_COMMITS` — once listed users have pushed `BOOST_COMMITS` commits (default 3) to branches other than development/master within the trailing `BOOST_HOURS` window, the floor rises to `BOOST_COUNT` until the window drains (any hour, any day); `runner-boost.yml` nudges reconcile on those pushes so it applies within ~1 minute |
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

# force capacity now (reconcile enforces the floor within 10 minutes anyway)
gh workflow run runner-scale-up.yml -f ensure=3

# rebuild the modern golden image (new SQL CU, new tooling, or adding sql2025)
pwsh .github/runners/build-modern-image.ps1 -ImageVersion 1.0.1 -Branch development
# then point the VMSS at the new version:
az vmss update -g dbatools-ci -n dbatools-runners --set virtualMachineProfile.storageProfile.imageReference.id=<new image version id>

# provision/repair all infrastructure (idempotent)
pwsh .github/runners/infra.ps1 -ImageId <gallery image id>
```

## How a CI run flows

1. Push/PR triggers `ci-azure.yml` → 8 matrix jobs queue on label `dbatools-modern`.
2. `runner-scale-up.yml` (workflow_run: requested) counts queued jobs, raises VMSS
   capacity (cap `MAX_RUNNERS`), and registers an ephemeral runner on every new
   instance via `az vm run-command` + `bootstrap-runner.ps1` (which then reboots the
   VM into the appveyor autologon session where run.cmd picks up the job).
3. Each job: sync repo at `C:\github\dbatools` → CRLF tests → one PowerShell session
   runs prep → instance setup (`appveyor.SQL*.ps1` set static ports, start services,
   EKM/HADR/master key) → `@@SERVERNAME` repair → Pester 6 → finalize → post.
4. After the job the ephemeral runner unregisters; `runner-reconcile.yml` deletes the
   spent instance and tops the fleet back up to the standby floor (or zero off-hours).

## Cost guardrails

- Budget `dbatools-ci-budget`: $600/month on RG `dbatools-ci`, email at 50/80/100%.
- Zombie kill: reconcile deletes any non-busy instance older than 3h.
- Scale-to-zero outside `STANDBY_HOURS` (`STANDBY_TZ`, Mon–Fri).
- Maintainer boost holds `BOOST_COUNT` warm runners once `BOOST_COMMITS` commits
  land in the window; it self-expires `BOOST_HOURS` after the last qualifying
  push (worst case ~10 × D4ds_v5 for 3h ≈ $7).
- Weekly month-to-date spend lands on the "CI cost tracker" issue (Mondays).
- Ephemeral OS disks cost nothing; the only storage bill is the gallery replicas.
- Dead man's switch: Azure Automation account `dbatools-ci-janitor` runs the
  `Remove-RunawayRunner` runbook every 6 hours, entirely independent of GitHub
  (source: `janitor-runbook.ps1`). It deletes runner VMs past their age cap
  (3h nights/weekends, 13h weekday daytime so the standby floor may idle),
  ps3smoke VMs past 2h, and orphaned CI NICs/public IPs. Its managed identity
  holds only the `dbatools-ci-operator` role on RG `dbatools-ci` -- no storage,
  no other resource groups. If GitHub-side reconcile ever dies, worst-case
  runaway spend is bounded at roughly one fleet-day instead of unbounded.

## Phase 0 gate results (2026-07-10)

- Azure guest agent answers run-command on the legacy image (the entire debug story).
- The .NET 8 runner 2.335.1 **works on Server 2012**: registered ephemeral, ran a job
  under PS 3.0, self-unregistered (see `phase0/README.md`).
- dbatools imports on PS 3.0 (718 commands) and the core battery passed 15/15 against
  SQL 2008 R2 and SQL 2017 via the runnerless pattern.
