# dbatools PowerShell Style Guide

This is the single source for repository-wide PowerShell style and workflow conventions. It applies to every PowerShell file under `public/`, `private/`, `tests/`, and the repository scripts, regardless of which agent or contributor makes the change.

## CRITICAL COMMAND SYNTAX RULES

### NO BACKTICKS - ALWAYS USE SPLATS

**ABSOLUTE RULE**: NEVER suggest or use backticks (`) for line continuation. Backticks are an anti-pattern in modern PowerShell development.

### PARAMETER ATTRIBUTES - NO `= $true` SYNTAX

**MODERN RULE**: Do NOT use `Mandatory = $true` or similar boolean attribute assignments.

```powershell
# CORRECT - Modern attribute syntax (no = $true)
param(
    [Parameter(Mandatory)]
    [string]$SqlInstance,
    [Parameter(ValueFromPipeline)]
    [object[]]$InputObject,
    [switch]$EnableException
)

# WRONG - Outdated PSv2 syntax
param(
    [Parameter(Mandatory = $true)]
    [string]$SqlInstance
)
```

**Guidelines:**
- Use `[Parameter(Mandatory)]` not `[Parameter(Mandatory = $true)]`
- Use `[switch]` for boolean flags, not `[bool]` parameters
- Avoid ParameterSets - use Test-Bound instead with useful error messages
- No extra line breaks between parameter declarations

### POWERSHELL v3 COMPATIBILITY

**CRITICAL RULE**: dbatools must support PowerShell v3. NEVER use `::new()` or other PowerShell v5+ syntax.

```powershell
# CORRECT - PowerShell v3 compatible
$object = New-Object -TypeName System.Collections.Hashtable

# WRONG - PowerShell v5+ only
$object = [System.Collections.Hashtable]::new()
```

### SPLAT USAGE REQUIREMENT

- **1-2 parameters**: Use direct parameter syntax
- **3+ parameters**: Use splatted hashtables with `$splat<Purpose>` naming

```powershell
# CORRECT - 2 parameters, direct syntax
$database = Get-DbaDatabase -SqlInstance $instance -Name "master"

# CORRECT - 5 parameters, must use splat
$splatConnection = @{
    SqlInstance     = $instance
    SqlCredential   = $credential
    Database        = $dbName
    EnableException = $true
    Confirm         = $false
}
$result = New-DbaDatabase @splatConnection
```

## SQL SERVER VERSION SUPPORT

Support SQL Server 2000 when feasible. Skip gracefully when feature requires SQL 2005+. Never be dismissive about users running old versions.

**For detailed version patterns and examples**, read `.github/prompts/sql-version-support.md`.

Quick reference:
- SQL 2000 = Version 8, SQL 2005 = Version 9, SQL 2012 = Version 11, etc.
- Use `Connect-DbaInstance -MinimumVersion 9` for SQL 2005+ requirements
- Use conditional logic when SQL 2000 support is straightforward

## SMO vs T-SQL USAGE

**Default to SMO** for object manipulation, scripting, and property access. Use T-SQL for system views, DMVs, stored procedures, and version-specific logic.

**For detailed guidance and examples**, read `.github/prompts/smo-vs-tsql.md`.

## PIPELINE OUTPUT

**CRITICAL RULE**: Output objects immediately to the pipeline. Never collect in ArrayList or array.

**For detailed patterns**, read `.github/prompts/pipeline-output.md`.

```powershell
# CORRECT - Output immediately
foreach ($db in $server.Databases) {
    [PSCustomObject]@{
        ComputerName = $server.ComputerName
        Database     = $db.Name
    }
}

# WRONG - Collecting results
$results = New-Object System.Collections.ArrayList
# ... add to results ...
$results
```

## COMMENT PRESERVATION REQUIREMENT

**ABSOLUTE MANDATE**: ALL COMMENTS MUST BE PRESERVED EXACTLY as they appear in the original code including:
- Development notes and temporary comments
- CI/CD system comments (especially AppVeyor)
- Do not delete anything that says `#$TestConfig.instance...` or similar metadata

## STRING AND QUOTE STANDARDS

- **Always use double quotes** for strings (SQL Server module standard)
- Properly escape quotes when needed

```powershell
# CORRECT
$database = "master"
$message = "Database `"$dbName`" created successfully"

# WRONG
$database = 'master'
```

### ARRAY FORMATTING

Format multi-line arrays with one value per line:

```powershell
$expectedParameters = @(
    "SqlInstance",
    "SqlCredential",
    "Database",
    "EnableException"
)
```

### MULTI-LINE STRINGS

Use here-strings for multi-line strings instead of concatenation:

```powershell
$query = @"
SELECT name, database_id
FROM sys.databases
WHERE name = 'master'
"@
```

## HASHTABLE ALIGNMENT (MANDATORY)

**CRITICAL FORMATTING REQUIREMENT**: ALL hashtable assignments must be perfectly aligned:

```powershell
# REQUIRED FORMAT - Aligned = signs
$splatConnection = @{
    SqlInstance     = $instance
    SqlCredential   = $credential
    Database        = $dbName
    EnableException = $true
}

# FORBIDDEN - Misaligned hashtables
$splat = @{
    SqlInstance = $instance
    Database = $db
}
```

## VARIABLE NAMING CONVENTIONS

- Use `$splat<Purpose>` for 3+ parameters (never plain `$splat`)
- Create unique variable names across all scopes to prevent collisions

## WHERE-OBJECT USAGE

Prefer direct property comparison for simple filters. Use a script block only for complex boolean logic, unsupported operators, or nested property and method access.

```powershell
$master = $databases | Where-Object Name -eq "master"
$systemDbs = $databases | Where-Object Name -in "master", "model", "msdb", "tempdb"
$hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
```

## FORMATTING RULES

- Apply OTBS (One True Brace Style) formatting to all code blocks
- No trailing spaces anywhere
- 4-space indentation for consistency

## DBATOOLS-SPECIFIC CONVENTIONS

### Command Naming and Creation

1. **Use singular nouns** - `Get-DbaDatabase`, not `Get-DbaDatabases`
2. **Use approved verbs** - Get, Set, New, Remove, Invoke, etc.
3. **Follow `<Verb>-Dba<Noun>` pattern**
4. **Include Claude as author** - List "the dbatools team + Claude" in .NOTES when creating commands

### Command Registration

When adding a new command, register it in **TWO places**:
1. **dbatools.psd1** - In the `FunctionsToExport` array
2. **dbatools.psm1** - In the explicit command export section

### Commit Messages

**CRITICAL: Always include the `(do ...)` pattern in the commit message** to limit CI test runs:

```
Get-DbaDatabase - Add support for filtering by recovery model

(do Get-DbaDatabase)
```

For multiple commands: `(do *Login*)` or `(do *Backup*, *Restore*)`

### Pull Request Naming

**Do NOT put the `(do ...)` pattern in pull request titles.** On a pull request, CI derives the tests to run from the files the branch changed, so the marker adds nothing and only makes the title hard to read. Keep the title plain and descriptive:

```
Sync-DbaAvailabilityGroup - Open one shared dedicated admin connection instead of three
```

### Pull Request Integration

**ABSOLUTE RULE: Always squash and merge pull requests that target `development`.**
Never use a merge commit or rebase merge when integrating a PR into `development`.

### .OUTPUTS Documentation

All commands should have proper `.OUTPUTS` documentation. **Use the prompt at `.github/prompts/typesncolumns.md`** to generate proper documentation.

### Pattern Parameter Convention

When adding a `-Pattern` parameter, it MUST use regular expressions (regex), not SQL LIKE or PowerShell wildcards.

## DBATOOLS.LIBRARY VERSION

The dbatools.library version used by CI and local development is pinned in **`.github/dbatools-library-version.json`** - a single JSON file with `version` and `notes` fields. Never hardcode a library version or release URL in a workflow; change this file instead.

```json
{
  "version": "2026.8.2-preview-main-20260802114210",
  "notes": "Version of dbatools.library to use for CI/CD and development"
}
```

`.github/scripts/install-dbatools-library.ps1` reads it and installs from PowerShell Gallery, falling back to GitHub releases at `https://github.com/dataplat/dbatools.library/releases/download/v{version}/dbatools.library.zip`. Preview versions (anything with a prerelease suffix) skip the Gallery and go straight to GitHub releases.

**This pin is repo-wide**, so verify the release exists before committing a change to it. It is consumed by `gallery.yml`, `integration-tests.yml`, `integration-tests-external-table.yml`, `integration-tests-s3.yml`, and `xplat-import.yml`, plus `tests/appveyor.prep.ps1` (which the self-hosted Azure matrix runs) and `tests/ps3-smoke.ps1`. Pinning a preview build points all of them at that build; if the preview asset is later deleted, they all fail until the pin moves.

**For full details**, read `.github/DBATOOLS_LIBRARY_VERSION_MANAGEMENT.md`.

## TEST GUIDELINES

`tests/CLAUDE.md` is the single source for ongoing test policy, including Pester structure, real-boundary behavioral and integration coverage, regression tests, instance selection, fixtures, cleanup, and assertions. Read it before changing command behavior or any test file.

## VERIFICATION CHECKLIST

**Syntax and Style:**
- [ ] No backticks for line continuation
- [ ] No `= $true` in parameter attributes
- [ ] No `::new()` syntax (PowerShell v3 compatible)
- [ ] Splats for 3+ parameters with `$splat<Purpose>` naming
- [ ] Hashtables perfectly aligned
- [ ] Double quotes for strings
- [ ] All comments preserved

**dbatools Patterns:**
- [ ] SMO used first, T-SQL only when appropriate
- [ ] Pipeline output emitted immediately
- [ ] No `-Detailed`/`-Simple` output mode switches
- [ ] Command names use singular nouns

**Command Registration (if adding new commands):**
- [ ] Added to dbatools.psd1 FunctionsToExport
- [ ] Added to dbatools.psm1 Export-ModuleMember
- [ ] Author includes "the dbatools team + Claude"

## SUMMARY - THE GOLDEN RULES

1. **NEVER use backticks** - Use splats for 3+ parameters
2. **NEVER use `= $true` in attributes** - Use `[Parameter(Mandatory)]`
3. **NEVER use `::new()`** - Use `New-Object` for PowerShell v3
4. **NEVER collect pipeline output** - Emit objects immediately
5. **ALWAYS prefer SMO first** - T-SQL only when needed
6. **ALWAYS align hashtables** - Equals signs line up vertically
7. **ALWAYS preserve comments** - Every comment stays exactly as written
8. **ALWAYS use double quotes** - SQL Server module standard
9. **ALWAYS register new commands** - Both dbatools.psd1 and dbatools.psm1
