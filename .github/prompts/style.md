# MODULE Test Style Guide

## COMMENT PRESERVATION REQUIREMENT

**ABSOLUTE MANDATE**: ALL COMMENTS MUST BE PRESERVED EXACTLY as they appear in the original code. This includes:
- Development notes and temporary comments
- End-of-file comments
- CI/CD system comments (especially AppVeyor)
- Seemingly unrelated comments
- Any comment that appears to be a note or reminder
- Do not delete anything that says #$TestConfig.instance...

**NO EXCEPTIONS** - Every single comment must remain intact in its original location and format.

## MODULE-SPECIFIC CONVENTIONS

### Module-Specific Header
```powershell
#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "MODULE",
    $CommandName = "Get-DbaDatabase",  # Static command name for MODULE
    $PSDefaultParameterValues = $TestConfig.Defaults
)
```

### Test Tags and Structure
```powershell
Describe $CommandName -Tag UnitTests {
    # Unit tests here
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        # Explain what needs to be set up for the test:
        # To add a database to an availablity group, we need an availability group and a database that has been backed up.
        # For negative tests, we need a database without a backup and a non existing database.

        # Set variables. They are available in all the It blocks.
        $agName                  = "addagdb_group"
        $existingDbWithBackup    = "dbWithBackup"
        $existingDbWithoutBackup = "dbWithoutBackup"
        $nonexistingDb           = "dbdoesnotexist"

        # Create the objects.
        $splat = @{
            Primary      = $TestConfig.instance3
            Name         = $agName
            ClusterType  = "None"
            FailoverMode = "Manual"
            Certificate  = "MODULEci_AGCert"
        }
        $null = New-DbaAvailabilityGroup @splat

        $null = New-DbaDatabase -SqlInstance $TestConfig.instance3 -Name $existingDbWithBackup
        $null = Backup-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $existingDbWithBackup -Path $backupPath

        $null = New-DbaDatabase -SqlInstance $TestConfig.instance3 -Name $existingDbWithoutBackup

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Cleanup all created object.
        $null = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agName
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.instance3 -Type DatabaseMirroring | Remove-DbaEndpoint
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $existingDbWithBackup, $existingDbWithoutBackup

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    # Integration tests here
}
```

## MODULE STYLE REQUIREMENTS

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
    Certificate  = "MODULEci_AGCert"
    Confirm      = $false
}

$splatReplica = @{
    Secondary    = $TestConfig.instance2
    Name         = $replicaAgName
    ClusterType  = "None"
    Confirm      = $false
}

# Direct parameters for 1-2 parameters
$ag = Get-DbaLogin -SqlInstance $instance -Login $loginName
```

### Unique Names Across Scopes
Use unique, descriptive variable names across scopes to avoid collisions. Pay particular attention to variable names in BeforeAll:

```powershell
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $primaryAgName = "MODULEci_agroup"
        $splatPrimary = @{
            Primary = $TestConfig.instance3
            Name    = $primaryAgName
        }
        $primaryAg = New-DbaAvailabilityGroup @splatPrimary
    }

    Context "When adding AG replicas" {
        BeforeAll {
            $replicaAgName = "MODULEci_add_replicagroup"
            $splatRepAg = @{
                Primary = $TestConfig.instance3
                Name    = $replicaAgName
            }
            $replicaAg = New-DbaAvailabilityGroup @splatRepAg
        }
    }
}
```

### Array Formatting
Multi-line arrays must be formatted consistently:
```powershell
$expectedParameters = @(
    "SqlInstance",
    "SqlCredential",
    "Database",
    "EnableException"
)
```

### Where-Object Usage
Prefer direct property comparison:
```powershell
# Preferred - direct property comparison
$master = $databases | Where-Object Name -eq "master"
$systemDbs = $databases | Where-Object Name -in "master", "model", "msdb", "tempdb"

# Required - script block for complex filtering only
$hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
```

### Temporary Files and Resource Management
- Create temporary test files/directories with unique names using `Get-Random`
- Always clean up temporary resources in `AfterAll` or `AfterEach` blocks with `-ErrorAction SilentlyContinue`

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

**Resource Tracking Requirements:**
- Add array variables to collect all resources created during tests
- Implement cleanup in reverse order of creation when dependencies exist
- Every resource created in BeforeAll/BeforeEach needs corresponding cleanup in AfterAll/AfterEach

### Parameter Validation Pattern
```powershell
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
```

### Integration Test Example
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

### Formatting Rules
- Apply OTBS (One True Brace Style) formatting to all code blocks
- No trailing spaces anywhere
- Use `$results.Status.Count` for accurate counting in MODULE context
- Remove unnecessary quotes from parameter values
- Preserve all original parameter names exactly as written - make no assumptions about parameter naming

## MODULE REQUIREMENTS SUMMARY

### Must Use
- Static `$CommandName` parameter in param block
- The approach shown for parameter validation with filtering out WhatIf/Confirm
- Unique variable names across scopes to prevent collisions
- Double quotes for strings (SQL Server module standard)
- Multi-line array formatting as specified
- `-ErrorAction SilentlyContinue` on cleanup operations
- OTBS (One True Brace Style) formatting for all code blocks
- **MANDATORY**: Perfectly aligned hashtable assignments using consistent spacing

### Must Not Use
- Assumed parameter names - match original tests exactly without modification
- Generic variable names that cause scope collisions
- Single quotes for string literals
- Trailing spaces anywhere in the code
- Plain `$splat` without purpose suffix for 3+ parameters
- **FORBIDDEN**: Misaligned hashtable assignments

## TEST MANAGEMENT GUIDELINES

The dbatools test suite must remain manageable in size while ensuring adequate coverage for important functionality.

### When to Add or Update Tests

- **ALWAYS update parameter validation tests** when parameters are added or removed from a command
- **ALWAYS add reasonable tests for your changes** - When adding new parameters, features, or fixing bugs, include tests that verify the changes work correctly
- **BE REASONABLE** - Add 1-3 focused tests for your changes, not 100 tests
- **For new commands, ALWAYS create tests** - Follow this style guide and migration.md

### Parameter Validation Updates

When you add or remove parameters from a command, you MUST update the parameter validation test:

```powershell
Context "Parameter validation" {
    It "Should have the expected parameters" {
        $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
        $expectedParameters = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "NewParameter",  # ADD new parameters here
            "EnableException"
            # REMOVE deleted parameters from this list
        )
        Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
    }
}
```

### What Makes a Good Test

Good tests are:
- **Focused** - Test one specific behavior or feature
- **Practical** - Test real-world usage scenarios
- **Reasonable** - 1-3 tests per feature, not exhaustive edge cases
- **Relevant** - Test your changes, not unrelated functionality

### Balance is Key

When making changes:
- Fixing a bug? Add a regression test
- Adding a parameter? Add a test that uses it
- Creating a new command? Add parameter validation and 1-3 integration tests
- Refactoring without behavior changes? Existing tests may be sufficient

### Local Testing Setup

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

# 4. Set the default params for sqlcred
$PSDefaultParameterValues["*:SqlCredential"] = $TestConfig.SqlCred
```

## MODULE VERIFICATION CHECKLIST

**Comment and Parameter Preservation:**
- [ ] All comments preserved exactly as in original
- [ ] Parameter names match original tests exactly without modification

**Style Requirements:**
- [ ] Double quotes used for all strings
- [ ] **MANDATORY**: Hashtable assignments perfectly aligned
- [ ] Splat variables use descriptive `$splat<Purpose>` format
- [ ] Variable names are unique across scopes
- [ ] OTBS formatting applied throughout

**Test Management:**
- [ ] Parameter validation test updated if parameters were added/removed
- [ ] Reasonable tests (1-3) added for new functionality
- [ ] Regression tests added for bug fixes
- [ ] Tests are focused, practical, and relevant

**MODULE Patterns:**
- [ ] EnableException handling correctly implemented
- [ ] Parameter validation follows MODULE pattern
- [ ] Where-Object conversions applied appropriately
- [ ] Temporary resource cleanup implemented properly
- [ ] Integration tests follow MODULE structure