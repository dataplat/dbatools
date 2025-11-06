# GitHub Copilot Code Review Instructions

When reviewing code or writing pull request summaries:

- Apply dbatools PowerShell conventions:
  - No backticks for line continuation
  - Use splats for 3+ parameters
  - Perfectly align hashtables
  - Preserve all comments
  - Use `[Parameter(Mandatory)]` (no `= $true`)
  - PowerShell v3-compatible (`New-Object`, not `::new()`)

- Always mention if code violates the style guide (`CLAUDE.md`).

- When summarizing code changes:
  - Start summaries with the main command or file, e.g. `Get-DbaDatabase - Add recovery model filtering`
  - Avoid listing filenames or diffs — use natural descriptions
  - Keep summaries ≤ 120 words

- When suggesting improvements:
  - Be direct but neutral: "Use splatting for 3+ parameters." (not "Consider using…")
  - Never alter semantics or function names unless explicitly incorrect.

Tone:
- Professional, concise, and technical
- Avoid filler words ("just","simply", "basically")
