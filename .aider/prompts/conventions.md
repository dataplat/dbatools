# Pester v5 Test Standards - Complete Transformation Guide

## MANDATORY HEADER STRUCTURE

Insert this exact header block at the top of every test file:
```powershell
#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "StaticCommandName",
    $PSDefaultParameterValues = $TestConfig.Defaults
)
```

**CRITICAL**: Replace "StaticCommandName" with the actual command name being tested as a static string. Never derive command names dynamically from file paths or directory structures.

## COMMENT PRESERVATION - ABSOLUTE REQUIREMENT

**ALL COMMENTS MUST BE PRESERVED EXACTLY** as they appear in the original code. This includes:
- Development notes and temporary comments
- End-of-file comments
- CI/CD system comments (especially AppVeyor)
- Seemingly unrelated comments
- Any comment that appears to be a note or reminder

**NO EXCEPTIONS** - Every single comment must remain intact in its original location and format.

## PARAMETER HANDLING

- Define all `$CommandName` parameters as static strings in the param block
- Remove all dynamic command name derivation from file paths or directory structures
- Strip out all knownParameters validation code
- **Preserve all original parameter names exactly as written** - make no assumptions about parameter naming

## TEST STRUCTURE TRANSFORMATION

### Describe Blocks
Replace all Describe block names with `$CommandName` variable and add appropriate tags:

```powershell
Describe $CommandName -Tag UnitTests {
    # tests here
}

Describe $CommandName -Tag IntegrationTests {
    # tests here
}
```

**NEVER use `-ForEach` parameters on any test blocks.**

### Context Blocks
Rewrite Context block names to describe specific scenarios or states:
- "When getting all databases"
- "When database is offline"
- "When connecting to SQL Server"

### Code Organization Rules
- **All setup code** → `BeforeAll` or `BeforeEach` blocks
- **All cleanup code** → `AfterAll` or `AfterEach` blocks
- **All test assertions** → `It` blocks only
- **No loose code** in `Describe` or `Context` blocks

### EnableException Pattern for Integration Tests
```powershell
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $filesToRemove = @()
        # setup code here
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        # cleanup code here
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
}
```

## PARAMETER & VARIABLE NAMING PATTERNS

### Parameter Usage Rules
- **1-2 parameters**: Use direct parameter format
- **3+ parameters**: Use splatting with `$splat<Purpose>` naming (never plain `$splat`)

### Hashtable Alignment (3+ Parameters Only)
Align all splat hashtable assignment operators for readability:

```powershell
# Direct parameters (1-2)
$ag = Get-DbaLogin -SqlInstance $instance -Login $loginName

# Splat with purpose suffix (3+) - aligned = signs
$splatPrimary = @{
    Primary      = $TestConfig.instance3
    Name         = $primaryAgName
    ClusterType  = "None"
    FailoverMode = "Manual"
    Certificate  = "dbatoolsci_AGCert"
    Confirm      = $false
}
$primaryAg = New-DbaAvailabilityGroup @splatPrimary
```

### Variable Scope Management
Use **unique, descriptive names across all scopes** to prevent collisions:

```powershell
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $primaryAgName = "dbatoolsci_agroup"
        $primaryAg = New-DbaAvailabilityGroup @splatPrimary
    }

    Context "When adding AG replicas" {
        BeforeAll {
            $replicaAgName = "dbatoolsci_add_replicagroup"
            $replicaAg = New-DbaAvailabilityGroup @splatRepAg
        }
    }
}
```

## CLEANUP AND RESOURCE MANAGEMENT

### Temporary Resource Pattern
Create unique temporary files/directories and ensure cleanup:

```powershell
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # Create unique temp path for this test run
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory
        $filesToRemove = @()
    }

    AfterAll {
        # Always clean up temp files
        Remove-Item -Path $backupPath -Recurse -ErrorAction SilentlyContinue
        Remove-Item -Path $filesToRemove -ErrorAction SilentlyContinue
    }
}
```

### Cleanup Requirements
- Track all resources created during tests
- Implement cleanup in reverse order of creation when dependencies exist
- Add `-ErrorAction SilentlyContinue` to cleanup operations
- Every resource created in BeforeAll/BeforeEach needs corresponding cleanup in AfterAll/AfterEach

## STANDARD TEST PATTERNS

### Parameter Validation Test (Exact Pattern)
```powershell
Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
```

### Integration Test Pattern
```powershell
Describe $CommandName -Tag IntegrationTests {
    Context "When connecting to SQL Server" {
        BeforeAll {
            $allResults = @()
            foreach ($instance in $TestConfig.Instances) {
                $allResults += Get-DbaDatabase -SqlInstance $instance
            }
        }

        It "Returns database objects with required properties" {
            $allResults | Should -BeOfType Microsoft.SqlServer.Management.Smo.Database
            $allResults[0].Name | Should -Not -BeNullOrEmpty
        }

        It "Always includes system databases" {
            $systemDbs = $allResults | Where-Object Name -in "master", "model", "msdb", "tempdb"
            $systemDbs.Count | Should -BeExactly 4
        }
    }
}
```

## POWERSHELL SYNTAX TRANSFORMATIONS

### Variable References
- Replace all `$_` with `$PSItem` (except where `$_` required for compatibility)
- **Preserve all original parameter names exactly** - no modifications

### Where-Object Conversion
Transform to direct property comparisons when possible:

```powershell
# Good - direct property comparison
$master    = $databases | Where-Object Name -eq "master"
$systemDbs = $databases | Where-Object Name -in "master", "model", "msdb", "tempdb"

# Required - script block for Parameters.Keys or complex filtering
$hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
```

### String and Array Formatting
- **Convert all single quotes to double quotes** (SQL Server module standard)
- **Multi-line array formatting**:
```powershell
$array = @(
    "Item1",
    "Item2",
    "Item3"
)
```
- Replace multi-line concatenated strings with here-strings when appropriate

### Scoping and Variables
- **Replace all `$script:` with `$global:`** (Pester v5 scoping requirement)
- Add explicit scope declarations when variables cross Pester block boundaries
- **Skip conditions must evaluate to `$true` or `$false`**, not strings

### Array and Parameter Operations
- Replace `$results.Count` with `$results.Status.Count` for accurate counting
- Add explicit array initialization: `$array = @()`
- Wrap result collection: `$results = @(Get-Something)`
- Remove unnecessary quotes from parameter values:
```powershell
# Convert this:
"$CommandName" -Tag "IntegrationTests"
# To this:
$CommandName -Tag IntegrationTests
```

### Code Formatting
- Apply **OTBS (One True Brace Style)** formatting to all code blocks
- **Remove all trailing spaces**

## MUST USE / MUST NOT USE

### Must Use
- Static `$CommandName` parameter in param block
- The specified parameter validation approach with WhatIf/Confirm filtering
- Unique variable names across scopes
- Double quotes for strings
- `$global:` instead of `$script:`

### Must Not Use
- Dynamic command name derivation from file paths
- Old knownParameters validation approach
- Generic variable names that cause scope collisions
- `-ForEach` parameters on test blocks
- Assumed parameter names (match originals exactly)

## TRANSFORMATION CHECKLIST

For each test file, ensure:
- [ ] Mandatory header with static command name
- [ ] All comments preserved exactly
- [ ] All loose code moved to appropriate BeforeAll/AfterAll blocks
- [ ] Variable names are unique across scopes
- [ ] Temporary resources have cleanup code
- [ ] EnableException handling for integration tests
- [ ] Parameter validation follows exact pattern
- [ ] All syntax transformations applied
- [ ] OTBS formatting applied
- [ ] No trailing spaces

This guide ensures complete compliance with Pester v5 standards while preserving all original functionality and comments.