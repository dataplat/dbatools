# dbatools Pester v5 Test Guide

This guide provides the standards and best practices for writing Pester v5 tests in the dbatools project.

## Local Testing Setup

To test commands locally during development:

```powershell
# 1. Import the module directly from the psm1 file
Import-Module .\dbatools.psm1
# 1a. ONLY IF any errors about dbatools.library
Import-Module C:\gallery\dbatools.library

# 2. Get the test configuration (private command)
$TestConfig = Get-TestConfig

# 3. Now you can use $TestConfig properties in your tests
$TestConfig.InstanceSingle    # Test SQL instance for tests that only need one instance
$TestConfig.InstanceMulti1    # First test SQL instance for tests that need multiple instances
$TestConfig.InstanceMulti2    # Second test SQL instance for tests that need multiple instances
$TestConfig.SqlCred           # Test credentials, all connections need this
$TestConfig.Temp              # Temp directory for test files
# 4. Set the default paras for sqlcred
$PSDefaultParameterValues["*:SqlCredential"] = $TestConfig.SqlCred
```

This allows you to manually test commands against actual SQL Server instances before running the full test suite.

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
Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        # Set variables. They are available in all the It blocks.
        $testDbName = "dbatoolsci_testdb_$(Get-Random)"

        # Create the objects.
        $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $testDbName

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $testDbName -Confirm:$false -ErrorAction SilentlyContinue

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse -ErrorAction SilentlyContinue
    }

    Context "Specific scenario" {
        BeforeAll {
            # Context-specific setup
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            # Do setup work here
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should do something specific" {
            # Test assertions only
            $result = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $testDbName
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

## DBATOOLS STYLE REQUIREMENTS

### String and Quote Standards
- **Always use double quotes** for strings (SQL Server module standard)
- Properly escape quotes when needed
- Convert all single quotes to double quotes for string literals

### Hashtable Alignment (MANDATORY)

**CRITICAL FORMATTING REQUIREMENT**: ALL hashtable assignments must be perfectly aligned using spaces:

```powershell
# REQUIRED FORMAT - Aligned = signs
$splatConnection = @{
    SqlInstance     = $TestConfig.instance2
    SqlCredential   = $TestConfig.SqlCredential
    Database        = $dbName
    EnableException = $true
    Confirm         = $false
}

# FORBIDDEN - Misaligned hashtables
$splat = @{
    SqlInstance = $instance
    Database = $db
    EnableException = $true
}
```

The equals signs must line up vertically to create clean, professional-looking code.

### Variable Naming Conventions

- Use `$splat<Purpose>` for 3+ parameters (never plain `$splat`)
- Use direct parameters for 1-2 parameters
- Create unique variable names across all scopes to prevent collisions

```powershell
# Good - descriptive splat names with aligned formatting
$splatPrimary = @{
    Primary      = $TestConfig.instance3
    Name         = $primaryAgName
    ClusterType  = "None"
    FailoverMode = "Manual"
    Certificate  = "dbatoolsci_AGCert"
    Confirm      = $false
}

$splatReplica = @{
    Secondary   = $TestConfig.instance2
    Name        = $replicaAgName
    ClusterType = "None"
    Confirm     = $false
}

# Direct parameters for 1-2 parameters
$ag = Get-DbaLogin -SqlInstance $instance -Login $loginName
```

### Unique Names Across Scopes

Use unique, descriptive variable names across scopes to avoid collisions:

```powershell
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $primaryAgName = "dbatoolsci_agroup"
        $splatPrimary = @{
            Primary = $TestConfig.instance3
            Name    = $primaryAgName
        }
        $primaryAg = New-DbaAvailabilityGroup @splatPrimary
    }

    Context "When adding AG replicas" {
        BeforeAll {
            $replicaAgName = "dbatoolsci_add_replicagroup"
            $splatRepAg = @{
                Primary = $TestConfig.instance3
                Name    = $replicaAgName
            }
            $replicaAg = New-DbaAvailabilityGroup @splatRepAg
        }
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

## RESOURCE MANAGEMENT

Always manage test resources properly with cleanup code:

```powershell
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # Enable exceptions for setup to catch failures
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

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
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # Re-enable exceptions for cleanup
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Clean up all resources with error suppression
        Remove-Item -Path $backupPath -Recurse -ErrorAction SilentlyContinue
        Remove-Item -Path $filesToRemove -ErrorAction SilentlyContinue
        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databasesToCleanup -Confirm:$false -ErrorAction SilentlyContinue
    }

    # Test code here
}
```

**Resource Management Best Practices:**
- Create unique temporary paths using `Get-Random`
- Use `-ErrorAction SilentlyContinue` on cleanup operations
- Track all created resources in arrays for batch cleanup
- Clean up in reverse order of creation when dependencies exist
- Always use `$PSDefaultParameterValues["*-Dba*:EnableException"] = $true` in BeforeAll and AfterAll

## PARAMETER VALIDATION PATTERN

```powershell
Context "Parameter validation" {
    It "Should have the expected parameters" {
        $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
        $expectedParameters = $TestConfig.CommonParameters
        $expectedParameters += @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "EnableException"
        )
        Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
    }
}
```

## INTEGRATION TEST EXAMPLE

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

## VERIFICATION CHECKLIST

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

**Style Requirements:**
- [ ] Double quotes used for all strings
- [ ] **MANDATORY**: Hashtable assignments perfectly aligned
- [ ] Splat variables use descriptive `$splat<Purpose>` format
- [ ] Variable names are unique across scopes
- [ ] OTBS formatting applied throughout
- [ ] No trailing spaces anywhere

**Resource Management:**
- [ ] Cleanup code with error suppression in `AfterAll`/`AfterEach` blocks
- [ ] Unique temporary resources created using `Get-Random`
- [ ] All created resources tracked and cleaned up properly
- [ ] EnableException enabled in BeforeAll/AfterAll, disabled for tests
