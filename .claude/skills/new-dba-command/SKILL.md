---
name: new-dba-command
description: Create a BRAND-NEW dbatools command (one with no public/*.ps1 and no bin/retired-index.json entry) — CRUD-gap fills like Set-DbaCredential, SSIS catalog commands, developer DDL, or any DESIGN-*/NEW-* row in migration/trackers/NEW-COMMANDS-TRACKER.md. Use whenever asked to "add a command", "create Set-/New-/Remove-DbaX", "fill the CRUD gap", or when a requested command turns out not to exist. NOT for porting an existing command (that is migration/porting-kit/).
---

# New dbatools Command (designed cmdlet, not a port)

A brand-new command follows a DIFFERENT pipeline than a port, with different laws. The full
digest is **`migration/creation-kit/QUICKSTART.md`** — read it before writing anything.

## 1. Confirm it really is new (30 seconds)

- `public/<Command>.ps1` exists → it's a **port**: use `migration/porting-kit/`, not this.
- Listed in `bin/retired-index.json` → already ported and flipped; nothing to create.
- Otherwise look it up in `migration/data/new-commands-index.json`:
  - `status: catalogued|designed|approved` → work it through
    `migration/trackers/NEW-COMMANDS-TRACKER.md` (one row, one mode per iteration).
  - `status: implemented` → it exists as a satellite cmdlet already.
  - `status: candidate` or **absent** → NOT approved. Do not build it. Add/confirm it in
    `migration/creation-kit/CRUD-GAPS.md §3` and raise it for owner sign-off instead.

## 2. The five rules sessions get wrong without this skill

1. **No .ps1, ever.** New commands are pure C# cmdlets in
   `dbatools.library/project/dbatools.<module>/Commands/`. Never write a PowerShell
   function for one, and never wrap a fresh PS body in a compatibility hop.
2. **Registration override:** register ONLY in `modules/<module>/<module>.psd1`
   `CmdletsToExport`. The repo CLAUDE.md rule "register in dbatools.psd1 + dbatools.psm1"
   applies to PS functions and does NOT apply here.
3. **The designed spec is the law.** No code before `migration/designed/<Command>.json`
   has non-empty `approvedBy`/`approvedDate` (owner-only fields). The surface gate is
   EXACT match — not additive — on both editions.
4. **Tests ship in the same iteration** (parameter contract, verbatim `-WhatIf` strings
   from `shouldProcessTargets`, multi-batch pipeline, lab-role integration, failure
   paths) and are immutable once merged.
5. **DONE needs the gate verdict JSON (designed mode) + an independent cross-model
   review**, then commits to all three repos and a status bump in
   `migration/data/new-commands-index.json`.

## 3. Templates (copy, don't re-derive)

- Cmdlet: `migration/creation-kit/CMDLET-TEMPLATE.cs`
- Designed spec: `migration/creation-kit/DESIGNED-SPEC-TEMPLATE.json`
- Test suite: `migration/creation-kit/TESTS-TEMPLATE.ps1`

Normative order if anything conflicts: `migration/specs/contracts.md` >
`migration/specs/new-commands.md` / `parity-contract.md §7` >
`migration/prompts/new-command-prompt.md` > creation-kit > this skill.
