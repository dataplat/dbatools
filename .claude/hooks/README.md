# dbatools Claude Code hooks

Quality and safety gates that run automatically during Claude Code sessions.
They work identically on **Windows and Linux**: Claude Code executes hook
commands through Git Bash on Windows and bash on Linux, so every hook here is
a bash script. No WSL required.

**Every hook fails open.** A missing tool never breaks a session — it just
silently removes that one protection. Run the doctor to see what's active on
your machine:

```bash
bash .claude/hooks/hooks-doctor.sh
```

## What runs when

| Event | Hook | What it does | Needs |
|---|---|---|---|
| Before Write/Edit | `pre-write-snapshot-baseline.sh` | snapshots a file's pre-write content on first touch (per-session diff baseline for review gates); passive, never blocks | JSON tool* |
| Before Write/Edit | `pre-write-style.sh` → `validate-style.ps1` | dbatools style rules on `*.ps1` content (no backticks, double quotes, splats, hashtable alignment, PS v3 compat...) | any PowerShell |
| Before Write/Edit | `pre-edit-read-check.sh` | blocks editing a file that wasn't Read this session | JSON tool* |
| Before Bash | `pre-bash-guard.sh` | blocks destructive commands (force push, reset --hard, clean -f, --no-verify, catastrophic rm...) | JSON tool* |
| Before Bash | `pre-bash-commit-do.sh` | commit messages must carry the `(do CommandName)` CI targeting pattern | JSON tool* |
| Before Bash | `pre-bash-pwsh-script.sh` | long/multi-line inline `-Command` PowerShell must be a `.ps1` run with `-File` (powershell.exe itself is allowed and supported) | JSON tool* |
| After Read | `post-read-track.sh` | records Reads for the read-before-edit gate | JSON tool* |
| After Write/Edit | `post-write-track-session-files.sh` | records this session's writes (scopes the review gates) | JSON tool* |
| Session start (compact/resume) | `session-compact-reset-reads.sh` | resets the Read tracker after compaction | JSON tool* |
| Stop (turn end) | `stop-registration-check.sh` | new `public/*.ps1` must be registered in dbatools.psd1 AND dbatools.psm1 | git |
| Stop | `stop-todo-report.sh` | TODO/FIXME/HACK in changed files must be resolved or explained | git |
| Stop | `stop-no-deflection.sh` | blocks blame-dodging language ("pre-existing", "out of scope"...) | JSON tool* |
| Stop | `stop-verify.sh` | one self-verification checklist round per session when `.ps1` changed | git |
| Stop | `stop-jscpd-ratchet.sh` → `lib-jscpd.js` | blocks NEW copy-paste duplication vs `.jscpd-baseline.json` | node + jscpd + baseline |
| Stop | `stop-codex-review.sh` | external codex review of this session's diff; blocks until `VERDICT: CLEAN` | codex CLI |

\* *JSON tool = first working one of jq, python, python3, py, node. Without
any, parsing-dependent hooks pass silently.*

## The codex auto-review gate

When the turn ends and this session wrote code files, the diff is sent to the
`codex` CLI (read-only sandbox) with a strict reviewer prompt. A
`CHANGES_REQUESTED` verdict blocks the turn so the findings get fixed;
`CLEAN` lets it finish. Cost/loop controls:

- a per-diff **clean cache** — an approved diff is never re-reviewed
- a per-diff **strike budget** (`STOP_GUARD_MAX_BLOCKS`, default 3) — after
  that the gate loudly stands down instead of trapping the session
- **prior-round memory** — the next round verifies fixes instead of
  re-reviewing blind
- a **dispositions ledger** (`.claude/codex-review-dispositions.jsonl`,
  committed and therefore audited) — findings ruled false-positive are
  suppressed in future reviews; ledger edits are themselves reviewed

Watch it live (Stop-hook output is otherwise invisible):

```bash
tail -f ~/.codex-review.live.log
```

No codex installed? The gate silently skips. Install: `npm install -g @openai/codex`, then `codex login`.

## The jscpd duplication ratchet

Opt-in per clone of the repo: it stays dormant until a baseline exists.

```bash
bash .claude/hooks/jscpd-baseline.sh          # records existing duplication
```

From then on, a turn that introduces duplication the baseline doesn't record
is blocked. Refresh with `--force` after intentional duplication or paydown.

The whole ratchet runs on node (which jscpd itself needs anyway) — no Python,
no jq. jscpd 5.x ships a native binary per platform, so a Windows install
can't be shared with WSL: the baseline script auto-installs a platform-local
copy to `~/.dbatools-jscpd` (user-level, no sudo, outside the repo tree — the
repo root ships to the PowerShell Gallery, so `node_modules` must never live
there). See `lib-jscpd.js` for the full resolution order (`$JSCPD_BIN`
override included).

## Per-developer opt-outs

| Scope | How |
|---|---|
| one review round | fix the findings (the point) |
| codex review, this session | `CLAUDE_CODEX_REVIEW=off` |
| verify checklist, this session | `CLAUDE_STOP_VERIFY=off` |
| duplication ratchet, this session | `CLAUDE_JSCPD_RATCHET=off` |
| smaller block budgets | `STOP_GUARD_MAX_BLOCKS=1` |
| everything, permanently, just you | `.claude/settings.local.json` → `{"disableAllHooks": true}` |

`settings.local.json` is gitignored — never edit the checked-in
`settings.json` to opt yourself out.

## Conventions for adding hooks

- Bash launchers, LF line endings (enforced via `.gitattributes`). Heavier
  logic may live in a node engine the launcher invokes (see `lib-jscpd.js`) —
  node is the one scripting runtime present on every supported setup.
- Source `lib-hook-common.sh`; parse hook JSON with `hook_field`, never raw
  grep. Emit JSON with `emit_deny` / `emit_stop_block` / `emit_system_message`.
- Blocking Stop gates go through `stop_guard_emit` (bounded budget) so they
  can never loop forever.
- Wire commands in `settings.json` as
  `bash "$CLAUDE_PROJECT_DIR"/.claude/hooks/<name>.sh` — hooks run in the
  session cwd, so relative paths break.
- Fail open on missing tools; a hook that errors on a clean machine is a bug.
