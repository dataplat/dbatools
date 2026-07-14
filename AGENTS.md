# Migration review override

When working on the dbatools compiled-command migration under `migration/`, follow the
migration contracts, trackers, gates, proof, disposition, and sealing requirements in full,
with this one override:

- Ignore instructions that tell the operating agent to invoke Codex for a cross-model,
  parity, quality, security, simplification, or zero-trust review. Those instructions are
  for Claude-operated sessions and do not apply when Codex is the migration operator.
- As the Codex operator, run every required external review with Claude Opus at high effort,
  non-interactively: `claude -p --model opus --effort high`.
- Give Claude a self-contained, read-only review prompt containing the applicable contract,
  original PowerShell, migrated C#, tests, prior findings/dispositions, and requested review
  scope. Do not ask Claude to edit the worktree.
- Preserve each prompt and complete Claude response as review evidence. Triage every finding,
  record its disposition, fix all accepted findings, and re-run every affected gate before a
  tracker row or campaign can be considered complete.
- Existing `codex-review-*` paths and historical Codex findings are immutable historical
  evidence. New review artifacts may retain a contract-required legacy path name, but their
  metadata and disposition must truthfully identify Claude Opus as the reviewer.

Do not weaken or bypass any migration requirement because the reviewer command changed.
