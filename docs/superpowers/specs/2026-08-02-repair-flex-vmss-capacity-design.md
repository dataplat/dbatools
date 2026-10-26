# Restore Full Maintainer Runner Pools

## Status

Approved on 2026-08-02. After seeing six real VMs serve a ten-job maintainer matrix, the user explicitly required all three maintainer lanes to receive ten VMs while CI is active and for 20 minutes after completion, then scale to zero, and requested a pull request.

## Problem

PR #10493 introduced demand-sized maintainer pools. That policy reduced a hot maintainer lane to its pending job count and held only `WARM_FLOOR` runners when nothing was pending. The resulting lower targets exposed a second, latent defect: the controller compares the target with Flexible VMSS `sku.capacity`, even when nominal capacity is greater than the actual VM inventory.

Live controller evidence showed two failure modes:

- nominal capacity 4, actual VMs 0, target 1: scale-out was skipped and the job remained queued;
- nominal capacity 4, actual VMs 0, target 10: Azure created only the six-unit nominal delta, leaving four matrix jobs queued.

The required outcome is ten actual VMs for a hot maintainer lane so the ten-job matrix can execute in parallel.

## Requirements

- A lane for `potatoqualitee`, `andreasjordan`, or `niphlod` targets ten runners while eligible CI is starting or live and for 20 minutes after eligible CI completes, regardless of pending-job count or `WARM_FLOOR`.
- A cold maintainer lane still targets zero runners.
- Maintainer lanes have no three-runner warm floor.
- The community lane retains demand-driven sizing up to five and uses `WARM_FLOOR` only while hot with no pending work.
- The independent Azure janitor preserves ten runners for every hot maintainer lane, including recent activity with no live run.
- Use the controller's freshly read VM inventory as the source of truth for actual capacity.
- Clear nominal capacity that is greater than the actual VM count before requesting scale-out.
- Perform capacity normalization synchronously so the subsequent scale-out is calculated from the repaired baseline.
- Preserve busy VMs, pool isolation, the 35-runner target ceiling, retry behavior, and unrelated comments.
- Update operator documentation and workflow comments so they describe fixed maintainer pools and demand-driven community capacity.
- Do not add credentials or a pull-request trigger to the fleet controller. Live Azure validation remains post-merge because the credentialed workflow executes only the default-branch copy.

## Policy Options Considered

### Ten runners while CI is active and for 20 minutes after completion

This is the selected policy and the user's explicit requirement. It restores full maintainer matrix parallelism, keeps the full pool briefly available for follow-up CI, and then scales directly to zero.

### Set `WARM_FLOOR` to ten

This does not meet the requirement. Pending work would still reduce a lane to the pending count, so a four-job observation could target four instead of ten.

### Keep thirty maintainer VMs online continuously

This guarantees zero cold-start delay but spends continuously even without maintainer activity. The requirement is full capacity for active maintainer lanes, not permanent capacity for cold lanes.

## Capacity Repair Options Considered

### Normalize nominal capacity, then scale to target

When nominal capacity exceeds actual inventory, first scale nominal capacity down to the actual count and wait for completion. If actual inventory remains below target, issue the existing asynchronous scale-out to the target.

This is selected because it removes phantom capacity, requests the exact missing VM count, and retains the existing hard target ceiling.

### Add the actual deficit to nominal capacity

Requesting `nominal + (target - actual)` would create the immediate deficit but preserve phantom capacity, allow nominal capacity to exceed the ceiling, and risk later over-allocation.

### Create Flexible VM instances individually

Using standard VM APIs would avoid `sku.capacity` but duplicate scale-set image and networking configuration in the controller. It is broader than the defect requires.

## Design

`Get-DesiredRunnerPools` will return `MaintainerCount` when an eligible maintainer run is live, when qualifying activity is waiting for its run to appear, or when an eligible completed run was updated within the last 20 minutes. It returns zero afterward. Pending-job demand and `WARM_FLOOR` continue to size only the community lane.

The controller workflow will replace the one-hour maintainer window with a 20-minute window. The janitor will recognize live and recently completed maintainer CI and set every active maintainer entry in `desiredPools` to `maintainerPoolSize`.

A pure `Get-VmssCapacityPlan` function in `runner-policy.ps1` will accept nominal capacity, actual VM count, and target capacity. It emits actual capacity when nominal exceeds actual, then emits target when actual is below target. The controller applies normalization without `--no-wait`, applies final scale-out with `--no-wait`, and retains its existing provisioning poll.

## Testing

Focused Pester regressions will prove:

- a live maintainer with three pending jobs still targets ten;
- a maintainer remains at ten for nineteen minutes after CI completion;
- a maintainer drops to zero at twenty minutes after CI completion;
- a cold maintainer remains zero;
- the janitor preserves ten recently active maintainer VMs without a live run;
- nominal/actual/target `4/0/1` produces capacity steps `0,1`;
- nominal/actual/target `10/6/10` produces capacity steps `6,10`;
- healthy `1/1/1` capacity produces no scale steps.

The production controller consumes the tested policy and capacity plan directly. The full `.github/runners/tests` suite must remain green.

## Rollout

The PR verifies deterministic policy and capacity planning without Azure credentials. Merge to `development` activates both changes. The next credentialed reconcile is the live canary and must report a ten-runner maintainer target with actual VM inventory converging to ten.
