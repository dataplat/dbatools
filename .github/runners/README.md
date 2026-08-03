# dbatools self-hosted CI on Azure VM Scale Sets

Replaces AppVeyor with disposable Azure VMs: every job runs on a factory-fresh
ephemeral VM booted from a golden image with SQL Server preinstalled, registered as a
single-use GitHub runner, and deleted afterwards. Activity heats four independent
AppVeyor-style lanes: `potatoqualitee`, `andreasjordan`, `niphlod`, and a shared
community lane. Active maintainer CI gets ten dedicated runners and remains at ten for
20 minutes after completion, then scales to zero. Community is demand-sized up to five
shared runners and holds a small warm floor (`WARM_FLOOR`, currently 3) while it is hot
but has nothing pending; it retains its existing 20-minute completion grace.

```
GitHub (public repo)                          Azure (eastus)
├─ ci-azure.yml          10-job matrix   ──►  VMSS dbatools-runners (Flexible, D4ds_v5)
├─ runner-reconcile.yml  event + 5-minute     ├─ ephemeral OS disk on local SSD ($0)
├─ runner-scale-up.yml    manual recovery     ├─ instance public IPs, NSG deny inbound
└─ ps3-smoke.yml          nightly PS 3.0      └─ image: dbatoolsGallery/dbatools-modern-image
                                              RG dbatools-ci, budget $600/mo + alerts
```

## Key facts

| Thing | Value |
|---|---|
| Runner labels | Base `dbatools-modern` plus exactly one pool label: `dbatools-pool-potatoqualitee`, `dbatools-pool-andreasjordan`, `dbatools-pool-niphlod`, or `dbatools-pool-community` |
| Golden image | `dbatoolsGallery/dbatools-modern-image` — Server 2022, SQL 2017/2019/2022 Developer (instances `SQL2017/SQL2019/SQL2022`, ports 14334/14335/14336, Manual start, mixed auth sa=AppVeyor convention) |
| Legacy image | `dbatoolsGallery/dbatools-golden-image` v1.0.0 — Server 2012, PS 3.0, SQL 2008R2/2012/2014/2016/2017 (used by nightly `ps3-smoke.yml`, runnerless); v2.0.0 adds WMF 5.1 (PS 5.1) for a future legacy runner pool |
| Runner execution | **Windows service as LocalSystem** (`config.cmd --runasservice --windowslogonaccount "NT AUTHORITY\SYSTEM"`). BITS works because LocalSystem is always logged on; no autologon, no plaintext password in the registry, no logon task, no second boot — the service starts during bootstrap and the VM takes its job on its first boot |
| Instance parity knobs | firewall off, `LocalAccountTokenFilterPolicy=1`, `@@SERVERNAME` repaired per job (all NSG-shielded) |
| Harness | the same `tests/appveyor.*.ps1` AppVeyor runs, not a fork, via `tests/gha.shim.ps1` (`APPVEYOR=True` drives Get-TestConfig). Changes to them must keep working on AppVeyor |
| Scaling controls | Active maintainer CI gets ten dedicated runners and remains at ten for 20 minutes after completion, then scales to zero. Community remains demand-sized while CI is live and for its existing 20-minute grace, capped at five and falling back to `WARM_FLOOR` (3) when nothing is pending. Demand never heats a cold community lane or sizes a maintainer lane. `MAX_RUNNERS=35` is the hard VMSS ceiling |
| CI markers | `(do <cmd>)` selects CI tests (the existing campaign convention); `[do ci]` activates the runner pool. They are compatible and unrelated. |
| Build queue | Workflow concurrency uses `queue: max`: one matrix build per lane consumes that lane's workers while later builds wait FIFO, matching AppVeyor account concurrency |
| Pool sizes | Active `potatoqualitee`, `andreasjordan`, and `niphlod` CI each gets ten dedicated workers and remains at ten for 20 minutes after completion, then scales to zero. Non-maintainers share five demand-sized workers with the existing community grace and floor |
| Outbound | Instance public IPs are the fleet's egress -- the subnet has no NAT gateway, no load balancer and no route table, and `defaultOutboundAccess` is unset, so implicit egress is not something to rely on. ~$8.31/mo and scales to zero with the fleet; a NAT gateway bills 24/7 against a fleet that is at zero capacity most of the day. Do not remove the IPs as a cost measure. |
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
gh workflow run runner-scale-up.yml -f boost_user=potatoqualitee -f boost_message='[do ci]'

# rebuild the modern golden image (new SQL CU, new tooling, or adding sql2025)
pwsh .github/runners/build-modern-image.ps1 -ImageVersion 1.0.1 -Branch development
# then point the VMSS at the new version:
az vmss update -g dbatools-ci -n dbatools-runners --set virtualMachineProfile.storageProfile.imageReference.id=<new image version id>

# provision/repair all infrastructure (idempotent)
pwsh .github/runners/infra.ps1 -ImageId <gallery image id>
```

## How a CI run flows

1. Push/PR triggers `ci-azure.yml`; ordinary `potatoqualitee` pushes stop on a
   GitHub-hosted authorization job unless the head commit contains `[do ci]`. Eligible
   builds wait in the actor's FIFO lane, then queue on its pool-specific runner label.
2. `runner-reconcile.yml` reacts to the requested CI run. Active maintainer CI gets ten
   dedicated runners and remains at ten for 20 minutes after completion, then scales to
   zero. Community remains demand-sized with its existing grace and floor (cap five;
   `MAX_RUNNERS=35` overall; the matrix is not created until the `authorize` gate
   clears, so the first pass estimates a full pool and the next replaces it with the
   real count), tags each Flexible VMSS instance
   with its pool, and registers an ephemeral runner on every new instance via
   `az vm run-command` + `bootstrap-runner.ps1` (which registers the runner as a
   LocalSystem Windows service; the service starts immediately and picks up the job on
   that first boot, with no reboot). `runner-scale-up.yml` remains as a manual recovery
   tool.
3. Each job: sync repo at `C:\github\dbatools` → CRLF tests → one PowerShell session
   runs prep → instance setup (`appveyor.SQL*.ps1` set static ports, start services,
   EKM/HADR/master key) → `@@SERVERNAME` repair → Pester 6 → finalize → post.
4. Every matrix job nudges reconcile as it finishes. The ephemeral runner unregisters,
   its spent VM is deleted, and a pristine replacement restores that lane's hot size.
   Maintainer lanes remain at ten for 20 minutes after CI completes, then scale to zero;
   community retains its existing 20-minute grace and demand-sized floor.

## Cost guardrails

- Budget `dbatools-ci-budget`: $600/month on RG `dbatools-ci`, email at 50/80/100%.
- Dead-runner cleanup: reconcile deletes never-registered and offline instances;
  healthy online hot-pool runners are not evicted merely because of age.
- Active maintainer CI gets ten dedicated runners and remains at ten for 20 minutes
  after completion, then scales to zero. Community alone is sized to pending jobs and
  holds `WARM_FLOOR` (3) rather than its full five when hot but idle. This is the largest
  single cost lever in the fleet -- July 2026 ran at 14.6% utilization (138.1 job-hours
  against 948.9 billed VM-hours), almost all of it community capacity sitting hot and idle.
- **Per-VM overhead is a floor that pool sizing cannot reach.** Runners are single-use, so
  July billed 1,726 VMs for 1,668 jobs -- job count, not pool size, decides how many boots
  get paid for, and 28 of an average VM's 33 billed minutes were not job execution.
  Lowering the community `WARM_FLOOR` buys *latency*, not boot savings -- and only for
  the community lane already hot with idle registered VMs, since a cold lane provisions
  from zero whatever the floor is.
  How that 28 minutes splits between idle waiting and boot is not yet measured; the
  `FLEETSTAT` lines (`bootMin`, `onlineObservedMin`, `ageMin`) exist to settle it.
  `onlineObservedMin` is an upper bound sampled by reconcile, not an exact boot timer.
- Active maintainer CI gets ten dedicated runners and remains at ten for 20 minutes
  after completion, then scales to zero. Community CI remains a shared demand-sized
  lane while live and for its existing 20-minute grace, then is zero.
- Maximum capacity is 35 only when all three maintainer lanes are active and community
  demand reaches five jobs; otherwise the VMSS scales to the fixed active maintainer pools
  plus the demand-sized community pool, including zero.
- Reconcile reaps orphaned NICs and instance public IPs every pass (snapshot at the start,
  delete only what was orphaned then and still is), so IP-hours track VM-hours instead of
  outliving them.
- Weekly month-to-date spend lands on the "CI cost tracker" issue (Mondays).
- Ephemeral OS disks cost nothing; the only storage bill is the gallery replicas.
- Dead man's switch (last ditch): Azure Automation account `dbatools-ci-janitor`
  runs the `Remove-RunawayRunner` runbook every 6 hours, entirely independent
  of GitHub Actions (source: `janitor-runbook.ps1`, deployed manually). It preserves ten
  runners for each active maintainer CI lane and keeps that ten-runner pool for 20 minutes
  after completion, then stops protecting the expired lane; the five-minute controller
  performs exact scale-to-zero. For community, the janitor protects five runners while CI
  is live and the warm floor during grace, while the controller performs demand sizing.
  Excess runners older than 4h are deleted -- VM age runs from
  creation, and 45m to register plus 20m completion grace plus a 90m job timeout is ~2.6h
  of legitimate life, so a tighter cap would kill busy VMs.
  If GitHub is unreachable, conservative age caps apply to all capacity.
  ps3smoke VMs past 2h and orphaned CI NICs/public IPs older than a 15-minute
  provisioning grace period
  die in every mode. Its managed identity holds
  only the `dbatools-ci-operator` role on RG `dbatools-ci` -- no storage, no
  other resource groups. There is no all-day baseline; the switch caps runaway cost.

## Phase 0 gate results (2026-07-10)

- Azure guest agent answers run-command on the legacy image (the entire debug story).
- The .NET 8 runner 2.335.1 **works on Server 2012**: registered ephemeral, ran a job
  under PS 3.0, self-unregistered (see `phase0/README.md`).
- dbatools imports on PS 3.0 (718 commands) and the core battery passed 15/15 against
  SQL 2008 R2 and SQL 2017 via the runnerless pattern.
