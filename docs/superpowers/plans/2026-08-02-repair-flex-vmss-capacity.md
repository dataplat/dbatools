# Restore Full Maintainer Runner Pools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every active maintainer CI run ten actual Azure VMs, retain all ten for 20 minutes after completion, then scale the lane directly to zero.

**Architecture:** Restore fixed ten-runner sizing for maintainer lanes in the pure policy while keeping community demand sizing. Align the workflow, janitor, and operator documentation to the 20-minute maintainer completion grace, then repair Flexible VMSS nominal capacity before scale-out so a target of ten means ten actual VMs.

**Tech Stack:** PowerShell 7 controller runtime, PowerShell v3-compatible policy syntax, Pester 6, Azure CLI, GitHub Actions.

## Global Constraints

- Preserve unrelated comments exactly.
- Use double-quoted PowerShell strings and aligned hashtables.
- Do not introduce `::new()` or PowerShell v5-only syntax.
- A maintainer lane targets exactly 10 while eligible CI is starting or live and for exactly 20 minutes after completion, then 0.
- `WARM_FLOOR` applies only to the community lane.
- Keep `MAX_RUNNERS=35` as the target ceiling.
- Do not add Azure credentials or a `pull_request` trigger to `runner-reconcile.yml`.
- The PR provides deterministic regression coverage; live Azure validation occurs only after merge to `development`.

---

### Task 1: Restore fixed maintainer sizing and 20-minute completion grace

**Files:**
- Modify: `.github/runners/tests/runner-policy.Tests.ps1`
- Modify: `.github/runners/runner-policy.ps1`

**Interfaces:**
- Consumes: eligible workflow runs, maintainer activity, `MaintainerCount=10`, `MaintainerWindowMinutes=20`, pending demand, and `WarmFloor`.
- Produces: `Get-DesiredRunnerPools` returning 10 for active/recently-completed maintainer CI and 0 after the grace; community behavior remains demand-driven.

- [ ] **Step 1: Change maintainer regression expectations before production code**

Replace the demand-sized maintainer expectations with these behaviors:

```powershell
It "keeps all ten runners for a live maintainer lane regardless of pending demand" {
    $run = New-CiRun -Actor "andreasjordan" -Status "in_progress" -UpdatedAt $script:Now
    $splatDemand = @{
        WorkflowRuns  = @($run)
        PoolJobDemand = @{ andreasjordan = 3 }
        WarmFloor     = 0
    }
    $result = Invoke-TestPolicy @splatDemand
    $result.andreasjordan | Should -Be 10
}

It "retains all ten maintainer runners nineteen minutes after CI completion" {
    $run = New-CiRun -Actor "andreasjordan" -Status "completed" -UpdatedAt $script:Now.AddMinutes(-19)
    $result = Invoke-TestPolicy -WorkflowRuns @($run) -WarmFloor 0
    $result.andreasjordan | Should -Be 10
}

It "drops a maintainer lane to zero twenty minutes after CI completion" {
    $run = New-CiRun -Actor "andreasjordan" -Status "completed" -UpdatedAt $script:Now.AddMinutes(-20)
    $result = Invoke-TestPolicy -WorkflowRuns @($run) -WarmFloor 10
    $result.andreasjordan | Should -Be 0
}
```

Set the test helper's `MaintainerWindowMinutes` to 20. Retain the cold-lane and community demand tests.

- [ ] **Step 2: Run the focused tests and verify RED**

```powershell
Import-Module Pester -RequiredVersion 6.0.0
Invoke-Pester -Path ".github/runners/tests/runner-policy.Tests.ps1" -FullNameFilter "*Get-DesiredRunnerPools*" -Output Detailed
```

Expected: the live three-job case returns 3 instead of 10, and completed maintainer CI is not retained for the required grace.

- [ ] **Step 3: Implement fixed maintainer sizing**

For each maintainer, treat eligible non-completed CI as live and eligible completed CI updated after the cutoff as recently completed. Return `MaintainerCount` when recent activity, live CI, recently completed CI, or a direct trigger makes the lane active; otherwise return zero. Do not consult pending demand or `WarmFloor` for maintainer sizing.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run the Step 2 command. Expected: all `Get-DesiredRunnerPools` tests pass.

- [ ] **Step 5: Run the full fleet suite and commit**

```powershell
Invoke-Pester -Path ".github/runners/tests" -Output Detailed
```

Expected: all tests pass with zero failures.

Commit subject:

```text
runner fleet - Restore full maintainer pool sizing

(do none)
```

### Task 2: Align the workflow, janitor, and operator documentation

**Files:**
- Modify: `.github/workflows/runner-reconcile.yml`
- Modify: `.github/runners/reconcile-runner-fleet.ps1`
- Modify: `.github/runners/janitor-runbook.ps1`
- Modify: `.github/runners/tests/janitor-runbook.Tests.ps1`
- Modify: `.github/runners/README.md`

**Interfaces:**
- Consumes: the fixed maintainer policy from Task 1.
- Produces: workflow input `BOOST_MINUTES=20`, janitor preservation of ten VMs for live/recently-completed maintainer CI, and matching documentation.

- [ ] **Step 1: Add a failing janitor regression**

Add a real runbook-policy fixture with one completed maintainer CI run whose `updated_at` is 19 minutes old, ten matching VMs older than the deletion cap, and no live run. Execute the runbook and assert that none of the ten maintainer VMs are removed.

- [ ] **Step 2: Run the janitor test and verify RED**

```powershell
Import-Module Pester -RequiredVersion 6.0.0
Invoke-Pester -Path ".github/runners/tests/janitor-runbook.Tests.ps1" -Output Detailed
```

Expected: the old runbook does not preserve all ten VMs for recently completed maintainer CI.

- [ ] **Step 3: Align workflow and janitor behavior**

In `runner-reconcile.yml`, replace `BOOST_HOURS: 1` with `BOOST_MINUTES: 20` and describe fixed ten-runner maintainer lanes plus community-only demand sizing. In the controller, read `BOOST_MINUTES` as `MaintainerWindowMinutes` while retaining `BOOST_HOURS` as a fallback for manual compatibility.

In `janitor-runbook.ps1`, use a 20-minute maintainer cutoff, recognize eligible completed maintainer runs updated after that cutoff, and assign `maintainerPoolSize` to every active maintainer. Keep community live/floor behavior unchanged.

- [ ] **Step 4: Update operator documentation**

Update `.github/runners/README.md` so every scaling description states that active maintainer CI gets ten runners, remains at ten for 20 minutes after completion, then scales to zero; community remains demand-sized with its existing grace and floor.

- [ ] **Step 5: Run the full fleet suite and commit**

```powershell
Invoke-Pester -Path ".github/runners/tests" -Output Detailed
```

Expected: all tests pass with zero failures.

Commit subject:

```text
runner fleet - Align maintainer grace and janitor policy

(do none)
```

### Task 3: Repair phantom Flexible VMSS capacity

**Files:**
- Modify: `.github/runners/tests/runner-policy.Tests.ps1`
- Modify: `.github/runners/runner-policy.ps1`
- Modify: `.github/runners/reconcile-runner-fleet.ps1`

**Interfaces:**
- Consumes: nominal VMSS capacity, actual VM inventory count, and the fixed target from Tasks 1-2.
- Produces: `Get-VmssCapacityPlan` and controller application of synchronous normalization followed by asynchronous scale-out.

- [ ] **Step 1: Write the failing capacity-plan regressions**

```powershell
Describe "Get-VmssCapacityPlan" {
    It "repairs phantom capacity before scaling to the requested target" {
        $splatCapacity = @{
            NominalCapacity = 4
            ActualCapacity  = 0
            TargetCapacity  = 1
        }
        @(Get-VmssCapacityPlan @splatCapacity) | Should -Be @(0, 1)
    }

    It "repairs a partial allocation before filling the requested target" {
        $splatCapacity = @{
            NominalCapacity = 10
            ActualCapacity  = 6
            TargetCapacity  = 10
        }
        @(Get-VmssCapacityPlan @splatCapacity) | Should -Be @(6, 10)
    }

    It "does nothing when actual capacity already satisfies the target" {
        $splatCapacity = @{
            NominalCapacity = 1
            ActualCapacity  = 1
            TargetCapacity  = 1
        }
        @(Get-VmssCapacityPlan @splatCapacity) | Should -BeNullOrEmpty
    }
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

```powershell
Import-Module Pester -RequiredVersion 6.0.0
Invoke-Pester -Path ".github/runners/tests/runner-policy.Tests.ps1" -FullNameFilter "*Get-VmssCapacityPlan*" -Output Detailed
```

Expected: failure because `Get-VmssCapacityPlan` is not defined.

- [ ] **Step 3: Implement the pure capacity plan**

```powershell
function Get-VmssCapacityPlan {
    [CmdletBinding()]
    param(
        [ValidateRange(0, 35)]
        [int]$NominalCapacity,
        [ValidateRange(0, 35)]
        [int]$ActualCapacity,
        [ValidateRange(0, 35)]
        [int]$TargetCapacity
    )

    if ($NominalCapacity -gt $ActualCapacity) {
        $ActualCapacity
    }
    if ($ActualCapacity -lt $TargetCapacity) {
        $TargetCapacity
    }
}
```

- [ ] **Step 4: Apply the plan in the controller**

Calculate `$actualCapacity = $state.Vms.Count`. Apply a normalization capacity without `--no-wait`, then apply a capacity greater than actual with `--no-wait`. Run the existing 15-attempt provisioning poll whenever actual capacity is below target.

- [ ] **Step 5: Run the full fleet suite and commit**

```powershell
Invoke-Pester -Path ".github/runners/tests" -Output Detailed
```

Expected: all tests pass with zero failures.

Commit subject:

```text
runner fleet - Repair phantom Flexible VMSS capacity

(do none)
```

### Task 4: Verify and publish

**Files:**
- Review all branch changes against this plan and the approved design.

**Interfaces:**
- Consumes: Tasks 1-3.
- Produces: a pushed `codex/repair-flex-vmss-capacity` branch and draft pull request targeting `development`.

- [ ] **Step 1: Run fresh verification**

Parse every changed PowerShell file, run `git diff --check`, and run `.github/runners/tests` with Pester 6.

- [ ] **Step 2: Push and create a draft PR**

Use a plain descriptive PR title without `(do ...)`. The PR body must explain the policy rollback, phantom-capacity root cause, validation, and that the credentialed live canary occurs after merge.
