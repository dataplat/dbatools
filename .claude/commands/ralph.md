# Generate Ralph Wiggum Automation

Generate a Ralph Wiggum-style iterative automation for large tasks. The Ralph Wiggum technique runs an AI CLI in a stateless loop where each iteration does ONE unit of work, then stops. Progress is tracked via git history and filesystem state.

Supports two AI engines: **Claude CLI** (default) and **GitHub Copilot CLI** (`--type copilot`).

## Task Description

$ARGUMENTS

## CLI Engine Parameters

Parse these from `$ARGUMENTS` if present (flags like `--type copilot --model opus --effort high`):

| Parameter | Values | Default |
|-----------|--------|---------|
| `--type` | `claude`, `copilot` | `claude` |
| `--model` | See model table below | `opus` |
| `--effort` | `low`, `medium`, `high`, `max` | `high` |

### Model Name Mapping

The two CLIs use different model name formats:

| Alias | Claude CLI (`--model`) | Copilot CLI (`--model`) |
|-------|----------------------|------------------------|
| `opus` | `claude-opus-4-6` | `claude-opus-4.6` |
| `sonnet` | `claude-sonnet-4-6` | `claude-sonnet-4.6` |
| `haiku` | `claude-haiku-4-5` | `claude-haiku-4.5` |

### Effort Support

| Engine | Flag | Values | Notes |
|--------|------|--------|-------|
| Claude | `--effort` | `low`, `medium`, `high`, `max` | `max` is Opus-only |
| Copilot | `--reasoning-effort` | `low`, `medium`, `high`, `xhigh` | Map `max` → `xhigh` |

Strip `--type`, `--model`, and `--effort` from `$ARGUMENTS` before processing the task description.

## Modes

This command operates in two modes based on context:

### Mode 1: Wrap Existing Work
If there are **uncommitted changes** or a **recent commit pattern** to follow:
- Analyze the changes to infer task parameters
- Generate wrapper for "more of the same"

### Mode 2: Full Planning
If the user provides a **project description** or asks for a full plan:
- Analyze the entire project/codebase
- Create a comprehensive plan with all work items
- Generate a TRACKER.md with all items as PENDING
- Generate the wiggum wrapper to execute the plan

## Instructions

### Step 1: Determine Mode

Check the arguments and current state:
- If `$ARGUMENTS` describes a project or feature -> **Full Planning Mode**
- If `$ARGUMENTS` is a task name or empty with uncommitted changes -> **Wrap Existing Mode**

### Step 2A: Full Planning Mode

1. **Analyze the project scope**
2. **Create a tracker file** at `docs/trackers/features/{TASK}-TRACKER.md`
3. **Count items** to calculate max iterations: `N + 10`
4. **Generate the prompt and orchestrator**

### Step 2B: Wrap Existing Mode

1. **Analyze current state** via git status/diff
2. **Infer task parameters** from the changes
3. **If ambiguous**, ask the user

### Step 3: Generate Files

#### File 1: `scripts/{task}-prompt.md`

The generated prompt MUST include ALL 8 quality check sections from the "Quality Checks" section below. Copy them verbatim into the prompt — these are the instructions Claude will follow headlessly, so if they're not in the prompt, they won't happen. The quality checks must appear AFTER the work instructions and BEFORE any "mark DONE" step.

#### File 2: `scripts/{task}.ps1`

**CRITICAL**: Set `$MaxIterations` to **item count + 5**.

**Resolve template placeholders** from the parsed CLI parameters:
- `{TYPE}` → `claude` or `copilot` (default: `claude`)
- `{MODEL}` → resolved model name for the chosen engine (use the Model Name Mapping table above; default: `opus` alias → `claude-opus-4-6` for claude, `claude-opus-4.6` for copilot)
- `{EFFORT}` → `low`, `medium`, `high`, or `max` (default: `high`)

Use this template for the PowerShell orchestrator - it streams tool use with file details:

```powershell
#!/usr/bin/env pwsh
param(
    [int]$MaxIterations = {ITEM_COUNT + 10},
    [ValidateSet('claude', 'copilot')]
    [string]$Type = '{TYPE}',
    [string]$Model = '{MODEL}',
    [ValidateSet('low', 'medium', 'high', 'max')]
    [string]$Effort = '{EFFORT}',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$TrackerPath = "/workspace/docs/trackers/features/{TASK}-TRACKER.md"
$PromptPath = "/workspace/scripts/{task}-prompt.md"

# Resolve engine binary
if ($Type -eq 'copilot') {
    $EngineBin = "/home/vscode/.local/bin/copilot"
    if (-not (Test-Path $EngineBin)) {
        Write-Host "ERROR: Copilot CLI not found at $EngineBin" -ForegroundColor Red
        exit 1
    }
} else {
    $EngineBin = "claude"
}

function Get-PendingCount {
    $tracker = Get-Content $TrackerPath -Raw
    return ([regex]::Matches($tracker, '\| PENDING[\s|]')).Count
}

function Get-CompletedCount {
    $tracker = Get-Content $TrackerPath -Raw
    $done = ([regex]::Matches($tracker, '\| DONE[\s|✓]')).Count
    $needsWork = ([regex]::Matches($tracker, '\| NEEDS_WORK[\s|✓]')).Count
    $blocked = ([regex]::Matches($tracker, '\| BLOCKED[\s|✓]')).Count
    return $done + $needsWork + $blocked
}

function Invoke-Iteration {
    param([int]$Iteration)

    Write-Host ""
    Write-Host ("=" * 5) -ForegroundColor Yellow
    Write-Host "  Iteration $Iteration of $MaxIterations ($Type)" -ForegroundColor Yellow
    Write-Host ("=" * 5) -ForegroundColor Yellow

    $prompt = Get-Content $PromptPath -Raw

    if ($Type -eq 'copilot') {
        $engineArgs = @(
            '-p', $prompt
            '--model', $Model
            '--allow-all'
        )
        $copilotEffort = if ($Effort -eq 'max') { 'xhigh' } else { $Effort }
        $engineArgs += @('--reasoning-effort', $copilotEffort)

        if ($DryRun) {
            Write-Host "  [DRY RUN] Would run: copilot $($engineArgs -join ' ')" -ForegroundColor DarkGray
            return $true
        }

        & $EngineBin @engineArgs 2>&1 | ForEach-Object {
            $line = "$PSItem"
            if ($line -and $line -notmatch '^\s*$') {
                Write-Host "  $line" -ForegroundColor White
            }
        }
    } else {
        $sessionId = [guid]::NewGuid().ToString()
        $engineArgs = @(
            '--dangerously-skip-permissions'
            '--session-id', $sessionId
            '--no-session-persistence'
            '--model', $Model
            '--effort', $Effort
            '--verbose'
            '--output-format', 'stream-json'
            '-p', $prompt
        )

        if ($DryRun) {
            Write-Host "  [DRY RUN] Would run: claude $($engineArgs -join ' ')" -ForegroundColor DarkGray
            return $true
        }

        # Stream and parse JSON - show tool use with file details
        & $EngineBin @engineArgs 2>&1 | ForEach-Object {
            $line = $PSItem
            try {
                $obj = $line | ConvertFrom-Json -ErrorAction Stop
                switch ($obj.type) {
                    'assistant' {
                        if ($obj.message.content) {
                            foreach ($content in $obj.message.content) {
                                switch ($content.type) {
                                    'tool_use' {
                                        $toolName = $content.name
                                        $detail = ""
                                        if ($content.input) {
                                            switch ($toolName) {
                                                'Read'   { $detail = Split-Path $content.input.file_path -Leaf }
                                                'Write'  { $detail = Split-Path $content.input.file_path -Leaf }
                                                'Edit'   { $detail = Split-Path $content.input.file_path -Leaf }
                                                'Glob'   { $detail = $content.input.pattern -replace '.*/',''}
                                                'Grep'   { $detail = $content.input.pattern.Substring(0, [Math]::Min(30, $content.input.pattern.Length)) }
                                                'Bash'   { $detail = ($content.input.command -split '\n')[0].Substring(0, [Math]::Min(40, ($content.input.command -split '\n')[0].Length)) }
                                            }
                                        }
                                        if ($detail) {
                                            Write-Host "  🔧 $toolName " -ForegroundColor DarkCyan -NoNewline
                                            Write-Host $detail -ForegroundColor DarkGray
                                        } else {
                                            Write-Host "  🔧 $toolName" -ForegroundColor DarkCyan
                                        }
                                    }
                                    'text' {
                                        if ($content.text) { Write-Host $content.text -ForegroundColor White }
                                    }
                                }
                            }
                        }
                    }
                    'result' {
                        $duration = [math]::Round($obj.duration_ms / 1000, 1)
                        $cost = [math]::Round($obj.total_cost_usd, 4)
                        Write-Host ""
                        Write-Host "✓ Completed in ${duration}s (\$$cost)" -ForegroundColor Green
                    }
                }
            } catch {
                if ($line -and $line -notmatch '^\s*$') { Write-Host $line -ForegroundColor DarkGray }
            }
        }
    }

    return $LASTEXITCODE -eq 0
}

# Main loop
Write-Host "Ralph Wiggum: {TASK} ($Type, $Model, effort=$Effort)" -ForegroundColor Cyan
$total = {ITEM_COUNT}
$iteration = 0
$stalledCount = 0
$maxStalled = 3

while ($iteration -lt $MaxIterations) {
    $iteration++
    $pending = Get-PendingCount
    $completed = Get-CompletedCount
    $completedBefore = $completed
    $percent = [math]::Min(100, [math]::Round(($completed / $total) * 100))

    $barFilled = [math]::Min(20, [math]::Floor($percent / 5))
    $barEmpty = [math]::Max(0, 20 - $barFilled)
    Write-Host "[$(('=' * $barFilled))$(('-' * $barEmpty))] $percent% ($completed/$total)" -ForegroundColor Cyan

    if ($pending -eq 0) {
        Write-Host "All items completed!" -ForegroundColor Green
        break
    }

    if (-not (Invoke-Iteration -Iteration $iteration)) {
        Write-Host "⚠️  Iteration failed. Sleeping 5 minutes before retry..." -ForegroundColor Yellow
        Start-Sleep -Seconds 300
        Write-Host "Retrying iteration $iteration..." -ForegroundColor Yellow
        if (-not (Invoke-Iteration -Iteration $iteration)) {
            Write-Host "✗ Iteration $iteration failed again after retry. Stopping." -ForegroundColor Red
            exit 1
        }
    }

    # Zero-trust: verify the iteration actually progressed
    $completedAfter = Get-CompletedCount

    if ($completedAfter -le $completedBefore) {
        $stalledCount++
        Write-Host "⚠️  No progress detected (stalled $stalledCount/$maxStalled)" -ForegroundColor Yellow
        Write-Host "   Before: $completedBefore completed, $pending pending" -ForegroundColor Yellow
        Write-Host "   After:  $completedAfter completed" -ForegroundColor Yellow

        if ($stalledCount -ge $maxStalled) {
            Write-Host "✗ Stalled $maxStalled times in a row. Claude is claiming done without finishing." -ForegroundColor Red
            Write-Host "   Check the tracker for items marked DONE that shouldn't be." -ForegroundColor Red
            exit 1
        }
    } else {
        $stalledCount = 0
        Write-Host "✓ Progress: $completedBefore → $completedAfter completed" -ForegroundColor Green
    }

    Start-Sleep -Seconds 2
}

Write-Host "Done. Completed: $(Get-CompletedCount) / $total" -ForegroundColor Green
```

### Step 4: Report to User

Show:
- Mode used (Full Planning or Wrap Existing)
- Item count and max iterations calculation
- Generated file paths
- How to run: `./scripts/{task}.ps1`
- Engine override example: `./scripts/{task}.ps1 -Type copilot -Model claude-sonnet-4.6 -Effort high`

### Verification Before Writing Code

```bash
# 1. Find the PSU endpoint and get the EXACT URL
grep -r "New-ProtectedEndpoint.*{resource}" /workspace/src/psu/endpoints/

# 2. Read the SQL schema for EXACT column names
cat /workspace/src/sql/Schema/Tables/{schema}.{Table}.sql
```

## Quality Checks (MANDATORY in every generated prompt)

The generated prompt in `scripts/{task}-prompt.md` MUST include ALL of the following sections verbatim. These are not optional — they are the difference between "Claude says it's done" and "it's actually done."

### 1. NAMING CONSISTENCY (before writing any code)

```
BEFORE writing any code for this item, verify naming:
1. Find the PSU endpoint URL: grep -r "New-ProtectedEndpoint" for the resource
2. Read the SQL schema: cat the .sql file for exact column names
3. Verify URL is plural kebab-case matching the SQL table name
4. If JS API calls exist, verify they match the PSU URL path
DO NOT proceed if any names are mismatched — fix the mismatch first.
```

### 2. VERIFY (prove the code works)

```
AFTER writing code, verify it actually works:
1. If C# was modified: `cd /workspace/src/module && dotnet build --nologo 2>&1 | grep "error CS"`
   - MUST return zero errors. If errors exist, fix them before continuing.
2. If PSU endpoints were modified: `docker restart dbpro-psu` and wait 30 seconds
3. If Hugo templates were modified: `docker restart dbpro-hugo`
4. Read back every file you modified and confirm the changes are present
   - Do NOT trust your memory of what you wrote — actually Read the file
```

### 3. TEST (run tests, don't just claim they pass)

```
AFTER verifying the build:
1. If C# tests exist for this area: `cd /workspace/src/module && dotnet test --filter "FullyQualifiedName~{relevant}" --nologo`
   - Report the exact Passed/Failed/Skipped counts
2. If Pester tests exist: run them and report results
3. If no tests exist for the code you wrote, state that explicitly — do not say "tests pass" when no tests were run
```

### 4. BUG REVIEW (find bugs before marking done)

```
BEFORE marking this item DONE, review your code for these common bugs:
1. **Null references**: Any property access that could be null? Add guards.
2. **Off-by-one**: Any loops, pagination, or array indexing? Verify bounds.
3. **Missing error handling at boundaries**: API inputs validated? SQL params parameterized?
4. **Stale references**: Did you reference a function/variable/column that doesn't exist?
   - grep for it — don't assume it exists from memory
5. **Incomplete implementations**: Search your changes for TODO, FIXME, NotImplemented, stub, placeholder:
   ```bash
   git diff HEAD~1 --unified=0 | grep -i "TODO\|FIXME\|NotImplemented\|stub\|placeholder"
   ```
   - MUST return zero matches. If any exist, you are NOT done.
```

### 5. SECURITY REVIEW (5 checks, non-negotiable)

```
BEFORE marking this item DONE, verify these 5 security properties:
- [ ] **Input validation**: All new parameters are typed and validated — no raw strings passed to SQL
- [ ] **Auth enforcement**: All new endpoints use New-ProtectedEndpoint (not New-PSUEndpoint) — no accidental anonymous access
- [ ] **SQL safety**: All queries use QueryBuilder/MutationBuilder parameterization — grep for string concatenation near SQL
- [ ] **No secrets**: No hardcoded credentials, connection strings, or tokens: `grep -rn "password\|secret\|apikey\|connectionstring" [your files] -i`
- [ ] **No info leaks**: Error responses use the standard envelope — no stack traces, internal paths, or raw SQL errors exposed

If ANY check fails, fix it. Do not mark DONE with security issues.
```

### 6. SIMPLIFY (remove unnecessary complexity)

```
REVIEW your changes for unnecessary complexity:
1. Any single-use helper functions? Inline them.
2. Any dead code or commented-out blocks? Remove them.
3. Any over-engineered abstractions for one-time operations? Flatten them.
4. Any duplicated logic that should be consolidated? Merge it.
Keep changes minimal — only simplify code YOU wrote in this iteration.
```

### 7. DOUBLECHECK (zero-trust final verification)

```
FINAL VERIFICATION — do not trust your earlier checks. Re-verify from scratch:

1. Read the tracker and find the item you just marked DONE
2. Read EVERY file you claim to have modified — confirm the changes are real
3. If it was a C# change, run `dotnet build` ONE MORE TIME right now
4. Verify the tracker status is correct:
   ```bash
   grep -c "| DONE |" {TRACKER_PATH}
   grep -c "| PENDING |" {TRACKER_PATH}
   ```
5. Fill out this verification table (include in your output):

| Check | Result | Evidence |
|-------|--------|----------|
| Files modified | X files | [list them] |
| Build passes | yes/no | [error count from dotnet build] |
| Tests pass | yes/no/N/A | [pass/fail counts] |
| No TODOs/stubs | yes/no | [grep result] |
| Security checks | 5/5 | [any failures?] |
| Naming consistent | yes/no | [URL + SQL verified] |

If ANY row is "no" or incomplete, you are NOT done. Fix it first.
DO NOT mark the tracker item as DONE until this table is fully green.
```

### 8. COMMIT YOUR WORK (mandatory — do NOT skip)

```
After ALL checks pass and the tracker is updated, you MUST commit:

    git add -A
    git commit -m "{type}({task-slug}): {item-name} — {summary}"

Use conventional commit format. If no files were modified (all checks passed),
commit just the tracker update. Each item gets its own commit so progress is
never lost between iterations. Do NOT skip this step.
```

### 9. STRUCTURED COMPLETION REPORT (mandatory output format)

```
After completing an item, your output MUST end with this structure:

ITEM: [item name from tracker]
STATUS: DONE | BLOCKED [reason]
FILES_MODIFIED: [exact file list]
FILES_READ_BACK: [yes — I re-read every modified file | no — EXPLAIN WHY]
BUILD: [PASS (0 errors) | FAIL (N errors) | N/A (no C# changes)]
TESTS: [PASS (N passed, 0 failed) | FAIL (details) | N/A (no tests)]
SECURITY: [5/5 | N/5 (list failures)]
BUGS_FOUND: [0 | N (list them and confirm fixed)]
VERIFICATION_TABLE: [included above | MISSING — NOT DONE]

If this structure is missing from your output, the orchestrator will
treat the iteration as failed regardless of what you claim.
```
