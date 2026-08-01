# Test Standards Ownership Design

## Goal

Give each repository rule one authoritative home while keeping general PowerShell style active for every source directory and test-specific rules active whenever command behavior or tests change.

## Ownership

- `CLAUDE.md` owns repository-wide PowerShell style for `public/`, `private/`, `tests/`, and scripts.
- `tests/CLAUDE.md` owns ongoing test policy: supported Pester runtime, test structure, real-boundary integration and regression coverage, instance selection, resource management, and assertions.
- `AGENTS.md` and `.github/copilot-instructions.md` are entry points. They direct agents to the two authoritative files and do not maintain competing copies of their rules.

## Consolidation

- Delete `bin/prompts/` and ignore `/bin/prompts/` so generated or local prompt copies cannot return.
- Delete `.github/prompts/style.md` and `.github/prompts/migration.md`.
- Move any still-relevant general style from the deleted files into root `CLAUDE.md`.
- Move any still-relevant ongoing test style into `tests/CLAUDE.md`.
- Drop migration-only advice, including exact preservation of legacy parameter names.

## Pester Version

Pester 6.0.0 is the supported runtime. Existing test files retain `#Requires ... ModuleVersion="5.0"` because it is a minimum-version declaration and `Invoke-ManualPester` currently uses that header to select the Pester 6 execution path. Converting every header and the runner is separate behavior-changing work.

## Integration Coverage

Regression integration tests are expected when they demonstrate changed behavior. The canonical test guide must require real implementation behavior against a separately running boundary and must not discourage adding new integration coverage.

## Verification

- No tracked or referenced `bin/prompts` content remains.
- No references to the deleted style or migration documents remain.
- Root entry points agree on the ownership model.
- General style remains in root `CLAUDE.md`; test-only rules remain in `tests/CLAUDE.md`.
- Stale `$TestConfig.instance*`, `$TestConfig.Instances`, and `$TestConfig.SqlCredential` examples are absent from authoritative agent guidance.
- Changed Markdown links resolve, `git diff --check` passes, and documentation consistency searches pass.
