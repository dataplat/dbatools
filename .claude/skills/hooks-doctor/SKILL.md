---
name: hooks-doctor
description: Diagnose the Claude Code hook environment for this repo — which tools are present, what each absence disables, and how to fix it. Use when hooks error, block unexpectedly, or seem to do nothing.
---

# Hooks Doctor

Run the diagnostic and interpret it for the user:

```bash
bash .claude/hooks/hooks-doctor.sh
```

Present the results conversationally:

1. **All OK** — say the hook environment is fully functional and list the active gates (style validation, read-before-edit, destructive-command guard, registration/TODO/verify Stop gates, codex auto-review, jscpd ratchet if baselined).
2. **Something MISSING** — explain what that specific absence disables (the script prints it) and give the one-line install fix. Every hook fails open, so a missing tool never breaks the session — it just silently removes that protection.
3. **Hook errors in the transcript** — if the user reports `hook error` messages, check:
   - Hook paths in [.claude/settings.json](../../settings.json) must use `"$CLAUDE_PROJECT_DIR"` (hooks run in the session cwd, not the repo root — relative paths break)
   - Line endings: hook scripts must be LF (enforced via `.gitattributes`); CRLF causes `bad interpreter` on Linux
   - `claude --debug hooks` records each hook's exit code and stderr
4. **User wants to opt out** — per-developer opt-outs, in increasing scope:
   - `CLAUDE_CODEX_REVIEW=off` / `CLAUDE_STOP_VERIFY=off` / `CLAUDE_JSCPD_RATCHET=off` (env, per session)
   - `STOP_GUARD_MAX_BLOCKS=1` to shrink blocking budgets
   - `.claude/settings.local.json` with `{"disableAllHooks": true}` (gitignored, personal)

Never suggest editing the checked-in `.claude/settings.json` to opt out — that changes the gates for every developer.
