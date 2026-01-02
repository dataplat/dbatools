# dbatools PowerShell Style Guide for Claude Code

This style guide provides coding standards for dbatools PowerShell development to ensure consistency, readability, and maintainability across the project.

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
    SqlCredential   = $TestConfig.SqlCredential
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

## HASHTABLE ALIGNMENT (MANDATORY)

**CRITICAL FORMATTING REQUIREMENT**: ALL hashtable assignments must be perfectly aligned:

```powershell
# REQUIRED FORMAT - Aligned = signs
$splatConnection = @{
    SqlInstance     = $TestConfig.instance2
    SqlCredential   = $TestConfig.SqlCredential
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

### Commit Messages and Pull Request Naming

**CRITICAL: Always include the `(do ...)` pattern** to limit CI test runs:

```
Get-DbaDatabase - Add support for filtering by recovery model

(do Get-DbaDatabase)
```

For multiple commands: `(do *Login*)` or `(do *Backup*, *Restore*)`

### .OUTPUTS Documentation

All commands should have proper `.OUTPUTS` documentation. **Use the prompt at `.github/prompts/typesncolumns.md`** to generate proper documentation.

### Pattern Parameter Convention

When adding a `-Pattern` parameter, it MUST use regular expressions (regex), not SQL LIKE or PowerShell wildcards.

## TEST GUIDELINES

**For test style requirements**, read `.github/prompts/style.md`.
**For Pester v5 migration**, read `.github/prompts/migration.md`.

Key points:
- ALWAYS update parameter validation tests when parameters change
- Add 1-3 focused tests for new functionality
- Use EnableException in BeforeAll/AfterAll blocks

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
