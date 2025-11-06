# dbatools Pester v5 Test Guide

This guide provides the standards and best practices for writing Pester v5 tests in the dbatools project.

## MANDATORY HEADER STRUCTURE

Every test file MUST include this exact header:

```powershell
#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDatabase",  # Static command name - use the actual command being tested
    $PSDefaultParameterValues = $TestConfig.Defaults
)
```

**Critical Requirements:**
- Use a **static command name** as a string literal (e.g., "Get-DbaDatabase")
- NEVER derive the command name dynamically from file paths or directory structures
- The `$CommandName` variable is used throughout the test file to reference the command

## TEST BLOCK ORGANIZATION

Pester v5 enforces strict organization of test code. Follow these rules:

### Code Placement Rules

- **All setup code** must be in `BeforeAll` or `BeforeEach` blocks
- **All cleanup code** must be in `AfterAll` or `AfterEach` blocks
- **All test assertions** must be in `It` blocks
- **No loose code** is allowed in `Describe` or `Context` blocks
- **Never use the `-ForEach` parameter** on any test blocks

### Standard Test Structure

```powershell
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # All setup code here
        # Set variables, create test objects, configure environment
    }

    AfterAll {
        # All cleanup code here
        # Remove test objects, clean up temporary files
    }

    Context "Specific scenario" {
        BeforeAll {
            # Context-specific setup
        }

        AfterEach {
            # Per-test cleanup if needed
        }

        It "Should do something specific" {
            # Test assertions only
            $result = Get-DbaDatabase -SqlInstance $instance
            $result | Should -Not -BeNullOrEmpty
        }
    }
}
```

## VARIABLE SCOPING

Pester v5 has strict variable scoping rules:

### Scope Modifiers

- Use `$global:` for variables that need to persist across Pester blocks
- Variables defined in `BeforeAll` are available in nested `It` blocks within the same `Describe` or `Context`
- Variables defined in `BeforeEach` are available only in the `It` block that follows
- Add explicit scope declarations when variables cross Pester block boundaries

```powershell
Describe $CommandName {
    BeforeAll {
        # This variable is available in all It blocks within this Describe
        $instanceName = $TestConfig.instance2

        # For cross-block persistence, use $global: if needed
        $global:sharedResource = New-DbaDatabase -SqlInstance $instanceName -Name "testdb"
    }

    It "Should access BeforeAll variables" {
        # Can access $instanceName directly
        $result = Get-DbaDatabase -SqlInstance $instanceName
        $result | Should -Not -BeNullOrEmpty
    }
}
```

## PESTER v5 SYNTAX STANDARDS

### Variable References

Use `$PSItem` instead of `$_` for clarity (except where `$_` is required for compatibility):

```powershell
# PREFERRED
$filtered = $results | Where-Object { $PSItem.Name -ne "master" }

# ACCEPTABLE (when required for compatibility)
$filtered = $results | ForEach-Object { $_.Name }
```

### Skip Conditions

Use boolean values for skip conditions, not strings:

```powershell
# CORRECT
It "Should test something" -Skip:$true {
    # Test code
}

# WRONG
It "Should test something" -Skip:"true" {
    # Test code
}
```

### Array Operations

- Use `$results.Status.Count` for accurate counting in dbatools context
- Initialize arrays explicitly: `$array = @()`
- Wrap result collection in array subexpression operator when needed

```powershell
# CORRECT - Explicit array initialization
$databases = @()
$databases = @(Get-DbaDatabase -SqlInstance $instance)

# CORRECT - Use .Status.Count for dbatools commands
$count = $results.Status.Count
```

### Parameter Quoting

Remove unnecessary quotes from parameter values:

```powershell
# CORRECT - No unnecessary quotes
Describe $CommandName -Tag IntegrationTests {
    # Test code
}

# WRONG - Unnecessary quotes
Describe "$CommandName" -Tag "IntegrationTests" {
    # Test code
}
```

### String Formatting

Use here-strings for multi-line strings instead of concatenation:

```powershell
# CORRECT - Here-string
$query = @"
SELECT name, database_id
FROM sys.databases
WHERE name = 'master'
"@

# WRONG - Concatenated strings
$query = "SELECT name, database_id" + `
         "FROM sys.databases" + `
         "WHERE name = 'master'"
```

## RESOURCE MANAGEMENT

Always manage test resources properly with cleanup code:

```powershell
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # Enable exceptions for setup to catch failures
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Create unique temporary resources
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        # Track resources for cleanup
        $databasesToCleanup = @()
        $filesToRemove = @()

        # Create test resources
        $testDb = "dbatoolsci_test_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $testDb
        $databasesToCleanup += $testDb

        # Disable exceptions for actual tests
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # Re-enable exceptions for cleanup
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Clean up all resources with error suppression
        Remove-Item -Path $backupPath -Recurse -ErrorAction SilentlyContinue
        Remove-Item -Path $filesToRemove -ErrorAction SilentlyContinue
        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databasesToCleanup -ErrorAction SilentlyContinue
    }

    # Test code here
}
```

**Resource Management Best Practices:**
- Create unique temporary paths using `Get-Random`
- Use `-ErrorAction SilentlyContinue` on cleanup operations
- Track all created resources in arrays for batch cleanup
- Clean up in reverse order of creation when dependencies exist
- Always use `$PSDefaultParameterValues['*-Dba*:EnableException'] = $true` in BeforeAll and AfterAll

## WHERE-OBJECT USAGE

Prefer direct property comparison over script blocks when possible:

```powershell
# PREFERRED - Direct property comparison
$master = $databases | Where-Object Name -eq "master"
$systemDbs = $databases | Where-Object Name -in "master", "model", "msdb", "tempdb"
$largeDbs = $databases | Where-Object Size -gt 1024

# REQUIRED - Script block only for complex filtering
$hasParameters = (Get-Command $CommandName).Parameters.Values.Name |
    Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
```

Use script blocks only when:
- Performing complex boolean logic
- Using operators not supported by direct comparison
- Accessing nested properties or methods

## PESTER v5 VERIFICATION CHECKLIST

**Header and Structure:**
- [ ] File includes mandatory `#Requires` header
- [ ] `$CommandName` uses static string literal, not dynamic derivation
- [ ] All setup code is in `BeforeAll` or `BeforeEach` blocks
- [ ] All cleanup code is in `AfterAll` or `AfterEach` blocks
- [ ] All test assertions are in `It` blocks
- [ ] No loose code in `Describe` or `Context` blocks
- [ ] No `-ForEach` parameters used on test blocks

**Variable Scoping:**
- [ ] `$global:` used for variables that persist across Pester blocks
- [ ] Explicit scope declarations added where variables cross block boundaries
- [ ] Variable scoping verified to work correctly across all test blocks

**Syntax Standards:**
- [ ] `$PSItem` used instead of `$_` (except where compatibility requires `$_`)
- [ ] Boolean values used for skip conditions, not strings
- [ ] Array operations use `.Status.Count` for dbatools commands
- [ ] Explicit array initialization used where needed
- [ ] Unnecessary quotes removed from parameter values
- [ ] Where-Object uses direct property comparison where possible
- [ ] Multi-line strings use here-strings instead of concatenation

**Resource Management:**
- [ ] Cleanup code with error suppression in `AfterAll`/`AfterEach` blocks
- [ ] Unique temporary resources created using `Get-Random`
- [ ] All created resources tracked and cleaned up properly
- [ ] EnableException enabled in BeforeAll/AfterAll, disabled for tests