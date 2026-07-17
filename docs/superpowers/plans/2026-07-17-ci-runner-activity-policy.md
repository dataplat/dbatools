# CI Runner Activity Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make ordinary `potatoqualitee` pushes unable to acquire Azure runners while preserving PR CI, adding `[do ci]` opt-in CI, revising pool retention, and proving the controller boundary live.

**Architecture:** Extract deterministic policy decisions into a dot-sourceable PowerShell file. The default-branch controller consumes GitHub event/run data, applies that policy before Azure login effects, and dispatches marked commits exactly once. Workflow-level filtering reduces noise but the controller remains authoritative for old branch workflows.

**Tech Stack:** PowerShell 7, Pester 6, GitHub Actions YAML, GitHub REST API through `gh`, Azure CLI, and PSScriptAnalyzer.

## Global Constraints

- Leave `C:\github\dbatools` checked out on `libmigration`; use the isolated `C:\github\dbatools\scripts\ci-runner-policy` worktree.
- Never force-push.
- Push the development result fast-forward-only to `development`.
- Do not push or modify `libmigration` until lane A receives its heads-up and the user gives the go.
- `potatoqualitee` ordinary pushes request zero runners; PR activity and `[do ci]` request ten.
- `andreasjordan` and `niphlod` independently request ten for one hour after activity or while CI is live.
- Community CI requests five through 20 minutes after its final run completes.
- The hard maximum is 35; no qualifying activity means zero.
- `(do <cmd>)` and `[do ci]` are compatible, unrelated markers.
- Live proof from an unmarked old-branch push is mandatory before declaring development validated.

---

### Task 1: Pure runner policy

**Files:**
- Create: `.github/runners/runner-policy.ps1`
- Create: `.github/runners/tests/runner-policy.Tests.ps1`

**Interfaces:**
- Produces: `Test-CiMarker`, `Get-PushHeadMessage`, `Test-CiRunEligible`, `Get-DesiredRunnerPools`, and `Get-MarkedPushDispatch`.
- Consumes: GitHub event and workflow-run objects, with no Azure or GitHub calls.

- [ ] **Step 1: Write failing marker and potato-boundary tests**

Create Pester tests that dot-source the not-yet-existing policy file and assert:

```powershell
It "matches the runner marker case-insensitively" {
    Test-CiMarker -Message "work complete [DO CI]" -Marker "[do ci]" | Should -BeTrue
}

It "does not activate potato from an ordinary old-branch push dispatch" {
    $splatPolicy = @{
        Events                  = @($ordinaryPotatoPush)
        WorkflowRuns            = @()
        Maintainers             = @("potatoqualitee", "andreasjordan", "niphlod")
        OptInPushUsers          = @("potatoqualitee")
        MaintainerCount         = 10
        MaintainerWindowMinutes = 60
        CommunityCount          = 5
        CommunityGraceMinutes   = 20
        MaxRunners              = 35
        Marker                  = "[do ci]"
        Now                     = $now
        DirectTriggerActor      = "potatoqualitee"
        DirectTriggerMessage    = ""
    }
    $result = Get-DesiredRunnerPools @splatPolicy
    $result.potatoqualitee | Should -Be 0
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```powershell
Invoke-Pester -Path .github/runners/tests/runner-policy.Tests.ps1 -Output Detailed
```

Expected: failure because `.github/runners/runner-policy.ps1` or its functions do not exist.

- [ ] **Step 3: Implement marker, event, and run eligibility**

Implement:

```powershell
function Test-CiMarker {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Message,
        [Parameter(Mandatory)]
        [string]$Marker
    )

    -1 -ne $Message.IndexOf($Marker, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-PushHeadMessage {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Event)

    $head = [string]$Event.payload.head
    $headCommit = @($Event.payload.commits | Where-Object { [string]$PSItem.sha -eq $head } | Select-Object -First 1)
    if ($headCommit) {
        return [string]$headCommit[0].message
    }
    if ($Event.payload.head_commit) {
        return [string]$Event.payload.head_commit.message
    }
    return [string](@($Event.payload.commits)[-1].message)
}
```

`Test-CiRunEligible` must always accept non-opt-in actors and PR events; an opt-in actor's push or workflow-dispatch run is eligible only when its head/input message contains the marker.

- [ ] **Step 4: Add failing pool-policy tests**

Cover:

```powershell
It "activates potato for a marked push" { ... expected 10 ... }
It "activates potato for PR synchronize activity without a marker" { ... expected 10 ... }
It "retains potato while eligible CI is live" { ... expected 10 ... }
It "activates andreasjordan independently for sixty minutes" { ... }
It "activates niphlod independently for sixty minutes" { ... }
It "shares five community runners while CI is live" { ... }
It "retains community for nineteen minutes after completion" { ... expected 5 ... }
It "expires community at twenty minutes after completion" { ... expected 0 ... }
It "returns zero for every pool without activity" { ... }
It "permits the complete thirty-five runner allocation" { ... expected sum 35 ... }
It "rejects policy totals above the hard maximum" { ... Should -Throw ... }
```

- [ ] **Step 5: Run the expanded tests and verify RED**

Expected: failures for the not-yet-implemented pool behavior.

- [ ] **Step 6: Implement `Get-DesiredRunnerPools` minimally**

The function must:

```powershell
$maintainerCutoff = $Now.AddMinutes(-$MaintainerWindowMinutes)
$communityCutoff = $Now.AddMinutes(-$CommunityGraceMinutes)
$eligibleRuns = @($WorkflowRuns | Where-Object {
        Test-CiRunEligible -Run $PSItem -OptInPushUsers $OptInPushUsers -Marker $Marker
    })
$liveRuns = @($eligibleRuns | Where-Object { $PSItem.status -ne "completed" })
```

For opt-in push users, a direct trigger without a marker must not count. PR events remain qualifying. Community retention comes only from live or recently completed eligible CI, not arbitrary repository pushes.

- [ ] **Step 7: Add failing marked-dispatch deduplication tests**

Cover a marked `potatoqualitee` PushEvent:

```powershell
It "returns the marked branch and SHA when CI has not run" { ... }
It "does not dispatch when a workflow run already has the head SHA" { ... }
It "does not dispatch an unmarked potato push" { ... }
```

- [ ] **Step 8: Implement `Get-MarkedPushDispatch` and verify GREEN**

Return one object containing `Actor`, `Ref`, `Sha`, and `Message` for the newest marked opt-in push without an existing CI run at that SHA; otherwise return `$null`.

Run the focused Pester suite and require zero failures.

---

### Task 2: Controller integration

**Files:**
- Modify: `.github/runners/reconcile-runner-fleet.ps1`
- Test: `.github/runners/tests/runner-policy.Tests.ps1`

**Interfaces:**
- Consumes: pure functions from `.github/runners/runner-policy.ps1`.
- Produces: desired pool hashtable and at-most-once marked workflow dispatch before Azure capacity reconciliation.

- [ ] **Step 1: Add failing controller-input coverage**

Add tests for the exact environment-derived policy:

```powershell
$envPolicy = @{
    Maintainers             = @("potatoqualitee", "andreasjordan", "niphlod")
    OptInPushUsers          = @("potatoqualitee")
    MaintainerCount         = 10
    MaintainerWindowMinutes = 60
    CommunityCount          = 5
    CommunityGraceMinutes   = 20
    MaxRunners              = 35
    Marker                  = "[do ci]"
}
```

Expected RED until the controller exposes the matching inputs to the pure function.

- [ ] **Step 2: Dot-source policy and replace `Get-DesiredPools` logic**

Download `runner-policy.ps1` beside the controller in workflows, then dot-source it:

```powershell
. $env:POLICY_PATH
```

Read explicit environment values, fetch repository events and `ci-azure` workflow runs once, call `Get-DesiredRunnerPools`, and preserve the existing maximum check and logging.

- [ ] **Step 3: Add marked-CI dispatch**

Call `Get-MarkedPushDispatch` using the same event/run snapshot. When it returns an object, use `WORKFLOW_TOKEN` to POST:

```text
repos/<repo>/actions/workflows/ci-azure.yml/dispatches
```

with `ref=<branch>` and `inputs.message=<marked head message>`. Never use the runner-registration PAT for this write. Existing runs at the same SHA suppress dispatch.

- [ ] **Step 4: Run policy tests and PowerShell parser validation**

Run:

```powershell
Invoke-Pester -Path .github/runners/tests/runner-policy.Tests.ps1 -Output Detailed
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path .github/runners/reconcile-runner-fleet.ps1),
    [ref]$null,
    [ref]$errors
) | Out-Null
if ($errors) { throw ($errors | Out-String) }
```

Expected: all policy tests pass and parser reports no errors.

---

### Task 3: Workflow authorization and controller schedule

**Files:**
- Modify: `.github/workflows/ci-azure.yml`
- Modify: `.github/workflows/runner-boost.yml`
- Modify: `.github/workflows/runner-reconcile.yml`
- Modify: `.github/workflows/runner-scale-up.yml`

**Interfaces:**
- Produces: cheap workflow authorization before any self-hosted job is requested.
- Consumes: `[do ci]`, PR event identity, explicit committed pool settings.

- [ ] **Step 1: Add a GitHub-hosted authorization job to `ci-azure`**

The job emits `run-ci=true` for:

- every PR;
- every actor except `potatoqualitee`;
- a `potatoqualitee` push/workflow dispatch whose effective message contains `[do ci]` case-insensitively.

The self-hosted matrix job must declare `needs: authorize` and:

```yaml
if: needs.authorize.outputs.run-ci == 'true'
```

An unmarked potato push can create a cheap workflow run but cannot queue a self-hosted job.

- [ ] **Step 2: Gate the new `runner-boost` workflow**

Keep all configured maintainer pushes automatic except `potatoqualitee`. For potato, exit successfully before dispatch unless the head commit contains `[do ci]` case-insensitively. Pass `boost_user`, `boost_message`, `boost_sha`, and `boost_ref` to reconciliation.

- [ ] **Step 3: Make reconciliation settings explicit**

Set in both reconciliation and manual recovery:

```yaml
MAX_RUNNERS: 35
COMMUNITY_COUNT: 5
COMMUNITY_GRACE_MINUTES: 20
BOOST_USERS: potatoqualitee andreasjordan niphlod
BOOST_COUNT: 10
BOOST_HOURS: 1
OPT_IN_PUSH_USERS: potatoqualitee
CI_MARKER: "[do ci]"
```

Add `actions: write`, `WORKFLOW_TOKEN`, `POLICY_PATH`, and the new dispatch inputs. Download `runner-policy.ps1` with the controller and bootstrap scripts.

- [ ] **Step 4: Tighten reconciliation timing**

Change the normal cron to:

```yaml
- cron: "*/5 * * * *"
```

Retain the Monday 07:00 UTC spend report and add `workflow_run: completed` so completed runs are observed immediately before the grace window begins.

- [ ] **Step 5: Parse all changed workflow YAML**

Use an available YAML parser to load each changed file and fail on syntax errors. Also run:

```powershell
pwsh .github/scripts/Test-GitHubActionsPins.ps1
```

Expected: YAML loads successfully and action pin validation passes.

---

### Task 4: Janitor and documentation

**Files:**
- Modify: `.github/runners/janitor-runbook.ps1`
- Modify: `.github/runners/README.md`

**Interfaces:**
- Produces: Azure-side ceiling consistent with 35 and operator documentation consistent with controller policy.

- [ ] **Step 1: Update janitor policy**

Change maintainer membership to include `niphlod`, change the activity window to one hour, ignore unmarked potato pushes, stop treating arbitrary community pushes as retained CI, and change the capacity warning threshold/message from 25 to 35. Preserve the conservative unreachable-mode behavior.

- [ ] **Step 2: Update README policy, flow, and cost guardrails**

Document 10/10/10/5 pools, one-hour maintainer retention, 20-minute community grace, five-minute reconciliation, 35 maximum, and the temporary potato opt-in.

Add exactly this distinction:

> `(do <cmd>)` selects CI tests (the existing campaign convention); `[do ci]` activates the runner pool. They are compatible and unrelated.

- [ ] **Step 3: Run parser, analyzer, and diff checks**

Run PowerShell parser validation for every changed `.ps1`, targeted PSScriptAnalyzer excluding pre-existing findings only when documented, and `git diff --check`.

---

### Task 5: Development verification and deployment

**Files:**
- Modify: `docs/superpowers/specs/2026-07-17-ci-runner-activity-policy-design.md`
- Modify: `docs/superpowers/plans/2026-07-17-ci-runner-activity-policy.md`

- [ ] **Step 1: Run the complete local gate**

Require fresh successful output from:

```powershell
Invoke-Pester -Path .github/runners/tests/runner-policy.Tests.ps1 -Output Detailed
pwsh .github/scripts/Test-GitHubActionsPins.ps1
git diff --check origin/development...HEAD
```

Parse every changed PowerShell and YAML file and inspect `git diff --stat` plus `git diff`.

- [ ] **Step 2: Consolidate into one focused development commit**

Amend the design commit so the final development history contains one focused CI policy commit. Use a message that contains the existing test-target convention but does not contain `[do ci]`, for example:

```text
CI - Make potato branch pushes opt in and revise runner retention

(do ci-azure)
```

The absence of `[do ci]` is intentional: the deployment push itself is the first unmarked authorization check.

- [ ] **Step 3: Refresh and require fast-forward**

Run:

```powershell
git fetch origin development
git rebase origin/development
git merge-base --is-ancestor origin/development HEAD
```

Re-run the complete local gate after any rebase. Never force-push.

- [ ] **Step 4: Push directly to development**

Run:

```powershell
git push origin HEAD:development
```

Expected: fast-forward success.

- [ ] **Step 5: Mandatory live controller proof**

Observe the unmarked development push and an unmarked old-branch `libmigration` campaign push. Inspect:

- the `ci-azure` authorization job;
- the `runner-reconcile` run and logs;
- desired pool output showing `potatoqualitee=0`;
- no queued/running job bearing `dbatools-pool-potatoqualitee`;
- no Azure/GitHub runner acquired for the potato pool.

If no campaign push arrives in the observation window, request explicit permission before making a no-op unmarked proof commit. Workflow creation without runner acquisition is the expected result.

- [ ] **Step 6: Stop at the coordinator handoff**

Report exactly:

> development validated, ready for libmigration

Do not create or push the libmigration backport yet.

---

### Task 6: Held libmigration backport after explicit go

**Files:**
- Add to `libmigration`: the 21 Azure CI files from the development policy commit's parent.
- Cherry-pick: the focused development CI policy commit.

- [ ] **Step 1: Wait for lane A heads-up and explicit user go**

No libmigration worktree, commit, or push before this gate.

- [ ] **Step 2: Create a second isolated worktree from refreshed `origin/libmigration`**

Leave the shared checkout unchanged.

- [ ] **Step 3: Commit the exact pre-policy baseline**

Restore the 21 CI paths from `<development-policy-commit>^` and commit:

```text
CI: baseline Azure runner infrastructure from development
```

- [ ] **Step 4: Cherry-pick the focused policy commit**

Require a clean cherry-pick. Resolve nothing by silently dropping policy or branch content.

- [ ] **Step 5: Verify and push fast-forward-only**

Run the complete local gate, verify CI path equality with development, refresh
`origin/libmigration`, and push without force. The resulting history must be exactly
the baseline commit followed by the policy commit.
