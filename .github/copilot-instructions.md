# dbatools Repository Onboarding Guide

## Repository Overview

**dbatools** is a PowerShell module with nearly 700 commands that automates SQL Server administration and database development. It enables DBAs to migrate SQL Server instances in minutes, test hundreds of backups automatically, and manage 100+ SQL instances from a single console. The project has 7+ million downloads, 250+ contributors, and 10+ years of active development.

**Key Stats:**
- **Size:** ~700 PowerShell commands across ~9.5MB of source code
- **Languages:** PowerShell (v3+ compatible, targets Windows PowerShell 5.1 and PowerShell 7+)
- **Framework:** PowerShell module with SMO (SQL Server Management Objects) via dbatools.library
- **Target Systems:** SQL Server 2000-2022, Azure SQL Database, Azure SQL Managed Instance
- **Supported Platforms:** Windows (100% commands), Linux/macOS (78% commands)

## Critical Prerequisites

### Required Dependencies
1. **dbatools.library** (v2025.8.17) - **MANDATORY** dependency module containing SMO libraries
   - Install: Run `.github/scripts/install-dbatools-library.ps1`
   - Version specified in: `.github/dbatools-library-version.json`
   - Without this, the module will not load

2. **PSScriptAnalyzer v1.18.2** - Required for code formatting and linting
   - Install: `Install-Module PSScriptAnalyzer -RequiredVersion 1.18.2`
   - Used by: `Invoke-DbatoolsFormatter` command and CI builds

3. **Pester** - Follow `tests/CLAUDE.md` for the supported runtime, installation, and test policy

## PR Summary Guidelines

**CRITICAL**: When creating PR summaries using GitHub Copilot (or Claude Code), follow these rules to avoid verbose, unhelpful descriptions:

### What Makes a Good PR Summary

**DO:**
- Start with a one-sentence summary of WHAT changed (max 20 words)
- Explain WHY the change was needed (problem being solved)
- List WHAT was changed (2-5 bullet points maximum)
- Keep it under 200 words total
- Use plain language, not diff terminology
- Focus on user impact or functional changes

**DON'T:**
- Include detailed file-by-file diffs or line counts
- Link to every changed file individually
- Use phrases like "This PR includes changes to..." or "Modified files include..."
- Add boilerplate sections you won't fill in
- Repeat information that's already in commits
- Include obvious information ("added tests for the new feature")

### PR Summary Template

Use this concise format:

```markdown
## Summary
[One sentence describing the change]

## Why
[1-2 sentences explaining the problem or need]

## Changes
- [Key change 1]
- [Key change 2]
- [Key change 3]

## Testing
[How this was verified - keep it brief]
```

### Example - GOOD PR Summary

```markdown
## Summary
Added -Pattern parameter to Get-DbaDatabase for regex-based filtering

## Why
Users need to filter databases using regex patterns instead of simple wildcards

## Changes
- Added -Pattern parameter using regex matching
- Updated parameter validation test
- Added integration tests for pattern filtering

## Testing
Verified against SQL Server 2016+ instances with various database naming patterns
```

### Example - BAD PR Summary (Too Verbose)

```markdown
## Summary
This PR includes changes to the Get-DbaDatabase command and its associated test files

## Modified Files
- `public/Get-DbaDatabase.ps1` (+45 lines, -12 lines)
  - [View diff](https://github.com/...)
- `tests/Get-DbaDatabase.Tests.ps1` (+89 lines, -5 lines)
  - [View diff](https://github.com/...)

## Changes Made
The following modifications have been implemented:
1. Added a new parameter called -Pattern to the Get-DbaDatabase function
2. Implemented regex matching logic for the pattern parameter
3. Updated the parameter validation section in the test file
4. Added new test cases for pattern matching scenarios
5. Updated documentation strings
6. Fixed minor formatting issues

## Detailed Changes by File
### public/Get-DbaDatabase.ps1
- Line 45: Added Pattern parameter definition
- Line 67: Implemented regex matching
- Line 89: Updated help documentation
...
```

### Automation Instructions for Copilot/Claude

When using automated PR generation (like `gh pr create` or GitHub Copilot), configure to:

1. **Analyze commits** - Extract the primary purpose from commit messages
2. **Summarize functionally** - What behavior changed, not which files
3. **Skip file listings** - Diffs are visible in the PR itself
4. **Match CLAUDE.md style** - Follow repository coding standards
5. **Keep it scannable** - Maintainers should read it in <30 seconds

### Custom Instructions for GitHub Copilot

Add this to your repository's instructions or prompt Copilot with:

```markdown
When generating PR summaries:
- Maximum 200 words
- No file diffs or line counts
- Focus on functional changes
- Follow template: Summary → Why → Changes → Testing
- Use bullet points (max 5)
- Match tone and style from CLAUDE.md
```

## Build & Test Instructions

### Initial Setup (REQUIRED)
```powershell
# 1. Install dbatools.library (MANDATORY - module won't work without this)
.\.github\scripts\install-dbatools-library.ps1

# 2. Install PSScriptAnalyzer (for formatting)
Install-Module PSScriptAnalyzer -RequiredVersion 1.18.2 -Force

# 3. Install Pester as specified in tests/CLAUDE.md

# 4. Import the module to verify setup
Import-Module .\dbatools.psd1

# 5. Trust SQL Server certificates (if testing locally)
Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true -Register
Set-DbatoolsConfig -FullName sql.connection.encrypt -Value $false -Register
```

**CRITICAL:** Always run `install-dbatools-library.ps1` first. The module CANNOT function without dbatools.library installed.

### Running Tests

**Integration tests require SQL Server instances** - tests use Docker containers on Linux or local SQL Server on Windows.

```powershell
# Run specific test file (recommended for development)
Invoke-Pester .\tests\Get-DbaDatabase.Tests.ps1 -Output Detailed

# Run tests with tag filter
Invoke-Pester -Path .\tests\ -Tag UnitTests -Output Detailed

# Run integration tests (requires SQL Server)
Invoke-Pester -Path .\tests\ -Tag IntegrationTests -Output Detailed
```

**Test Execution Time:** Individual test files run in 5-30 seconds. Full integration test suite takes 45+ minutes across all scenarios.

### Formatting Code

```powershell
# Format a single file (ALWAYS do this before committing)
Invoke-DbatoolsFormatter -Path .\public\Get-DbaDatabase.ps1

# Format multiple files
Get-ChildItem .\public\*.ps1 | Invoke-DbatoolsFormatter
```

**REQUIRED:** All code must pass PSScriptAnalyzer formatting before PR submission. The CI pipeline WILL fail if code is not properly formatted.

### Module Registration (For New Commands)

When creating a new command, you MUST register it in TWO places:

1. **dbatools.psd1** - Add to `FunctionsToExport` array (alphabetically)
2. **dbatools.psm1** - Add to `Export-ModuleMember -Function` list (alphabetically)

Failure to register in both locations = command won't be available to users.

## Repository Structure

### Key Directories
```
dbatools/
├── public/              # ~700 exported commands (user-facing)
├── private/             # Internal functions (not exported)
│   ├── functions/       # Helper functions
│   ├── configurations/  # Module config/settings
│   └── scripts/         # Initialization scripts
├── tests/               # Pester 6 tests (one per public command)
│   └── CLAUDE.md        # Single source for test standards
├── bin/                 # Build assets, SQL scripts, templates
├── xml/                 # Type and format definitions
├── .github/
│   ├── workflows/       # GitHub Actions (integration tests, CI/CD)
│   └── scripts/         # Build and setup scripts
├── dbatools.psd1        # Module manifest (metadata, dependencies)
├── dbatools.psm1        # Module loader (imports public/private functions)
└── CLAUDE.md            # **PRIMARY STYLE GUIDE** - MUST READ
```

### Configuration Files
- **CLAUDE.md** - Single source for repository-wide PowerShell style and workflow conventions
- **tests/CLAUDE.md** - Single source for ongoing test policy and Pester 6 rules
- **.github/workflows/ci-azure.yml** - the test suite of record (Windows testing on self-hosted Azure runners, SQL Server 2017/2019/2022)
- **.github/workflows/integration-tests.yml** - GitHub Actions (cross-platform testing)

## CI/CD Validation Pipeline

### Pre-Commit Checks (Run These Before Pushing)

1. **Format check:** Code must pass `Invoke-DbatoolsFormatter`
2. **PSScriptAnalyzer:** No warnings/errors allowed
3. **Tests:** Relevant tests must pass
4. **Module import:** `Import-Module .\dbatools.psd1` must succeed

### GitHub Actions Workflows

**.github/workflows/integration-tests.yml** - Runs on every push to non-master branches:
- **Linux:** Docker containers (SQL Server 2019/2022), runs subset of cross-platform tests
- **Windows:** LocalDB + SQL Server 2019, runs full PowerShell + pwsh test suite
- **macOS:** Limited tests (no WMI/ComputerName commands)

**Validation steps:**
1. Installs dbatools.library (version from `.github/dbatools-library-version.json`)
2. Sets up SQL Server instances
3. Clones appveyor-lab repo for test fixtures
4. Installs SqlPackage
5. Runs platform-specific test suite (`.github/scripts/gh-actions.ps1` or `gh-winactions.ps1`)

### ci-azure (.github/workflows/ci-azure.yml)

The test suite of record. Runs on pushes to `development` and on PRs targeting it, on self-hosted Azure VMSS runners, with these scenarios in parallel:
- **SINGLE:** SQL Server 2022, split into five parts
- **MULTI:** SQL Server 2022 + 2017, for tests needing two instances
- **COPY:** SQL Server 2017 + 2022, for `Copy-*` commands
- **HADR:** SQL Server 2019 with availability groups configured
- **RESTART:** SQL Server 2019, for service restart testing
- **default:** no instance, for tests that don't need a running server

It drives the `tests/appveyor.*.ps1` build scripts, which kept their name when the project moved off AppVeyor; `tests/gha.shim.ps1` supplies the AppVeyor build API they call. There is no `appveyor.yml` in the repository.

**Magic commit commands:**
- Add `(do Get-DbaFoo)` to commit message to run only `Get-DbaFoo` tests
- Add `[skip ci]` to commit message to skip CI entirely

### Common CI Failures & Workarounds

**Problem:** "Could not load dbatools.library"
- **Solution:** Check `.github/dbatools-library-version.json` version is published
- **Workaround:** Update to latest stable version

**Problem:** "Test timed out"
- **Solution:** Reduce test scope, mock external dependencies
- **Typical cause:** Network operations, waiting for SQL Server responses

**Problem:** "Module import failed"
- **Solution:** Check dbatools.psd1 and dbatools.psm1 have matching function lists
- **Check:** All dependencies in RequiredModules are available

## Authoritative Development Instructions

- Read root `CLAUDE.md` for repository-wide PowerShell style and workflow conventions. Those rules apply under `public/`, `private/`, `tests/`, and the repository scripts.
- Read `tests/CLAUDE.md` before changing command behavior or tests. It is the single source for Pester 6 structure, real-boundary behavioral and integration coverage, regression tests, test instances, fixtures, cleanup, and assertions.
- Do not restate these rules in Copilot-specific instructions; update the authoritative file instead.

## Trust These Instructions

**Important:** These instructions are maintained and validated. When in doubt:
1. Check CLAUDE.md first (comprehensive style guide)
2. Check tests/CLAUDE.md for ongoing test policy and Pester 6 requirements
3. Only search codebase if instructions are incomplete or incorrect

**This guide is accurate as of the repository state.** If you find inaccuracies, the repository may have changed - verify with a search only when instructions don't work as described.

---

## Summary Checklist

Before submitting any PR, verify:
- [ ] Read root `CLAUDE.md`
- [ ] If command behavior or tests changed, read `tests/CLAUDE.md`
- [ ] Installed dbatools.library (module imports successfully)
- [ ] Applied the relevant authoritative checklists from those files
- [ ] Ran the verification appropriate to the changed files
