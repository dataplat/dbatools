# Pester v4 to v5 Migration Guide

## CORE PESTER v5 REQUIREMENTS

### Mandatory Header Structure
Every test file must include this header:

```powershell
#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "YourModuleName",
    $CommandName = "StaticCommandName",  # Always use static command name
    $PSDefaultParameterValues = $TestConfig.Defaults
)
```

**Critical Requirements:**
- Replace "StaticCommandName" with the actual command name being tested as a static string
- **Remove all dynamic command name derivation** from file paths or directory structures
- Strip out all `knownParameters` validation code (old Pester v4 pattern)

### Critical Structural Changes

#### Test Block Organization
- **All setup code** must be in `BeforeAll` or `BeforeEach` blocks
- **All cleanup code** must be in `AfterAll` or `AfterEach` blocks
- **All test assertions** must be in `It` blocks
- **No loose code** allowed in `Describe` or `Context` blocks
- **Never use `-ForEach` parameter** on any test blocks

```powershell
# Pester v5 Structure
Describe $CommandName {
    BeforeAll {
        # All setup code here
    }

    AfterAll {
        # All cleanup code here
    }

    Context "Specific scenario" {
        BeforeAll {
            # Context-specific setup
        }

        It "Should do something" {
            # Test assertions only
        }
    }
}
```

### Variable Scoping Changes
- Replace all `$script:` with `$global:` for variables that need to persist across Pester blocks
- Pester v5 has stricter scoping - variables in `BeforeAll` may not be available in `It` blocks without proper scoping
- Add explicit scope declarations when variables cross Pester block boundaries

### PowerShell Syntax Updates Required for Pester v5

#### Variable References
- Replace `$_` with `$PSItem` (recommended for clarity, except where `$_` is required for compatibility)

#### Skip Conditions
- Use boolean values for skip conditions (`$true`/`$false`), not strings

#### Array Operations
- Replace `$results.Count` with `$results.Status.Count` for accurate counting
- Add explicit array initialization: `$array = @()`
- Wrap result collection in array subexpression operator: `$results = @(Get-Something)`

#### Parameter Quoting
Remove unnecessary quotes from parameter values:
```powershell
# Convert this:
"$CommandName" -Tag "IntegrationTests"
# To this:
$CommandName -Tag IntegrationTests
```

#### String Formatting
- Replace multi-line concatenated strings with here-strings when appropriate

### Resource Management
- Always include cleanup code in `AfterAll`/`AfterEach` blocks
- Use `-ErrorAction SilentlyContinue` on cleanup operations
- Create unique temporary resources using `Get-Random`

```powershell
BeforeAll {
    $tempPath = "$env:TEMP\TestRun-$(Get-Random)"
    $resourcesToCleanup = @()
}

AfterAll {
    Remove-Item -Path $tempPath -Recurse -ErrorAction SilentlyContinue
    Remove-Item -Path $resourcesToCleanup -ErrorAction SilentlyContinue
}
```

### Where-Object Conversion Rules
Transform Where-Object script blocks to direct property comparisons when possible:

```powershell
# Pester v5 Preferred - direct property comparison
$master = $databases | Where-Object Name -eq "master"
$systemDbs = $databases | Where-Object Name -in "master", "model", "msdb", "tempdb"

# Required - script block for complex filtering only
$hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
```

Only use script blocks when direct property comparison is not possible.

## MIGRATION CHECKLIST

**Header and Structure:**
- [ ] Added mandatory `#Requires` header
- [ ] Replaced dynamic command name derivation with static command name
- [ ] Stripped out old `knownParameters` validation code
- [ ] Moved all loose code into appropriate `BeforeAll`/`AfterAll` blocks
- [ ] Removed any `-ForEach` parameters from test blocks
- [ ] All test assertions properly placed in `It` blocks

**Variable Scoping:**
- [ ] Changed `$script:` to `$global:` where needed
- [ ] Added explicit scope declarations for cross-block variables
- [ ] Verified variable scoping works across Pester blocks

**Syntax Transformations:**
- [ ] Replaced `$_` with `$PSItem` (except where compatibility requires `$_`)
- [ ] Replaced string-based skip conditions with boolean values
- [ ] Updated array operations (`$results.Count` → `$results.Status.Count`)
- [ ] Added explicit array initialization where needed
- [ ] Removed unnecessary parameter quotes
- [ ] Applied Where-Object conversions where possible
- [ ] Replaced concatenated strings with here-strings where appropriate

**Resource Management:**
- [ ] Added proper cleanup code with error suppression
- [ ] Created unique temporary resources using `Get-Random`
- [ ] Ensured all created resources have corresponding cleanup

**Migration Policy:**
- [ ] Do not invent new integration tests - if they don't exist, there's a reason