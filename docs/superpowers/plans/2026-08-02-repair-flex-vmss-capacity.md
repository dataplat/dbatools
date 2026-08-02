# Repair Flexible VMSS Phantom Capacity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Azure runner controller replace phantom Flexible VMSS capacity with the actual VM count before scaling to its requested target.

**Architecture:** Keep capacity planning pure in `runner-policy.ps1`, where hand-derived regression fixtures can execute without Azure credentials. Make `reconcile-runner-fleet.ps1` apply the returned capacity steps synchronously for normalization and asynchronously for final scale-out, retaining its existing provisioning poll.

**Tech Stack:** PowerShell 7 controller runtime, PowerShell v3-compatible policy syntax, Pester 6, Azure CLI, GitHub Actions.

## Global Constraints

- Preserve every existing comment exactly.
- Use double-quoted PowerShell strings and aligned hashtables.
- Do not introduce `::new()` or PowerShell v5-only syntax.
- Keep `MAX_RUNNERS=35` as the target ceiling.
- Do not add Azure credentials or a `pull_request` trigger to `runner-reconcile.yml`.
- The PR provides deterministic regression coverage; live Azure validation occurs only after merge to `development`.

---

### Task 1: Add the phantom-capacity regression and pure plan

**Files:**
- Modify: `.github/runners/tests/runner-policy.Tests.ps1`
- Modify: `.github/runners/runner-policy.ps1`

**Interfaces:**
- Consumes: integer nominal VMSS capacity, actual VM count, and target capacity.
- Produces: `Get-VmssCapacityPlan -NominalCapacity <int> -ActualCapacity <int> -TargetCapacity <int>`, emitting an ordered sequence of integer capacity values.

- [ ] **Step 1: Write the failing regression test**

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
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```powershell
Import-Module Pester -RequiredVersion 6.0.0
Invoke-Pester -Path ".github/runners/tests/runner-policy.Tests.ps1" -FullNameFilter "*Get-VmssCapacityPlan*" -Output Detailed
```

Expected: failure because `Get-VmssCapacityPlan` is not defined.

- [ ] **Step 3: Implement the minimal pure capacity plan**

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

- [ ] **Step 4: Add the partial-allocation and healthy-capacity fixtures**

```powershell
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
```

- [ ] **Step 5: Run the focused test and verify GREEN**

Run the Step 2 command. Expected: all `Get-VmssCapacityPlan` cases pass.

### Task 2: Apply the capacity plan in the real controller

**Files:**
- Modify: `.github/runners/reconcile-runner-fleet.ps1:599`

**Interfaces:**
- Consumes: `Get-VmssCapacityPlan` from the downloaded `runner-policy.ps1` and the final pre-scale `Get-FleetState` inventory.
- Produces: synchronous nominal-capacity normalization followed by the existing asynchronous scale-out and provisioning poll.

- [ ] **Step 1: Calculate actual capacity and request the plan**

```powershell
$actualCapacity = $state.Vms.Count
$splatCapacityPlan = @{
    NominalCapacity = $capacity
    ActualCapacity  = $actualCapacity
    TargetCapacity  = $target
}
$capacityPlan = @(Get-VmssCapacityPlan @splatCapacityPlan)
```

- [ ] **Step 2: Apply normalization synchronously and scale-out asynchronously**

```powershell
foreach ($plannedCapacity in $capacityPlan) {
    $scaleArguments = @(
        "vmss", "scale", "--resource-group", $resourceGroup, "--name", $vmss,
        "--new-capacity", "$plannedCapacity", "--only-show-errors", "--output", "none"
    )
    $operation = "normalize VMSS capacity to $plannedCapacity actual VM(s)"
    if ($plannedCapacity -gt $actualCapacity) {
        $scaleArguments += "--no-wait"
        $operation = "scale VMSS to $plannedCapacity"
    }
    $null = Invoke-NativeText -Tool "az" -Arguments $scaleArguments -Operation $operation
}
```

- [ ] **Step 3: Preserve the existing provisioning poll**

```powershell
if ($actualCapacity -lt $target) {
    foreach ($attempt in 1..15) {
        Start-Sleep -Seconds 20
        $state = Get-FleetState
        $notReady = @($state.Vms | Where-Object provisioning -NE "Succeeded").Count
        if ($state.Vms.Count -ge $target -and $notReady -eq 0) {
            break
        }
        Write-Host "provisioning check $attempt of 15: vms=$($state.Vms.Count)/$target not_ready=$notReady"
    }
}
```

- [ ] **Step 4: Run the full fleet suite**

```powershell
Import-Module Pester -RequiredVersion 6.0.0
Invoke-Pester -Path ".github/runners/tests" -Output Detailed
```

Expected: 53 tests pass, zero fail.

### Task 3: Verify and publish

**Files:**
- Review all modified files with `git diff --check` and `git diff`.

**Interfaces:**
- Consumes: the completed controller and regression coverage.
- Produces: a pushed `codex/repair-flex-vmss-capacity` branch and draft pull request targeting `development`.

- [ ] **Step 1: Run syntax and full focused verification**

Parse both modified PowerShell files and rerun `.github/runners/tests` with Pester 6.

- [ ] **Step 2: Commit with the repository CI marker**

```text
runner fleet - Repair phantom Flexible VMSS capacity

(do none)
```

- [ ] **Step 3: Push and create a draft PR**

Use a plain descriptive PR title without a `(do ...)` marker. Explain the live evidence, regression coverage, and that live credentialed validation begins only after merge.
