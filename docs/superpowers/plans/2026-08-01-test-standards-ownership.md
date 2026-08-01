# Test Standards Ownership Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make repository-wide PowerShell style and ongoing Pester test policy authoritative in exactly one file each, then update PR #10485 accordingly.

**Architecture:** Root `CLAUDE.md` owns general PowerShell style for every source directory. `tests/CLAUDE.md` owns ongoing test policy. `AGENTS.md` and Copilot instructions are thin entry points that point to those owners instead of repeating rules.

**Tech Stack:** Markdown, git, PowerShell-based consistency checks, GitHub CLI.

## Global Constraints

- Pester 6.0.0 is the supported runtime.
- Existing test files retain the minimum `ModuleVersion="5.0"` header; runner/header migration is out of scope.
- Real-boundary regression integration tests are valid and required for new or changed command behavior.
- General PowerShell style must apply to `public/`, `private/`, `tests/`, and scripts.
- Do not modify hook behavior.
- Push the verified result to `origin/consolidate-test-style-docs` and comment on PR #10485 as Chrissy's Sol.

---

### Task 1: Establish the two authoritative documents

**Files:**
- Modify: `CLAUDE.md`
- Modify: `tests/CLAUDE.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: Existing general and test guidance from the PR head and the documents being removed.
- Produces: One repository-wide style source and one ongoing test-policy source.

- [ ] **Step 1: Make root style explicitly repository-wide**

State that `CLAUDE.md` applies to all PowerShell under `public/`, `private/`, `tests/`, and scripts. Add the useful general array, multiline-string, and `Where-Object` conventions currently duplicated in test prompt documents. Correct stale `$TestConfig` example properties.

- [ ] **Step 2: Make the test guide ongoing and Pester 6-focused**

Rename the guide for Pester 6, explain why the minimum header remains 5.0, remove migration language and general-style duplication, fix the single-quote warning example, and make real-boundary regression/integration coverage explicit.

- [ ] **Step 3: Make AGENTS an entry point**

Replace duplicated policy with matching pointers: root `CLAUDE.md` for repository-wide style/workflow and `tests/CLAUDE.md` whenever command behavior or tests change.

- [ ] **Step 4: Verify authority boundaries**

Run searches showing general-style ownership in root, test-policy ownership in tests, and no contradictory integration-test wording.

### Task 2: Remove obsolete copies and align entry points

**Files:**
- Modify: `.gitignore`
- Delete: `bin/prompts/pester.md`
- Delete: `bin/prompts/style.md`
- Delete: `.github/prompts/style.md`
- Delete: `.github/prompts/migration.md`
- Modify: `.github/copilot-instructions.md`
- Modify: `.github/CONTRIBUTING-TESTING.md`
- Modify: `.claude/skills/issue/SKILL.md`

**Interfaces:**
- Consumes: The two authoritative documents from Task 1.
- Produces: Entry points and human operational guidance without competing standards copies.

- [ ] **Step 1: Delete obsolete prompt and migration documents**

Remove all four tracked copies and add `/bin/prompts/` to `.gitignore`.

- [ ] **Step 2: Prune Copilot duplication**

Replace inline PowerShell/test standards, stale `$TestConfig` examples, Pester 5 references, and deleted-file references with direct pointers to root `CLAUDE.md` and `tests/CLAUDE.md`.

- [ ] **Step 3: Correct nearby maintained guidance**

Update the contributor testing guide and issue skill to identify Pester 6 and the canonical test guide without adding new normative copies.

- [ ] **Step 4: Verify references**

Search tracked Markdown and agent guidance for deleted paths, stale test-config properties, and stale Pester-version claims.

### Task 3: Verify, commit, publish, and explain

**Files:**
- Modify: `docs/superpowers/plans/2026-08-01-test-standards-ownership.md` only to mark completed checkboxes if useful.

**Interfaces:**
- Consumes: Completed documentation consolidation.
- Produces: Verified commits on the existing PR branch and a maintainer-facing review comment.

- [ ] **Step 1: Run documentation verification**

Run `git diff --check`, validate relative Markdown links in changed files, confirm deleted paths are unreferenced, and inspect the complete diff against `origin/pr-10485`.

- [ ] **Step 2: Commit**

Commit the implementation with a documentation-focused message ending in `(do none)`.

- [ ] **Step 3: Push**

Push `HEAD` to `origin/consolidate-test-style-docs` only after confirming the remote head is still `5a87ca6b8a59d931de4e6ac840356b4e5772c2cd`.

- [ ] **Step 4: Comment on PR #10485**

Post a concise comment identifying the reviewer as “Chrissy's Sol,” listing the original findings, the ownership model, the Pester 6/minimum-header decision, deletions, and verification evidence.
