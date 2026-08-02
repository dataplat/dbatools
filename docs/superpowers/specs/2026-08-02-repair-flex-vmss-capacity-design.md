# Repair Flexible VMSS Phantom Capacity

## Status

Approved on 2026-08-02. The user approved the diagnosed repair and requested a pull request.

## Problem

The Azure-backed GitHub Actions fleet controller compares the requested runner target with the Flexible VMSS `sku.capacity`. Live controller evidence showed `sku.capacity=4` while the actual VM inventory was empty. A one-job target therefore skipped scale-out because the nominal capacity was already greater than the target.

The next ten-runner request exposed the same mismatch from the other direction: scaling nominal capacity from four to ten created only six VMs. The merged demand-driven sizing change made the latent mismatch visible because normal targets are now often one to three instead of ten.

## Requirements

- Use the controller's freshly read VM inventory as the source of truth for actual capacity.
- Clear nominal capacity that is greater than the actual VM count before requesting scale-out.
- Perform the normalization synchronously so the subsequent scale-out is calculated from the repaired baseline.
- Preserve the existing asynchronous scale-out and provisioning wait behavior.
- Preserve busy VMs, pool assignment, the 35-runner hard target ceiling, retry behavior, and all existing comments.
- Add focused regression coverage for both a fully phantom capacity and a partially allocated capacity.
- Do not add credentials or a pull-request trigger to the fleet controller. Live Azure validation remains a post-merge observation because the credentialed workflow executes only the default-branch copy.

## Considered Approaches

### Normalize nominal capacity, then scale to target

When nominal capacity is above actual inventory, first scale nominal capacity down to the actual count and wait for completion. If actual inventory remains below the target, issue the existing asynchronous scale-out to the target.

This is the selected approach. It removes phantom capacity, requests the exact missing number of VMs, and retains the existing hard target ceiling.

### Add the actual deficit to nominal capacity

Request `nominal + (target - actual)`. This would create the missing VM delta, but it deliberately preserves the phantom baseline, can push nominal capacity above the documented ceiling, and risks later over-allocation if delayed capacity materializes.

### Create Flexible VM instances individually

Use standard VM APIs to add instances to the Flexible scale set. This avoids `sku.capacity`, but duplicates the scale-set model and networking configuration in the controller and is much broader than the observed defect requires.

## Design

Add a pure `Get-VmssCapacityPlan` function to `runner-policy.ps1`. It accepts nominal capacity, actual VM count, and target capacity, and emits the ordered capacity values the controller must apply:

- emit actual capacity when nominal capacity is greater than actual capacity;
- emit target capacity when actual capacity is less than target capacity;
- emit nothing when capacity already satisfies the target.

The controller will calculate actual capacity from the final pre-scale `Get-FleetState` snapshot. It will apply a normalization step without `--no-wait`, then retain `--no-wait` for the final scale-out step. The existing post-scale polling loop will run whenever actual capacity was below target.

## Testing

The regression test will execute the real pure planning function with hand-derived fixtures:

- nominal 4, actual 0, target 1 produces capacity steps 0 then 1;
- nominal 10, actual 6, target 10 produces capacity steps 6 then 10;
- nominal 1, actual 1, target 1 produces no steps.

The production controller consumes that plan directly. The full `.github/runners/tests` suite must remain green. After merge, the next credentialed default-branch reconcile log must show nominal and actual capacity converging and the Azure VM inventory reaching the requested target.

## Rollout and Risk

The pull request is safe to review and test without Azure credentials, but it cannot execute the modified credentialed controller. Merge to `development` activates the fix. The next reconcile is the live canary; if Azure rejects normalization, the controller's existing transient-failure handling exits without additional fleet changes and a later reconcile retries.
