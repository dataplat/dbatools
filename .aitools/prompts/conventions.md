# Pester v5 Test Standards - Complete Claude Transformation Guide

## CRITICAL COMMENT PRESERVATION REQUIREMENT

**ABSOLUTE MANDATE**: ALL COMMENTS MUST BE PRESERVED EXACTLY as they appear in the original code. This includes:
- Development notes and temporary comments
- End-of-file comments
- CI/CD system comments (especially AppVeyor)
- Seemingly unrelated comments
- Any comment that appears to be a note or reminder

**NO EXCEPTIONS** - Every single comment must remain intact in its original location and format.

## TRANSFORMATION OBJECTIVES

<objectives>
Transform PowerShell test files to comply with Pester v5 standards for the dbatools module. Maintain all existing functionality while enforcing consistent structure and style.
</objectives>

## MANDATORY HEADER STRUCTURE

<header_requirements>
Insert this exact header block at the top of every test file:

```powershell
#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "StaticCommandName",  # Always use static command name, never derive from file
    $PSDefaultParameterValues = $TestConfig.Defaults
)
```

- Replace "StaticCommandName" with the actual command name being tested as a static string
- Remove all dynamic command name derivation from file paths or directory structures
- Strip out all knownParameters validation code
- Preserve all original parameter names exactly as written - make no assumptions about parameter naming
</header_requirements>

## TEST STRUCTURE TRANSFORMATIONS

<describe_blocks>
### Describe Blocks
- Replace all Describe block names with `$CommandName` variable
- Add appropriate tags: `-Tag UnitTests` or `-Tag IntegrationTests`
- **Never use `-ForEach` parameter on any test blocks**

```powershell
Describe $CommandName -Tag UnitTests {
    # tests here
}
```
</describe_blocks>

<context_blocks>
### Context Blocks
- Describe specific scenarios or states
- Use clear, descriptive names that explain the test scenario
- Example: "When getting all databases", "When database is offline"
</context_blocks>

<test_code_placement>
### Test Code Placement
- All setup code goes in `BeforeAll` or `BeforeEach` blocks
- All cleanup code goes in `AfterAll` or `AfterEach` blocks
- All test assertions go in `It` blocks
- No loose code in `Describe` or `Context` blocks
- Set EnableException in BeforeAll and remove in AfterAll for integration tests

```powershell
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $filesToRemove = @()
        # setup code here
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        Remove-Item -Path $filesToRemove -ErrorAction SilentlyContinue
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When getting all databases" {
        BeforeAll {
            $results = Get-DbaDatabase
        }

        It "Returns results" {
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
```
</test_code_placement>

## STYLE GUIDELINES

<formatting_rules>
### Formatting Rules
- Use double quotes for strings (we're a SQL Server module)
- Array declarations should be on multiple lines:
```powershell
$array = @(
    "Item1",
    "Item2",
    "Item3"
)
```
- Skip conditions must evaluate to `$true` or `$false`, not strings
- Use `$global:` instead of `$script:` for test configuration variables when required for Pester v5 scoping
- No trailing spaces
- Use `$results.Status.Count` for accurate counting
- Apply OTBS (One True Brace Style) formatting to all code blocks
</formatting_rules>

<hashtable_alignment>
### MANDATORY Hashtable Alignment
**CRITICAL FORMATTING REQUIREMENT**: ALL hashtable assignments must be perfectly aligned using spaces to create clean, readable columns. This is non-negotiable.

**REQUIRED FORMAT:**
```powershell
$splatConnection = @{
    SqlInstance     = $TestConfig.instance2
    SqlCredential   = $TestConfig.SqlCredential
    Database        = $dbName
    EnableException = $true
    Confirm         = $false
}
```

**FORBIDDEN - Misaligned hashtables:**
```powershell
# DO NOT DO THIS - misaligned
$splat = @{
    SqlInstance = $instance
    Database = $db
    EnableException = $true
}
```

The equals signs must line up vertically to create clean, professional-looking code.
</hashtable_alignment>

<parameter_variable_naming>
### Parameter & Variable Naming Rules
- Use direct parameters for 1-2 parameters
- Use `$splat<Purpose>` for 3+ parameters (never plain `$splat`)
- **CRITICAL**: Align splat hashtable assignments with consistent spacing for readability - this is MANDATORY

**ALIGNMENT REQUIREMENT**: All hashtable assignments MUST be aligned using spaces to create clean, readable columns:

```powershell
# CORRECT - Aligned = signs (REQUIRED)
$splatPrimary = @{
    Primary      = $TestConfig.instance3
    Name         = $primaryAgName
    ClusterType  = "None"
    FailoverMode = "Manual"
    Certificate  = "dbatoolsci_AGCert"
    Confirm      = $false
}

# WRONG - Not aligned (DO NOT DO THIS)
$splatPrimary = @{
    Primary = $TestConfig.instance3
    Name = $primaryAgName
    ClusterType = "None"
}
```

# Direct parameters
$ag = Get-DbaLogin -SqlInstance $instance -Login $loginName

# Splat with purpose suffix - note aligned = signs
$splatConnection = @{
    SqlInstance     = $TestConfig.instance2
    SqlCredential   = $TestConfig.SqlCredential
    Database        = $dbName
    EnableException = $true
    Confirm         = $false
}
$primaryAg = New-DbaAvailabilityGroup @splatConnection
</parameter_variable_naming>

<where_object_usage>
### Where-Object Usage
Avoid script blocks in Where-Object when possible:
```powershell
# Good - direct property comparison
$master    = $databases | Where-Object Name -eq "master"
$systemDbs = $databases | Where-Object Name -in "master", "model", "msdb", "tempdb"

# Required - script block for Parameters.Keys or filtering
$hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
```
</where_object_usage>

<unique_names_across_scopes>
### Unique Names Across Scopes
Use unique, descriptive variable names across scopes to avoid collisions. Pay particular attention to variable names in BeforeAll:

```powershell
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $primaryAgName = "dbatoolsci_agroup"
        $splatPrimary = @{
            Primary = $TestConfig.instance3
            Name    = $primaryAgName
            ...
        }
        $ag = New-DbaAvailabilityGroup @splatPrimary
    }

    Context "When adding AG replicas" {
        BeforeAll {
            $replicaAgName = "dbatoolsci_add_replicagroup"
            $splatRepAg = @{
                Primary = $TestConfig.instance3
                Name    = $replicaAgName
                ...
            }
            $replicaAg = New-DbaAvailabilityGroup @splatRepAg
        }
    }
}
```
</unique_names_across_scopes>

<temp_files_cleanup>
### Temporary Files and Cleanup
- Create temporary test files/directories with unique names using Get-Random
- Always clean up temporary resources in AfterAll or AfterEach blocks with `-ErrorAction SilentlyContinue`

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

    Context "When performing backups" {
        # test code here
    }
}
```

**Resource Tracking Requirements:**
- Add array variables to collect all resources created during tests
- Implement cleanup in reverse order of creation when dependencies exist
- Every resource created in BeforeAll/BeforeEach needs corresponding cleanup in AfterAll/AfterEach
</temp_files_cleanup>

## TEST IMPLEMENTATION EXAMPLES

<parameter_validation_test>
### Good Parameter Test
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
</parameter_validation_test>

<integration_test_example>
### Good Integration Test
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
</integration_test_example>

## POWERSHELL SYNTAX TRANSFORMATIONS

<syntax_requirements>
### Variable References
- Replace all `$_` with `$PSItem` (except where `$_` is required for compatibility)
- Preserve all parameter names exactly as written in original tests without modification

### String and Array Formatting
- Convert all single quotes to double quotes for string literals
- Add proper quote escaping when needed
- Replace multi-line concatenated strings with here-strings when appropriate
- Multi-line array formatting as shown above

### Scope Declarations
- Replace all `$script:` with `$global:` for test configuration variables (Pester v5 scoping requirement)
- Add explicit scope declarations when variables cross Pester block boundaries

### Array Operations
- Replace `$results.Count` with `$results.Status.Count` for accurate counting
- Add explicit array initialization: `$array = @()`
- Wrap result collection in array subexpression operator: `$results = @(Get-Something)`

### Parameter Quoting
Remove unnecessary quotes from parameter values:
```powershell
# Convert this:
"$CommandName" -Tag "IntegrationTests"
# To this:
$CommandName -Tag IntegrationTests
```
</syntax_requirements>

<where_object_conversion_rules>
### Where-Object Conversion Rules
Transform Where-Object script blocks to direct property comparisons when possible:

```powershell
# Good - direct property comparison
$master = $databases | Where-Object Name -eq "master"
$systemDbs = $databases | Where-Object Name -in "master", "model", "msdb", "tempdb"

# Required - script block for Parameters.Keys or complex filtering
$hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
```

Only use script blocks when direct property comparison is not possible.
</where_object_conversion_rules>

## ADDITIONAL REQUIREMENTS

<must_use_requirements>
### Must Use
- Static `$CommandName` parameter in param block
- The approach shown for parameter validation with filtering out WhatIf/Confirm
- Unique variable names across scopes to prevent collisions
- Double quotes for strings (SQL Server module standard)
- `$global:` instead of `$script:` for test configuration variables
- Multi-line array formatting as specified
- `-ErrorAction SilentlyContinue` on cleanup operations
- OTBS (One True Brace Style) formatting for all code blocks
- **MANDATORY**: Perfectly aligned hashtable assignments using consistent spacing
</must_use_requirements>

<must_not_use_requirements>
### Must Not Use
- Dynamic command name derivation from file paths or directory structures
- Old knownParameters validation approach
- Assumed parameter names - match original tests exactly without modification
- `-ForEach` parameters on any test blocks
- Generic variable names that cause scope collisions
- Single quotes for string literals
- Trailing spaces anywhere in the code
- Plain `$splat` without purpose suffix for 3+ parameters
- **FORBIDDEN**: Misaligned hashtable assignments
</must_not_use_requirements>

## TRANSFORMATION VERIFICATION CHECKLIST

<verification_checklist>
For each test file transformation, verify ALL of the following:

**Header and Structure:**
- [ ] Mandatory header with static command name inserted
- [ ] All comments preserved exactly as they appeared in original
- [ ] All loose code moved to appropriate BeforeAll/AfterAll blocks
- [ ] No `-ForEach` parameters on any test blocks
- [ ] Describe blocks use `$CommandName` variable with appropriate tags

**Variable and Naming:**
- [ ] Variable names are unique across all scopes
- [ ] Parameter names match original tests exactly
- [ ] Splat variables use `$splat<Purpose>` format for 3+ parameters
- [ ] **CRITICAL**: Hashtable assignments are perfectly aligned with consistent spacing (MANDATORY)

**Cleanup and Resources:**
- [ ] Temporary resources have cleanup code with `-ErrorAction SilentlyContinue`
- [ ] EnableException handling correctly placed (BeforeAll to set, AfterAll to remove)
- [ ] All resources created in BeforeAll/BeforeEach have corresponding cleanup

**Syntax Transformations:**
- [ ] All `$_` replaced with `$PSItem` (except where compatibility requires `$_`)
- [ ] All single quotes converted to double quotes
- [ ] All `$script:` replaced with `$global:`
- [ ] Unnecessary parameter quotes removed
- [ ] Where-Object conversions applied where possible

**Formatting:**
- [ ] OTBS (One True Brace Style) formatting applied
- [ ] No trailing spaces anywhere
- [ ] Multi-line arrays formatted correctly
- [ ] Skip conditions use boolean values, not strings
- [ ] **MANDATORY**: All hashtable assignments perfectly aligned

**Test Patterns:**
- [ ] Parameter validation follows exact pattern specified
- [ ] Integration tests follow specified structure
- [ ] All test assertions properly placed in `It` blocks
</verification_checklist>