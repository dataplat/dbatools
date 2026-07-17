# CI Runner Activity Policy Design

## Goal

Reduce Azure VMSS runner cost while preserving automatic CI for pull requests and
contributors. `potatoqualitee` temporarily opts in to branch-push CI with `[do ci]`;
pull requests continue to run automatically.

## Pool policy

| Pool | Size | Activation | Retention |
|---|---:|---|---|
| `potatoqualitee` | 10 | PR activity, live PR CI, or a pushed head commit containing `[do ci]` | While CI is live and for one hour after the latest qualifying activity |
| `andreasjordan` | 10 | Push or PR activity, or live CI | While CI is live and for one hour after the latest qualifying activity |
| `niphlod` | 10 | Push or PR activity, or live CI | While CI is live and for one hour after the latest qualifying activity |
| `community` | 5 | CI requested by any other actor | While CI is live and for 20 minutes after the final CI run completes |

The hard maximum is 35. With no qualifying activity or retained CI, desired capacity
is zero.

## Marker semantics

`[do ci]` is a case-insensitive exact marker in the pushed head commit message. For
`potatoqualitee`, it both activates the dedicated runner pool and runs the existing
`ci-azure` matrix for that commit. Dispatch is deduplicated by commit SHA.

The existing `(do <cmd>)` syntax remains CI test targeting. `[do ci]` controls runner
pool activation. The two markers are compatible and unrelated.

## Controller authority

The controller on `development` is the policy authority. It must reject an ordinary
`potatoqualitee` push even if an old feature branch still contains the former
`runner-boost.yml` and dispatches reconciliation. Workflow filtering is defense in
depth, not the security or cost boundary.

The controller separates pure policy decisions from Azure and GitHub side effects.
Tests exercise the real policy functions with representative GitHub event and workflow
run data; no external-system mock substitutes for the required live validation.

## Timing

Reconciliation runs every five minutes and on existing event-driven nudges. Practical
idle teardown is therefore:

- maintainer pools: 60–65 minutes after latest qualifying activity;
- community pool: 20–25 minutes after the final CI run completes.

Busy runners are never deleted. A live CI run retains its assigned pool even after the
activity window expires.

## Development rollout

Work occurs in an isolated worktree based on `origin/development`; the shared checkout
remains on `libmigration`. The implementation is committed as a focused CI policy
change, refreshed against `origin/development`, and pushed fast-forward-only directly
to `development`. Force push is prohibited.

After the commit lands, live proof is mandatory. Observe an unmarked push from the old
`libmigration` campaign branch (or make an explicitly approved unmarked proof commit),
inspect the resulting reconciliation run, and prove that the `potatoqualitee` pool
remains at zero. Workflow creation alone is not success; the old-branch run must be
unable to acquire runners.

The development phase ends with the exact status:

> development validated, ready for libmigration

## Libmigration hold and backport

Do not push to `libmigration` until the coordinator posts a heads-up to lane A and the
user gives the go.

`libmigration` currently lacks all 21 Azure runner files. In a second isolated worktree:

1. Add the exact pre-policy Azure CI snapshot from the parent of the development policy
   commit as `CI: baseline Azure runner infrastructure from development`.
2. Cherry-pick the focused development policy commit.
3. Verify the resulting CI paths match `development`.
4. Push fast-forward-only after the explicit go.

The intended `libmigration` history is exactly two commits: baseline, then policy.

## Verification

- Pester policy tests cover all four pools, marker matching, dispatch deduplication,
  live-run retention, grace expiry, zero-idle behavior, and the 35-runner cap.
- Workflow YAML parses successfully.
- Changed PowerShell passes syntax validation and targeted PSScriptAnalyzer review.
- The complete diff contains only approved CI policy, tests, documentation, and plan
  artifacts.
- Live GitHub Actions evidence proves an unmarked old-branch potato push cannot acquire
  runners.
