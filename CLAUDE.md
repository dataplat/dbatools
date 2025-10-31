# dbatools PowerShell Style Guide for Claude Code

This style guide provides coding standards for dbatools PowerShell development to ensure consistency, readability, and maintainability across the project.

## CRITICAL COMMAND SYNTAX RULES

### NO BACKTICKS - ALWAYS USE SPLATS

**ABSOLUTE RULE**: NEVER suggest or use backticks (`) for line continuation. Backticks are an anti-pattern in modern PowerShell development.

### PARAMETER ATTRIBUTES - NO `= $true` SYNTAX

**MODERN RULE**: Do NOT use `Mandatory = $true` or similar boolean attribute assignments. Boolean attributes do not require explicit value assignment in modern PowerShell.

```powershell
# CORRECT - Modern attribute syntax (no = $true)
param(
    [Parameter(Mandatory)]
    [string]$SqlInstance,

    [Parameter(ValueFromPipeline)]
    [object[]]$InputObject,

    [switch]$EnableException
)

# WRONG - Outdated PSv2 syntax (no longer needed)
param(
    [Parameter(Mandatory = $true)]
    [string]$SqlInstance,

    [Parameter(ValueFromPipeline = $true)]
    [object[]]$InputObject
)
```

**Guidelines:**
- Use `[Parameter(Mandatory)]` not `[Parameter(Mandatory = $true)]`
- Use `[switch]` for boolean flags, not `[bool]` parameters
- Keep non-boolean attributes with values: `[Parameter(ValueFromPipelineByPropertyName = "Name")]`

### POWERSHELL v3 COMPATIBILITY

**CRITICAL RULE**: dbatools must support PowerShell v3. NEVER use `::new()` or other PowerShell v5+ syntax constructs.

**Do NOT use:**
- `[ClassName]::new()` - Use `New-Object` instead
- Advanced type accelerators only available in v5+
- Other v5+ language features

```powershell
# CORRECT - PowerShell v3 compatible
$object = New-Object -TypeName System.Collections.Hashtable
$collection = New-Object System.Collections.ArrayList

# WRONG - PowerShell v5+ only
$object = [System.Collections.Hashtable]::new()
$collection = [System.Collections.ArrayList]::new()
```

When in doubt about version compatibility, use the `New-Object` cmdlet approach.

### SPLAT USAGE REQUIREMENT

**USE SPLATS ONLY FOR 3+ PARAMETERS**

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

# WRONG - 3+ parameters without splat
Get-DbaDatabase -SqlInstance $instance -Database $db -EnableException $true -WarningAction SilentlyContinue

# WRONG - Using backticks for continuation
Get-DbaDatabase -SqlInstance $instance `
    -Database $db `
    -EnableException $true

# WRONG - Generic $splat without purpose
$splat = @{
    SqlInstance = $instance
    Database    = $db
    Confirm     = $false
}
```

## COMMENT PRESERVATION REQUIREMENT

**ABSOLUTE MANDATE**: ALL COMMENTS MUST BE PRESERVED EXACTLY as they appear in the original code. This includes:
- Development notes and temporary comments
- End-of-file comments
- CI/CD system comments (especially AppVeyor)
- Seemingly unrelated comments
- Any comment that appears to be a note or reminder
- Do not delete anything that says `#$TestConfig.instance...` or similar metadata

**NO EXCEPTIONS** - Every single comment must remain intact in its original location and format.

## STRING AND QUOTE STANDARDS

- **Always use double quotes** for strings (SQL Server module standard)
- Properly escape quotes when needed
- Convert all single quotes to double quotes for string literals
- Remove unnecessary quotes from parameter values

```powershell
# CORRECT
$database = "master"
$query = "SELECT * FROM sys.databases"
$message = "Database `"$dbName`" created successfully"

# WRONG
$database = 'master'
$query = 'SELECT * FROM sys.databases'
```

## HASHTABLE ALIGNMENT (MANDATORY)

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

## VARIABLE NAMING CONVENTIONS

- Use `$splat<Purpose>` for 3+ parameters (never plain `$splat`)
- Use direct parameters for 1-2 parameters
- Create unique variable names across all scopes to prevent collisions
- Be descriptive with variable names to indicate their purpose

```powershell
# GOOD - descriptive splat names with aligned formatting
$splatPrimary = @{
    Primary      = $TestConfig.instance3
    Name         = $primaryAgName
    ClusterType  = "None"
    FailoverMode = "Manual"
    Certificate  = "dbatoolsci_AGCert"
    Confirm      = $false
}

$splatReplica = @{
    Secondary = $TestConfig.instance2
    Name      = $replicaAgName
    ClusterType = "None"
    Confirm   = $false
}

# Direct parameters for 1-2 parameters
$ag = Get-DbaLogin -SqlInstance $instance -Login $loginName

# WRONG - Generic splat name
$splat = @{
    Primary = $TestConfig.instance3
    Name    = $agName
}
```

### Unique Names Across Scopes

Use unique, descriptive variable names across scopes to avoid collisions:

```powershell
Describe $CommandName {
    BeforeAll {
        $primaryInstanceName = "instance3"
        $splatPrimary = @{
            SqlInstance = $primaryInstanceName
            Database    = "testdb"
        }
    }

    Context "Specific scenario" {
        BeforeAll {
            # Different variable name - not $primaryInstanceName again
            $secondaryInstanceName = "instance2"
            $splatSecondary = @{
                SqlInstance = $secondaryInstanceName
                Database    = "testdb"
            }
        }
    }
}
```

## ARRAY FORMATTING

Multi-line arrays must be formatted consistently:

```powershell
$expectedParameters = @(
    "SqlInstance",
    "SqlCredential",
    "Database",
    "EnableException"
)

# Multi-line hashtable arrays
$instances = @(
    @{
        Name    = "instance1"
        Version = "2019"
    },
    @{
        Name    = "instance2"
        Version = "2022"
    }
)
```

## WHERE-OBJECT USAGE

Prefer direct property comparison for simple filters:

```powershell
# Preferred - direct property comparison
$master = $databases | Where-Object Name -eq "master"
$systemDbs = $databases | Where-Object Name -in "master", "model", "msdb", "tempdb"

# Required - script block for complex filtering only
$hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
```

## FORMATTING RULES

- Apply OTBS (One True Brace Style) formatting to all code blocks
- No trailing spaces anywhere
- Use `$results.Status.Count` for accurate counting in dbatools context
- Preserve all original parameter names exactly as written
- 4-space indentation for consistency

```powershell
# CORRECT - OTBS style
if ($condition) {
    $result = Get-DbaDatabase -SqlInstance $instance
} else {
    $result = $null
}

# CORRECT - Foreach with OTBS
foreach ($instance in $instances) {
    $splatQuery = @{
        SqlInstance = $instance
        Query       = "SELECT @@VERSION"
    }
    $null = Invoke-DbaQuery @splatQuery
}
```

## TEMPORARY FILES AND RESOURCE MANAGEMENT

- Create temporary test files/directories with unique names using `Get-Random`
- Always clean up temporary resources with `-ErrorAction SilentlyContinue`
- Track all resources created for cleanup

```powershell
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
```

## DBATOOLS-SPECIFIC CONVENTIONS

### Command Naming and Creation

**CRITICAL RULE**: When creating new commands, follow PowerShell best practices:

1. **Use singular nouns** - Command names must use singular nouns, not plural
   - Correct: `Get-DbaDatabase`, `Get-DbaLogin`, `Get-DbaAgent`
   - Incorrect: `Get-DbaDatabases`, `Get-DbaLogins`, `Get-DbaAgents`

2. **Use approved verbs** - Always use approved PowerShell verbs from the standard set (Get, Set, New, Remove, Invoke, etc.)

3. **Consistent naming pattern** - Follow the `<Verb>-Dba<Noun>` pattern consistently

```powershell
# CORRECT - Singular nouns
function Get-DbaDatabase { }
function Set-DbaLogin { }
function New-DbaAgent { }
function Remove-DbaJob { }

# WRONG - Plural nouns
function Get-DbaDatabases { }
function Set-DbaLogins { }
function New-DbaAgents { }
```

### Microsoft SMO Property Name Typos

**CRITICAL KNOWLEDGE**: Some Microsoft SMO (SQL Server Management Objects) properties contain typos in their official names. These are NOT errors - they are the actual property names you must use.

**Known typos that MUST be preserved:**

1. **`AvailabilityDateabaseId`** (with typo: "Dateabase" instead of "Database")
   - Used in: Availability Group DatabaseReplicaStates
   - Correct usage: `Where-Object AvailabilityDateabaseId -eq $db.UniqueId`
   - DO NOT "fix" this to `AvailabilityDatabaseId` - it will break the code

```powershell
# CORRECT - Uses Microsoft's typo
$databaseReplicaState = $replicaStates | Where-Object AvailabilityDateabaseId -eq $db.UniqueId

# WRONG - "Fixed" spelling will not work
$databaseReplicaState = $replicaStates | Where-Object AvailabilityDatabaseId -eq $db.UniqueId
```

**Important:** When reviewing or modifying code that uses SMO objects, verify the actual property names in Microsoft's documentation or SMO metadata before "correcting" apparent typos. The typo might be intentional (or at least unchangeable) in the SMO library.

### Command Registration

**CRITICAL RULE**: When adding a new command, you MUST register it in TWO places:

1. **Add to dbatools.psd1** - In the `FunctionsToExport` array
2. **Add to dbatools.psm1** - In the explicit command export section

Both registrations are required for the command to be properly exported and discoverable.

```powershell
# Example: Adding a new command "Get-DbaNewFeature"

# 1. In dbatools.psd1, add to FunctionsToExport:
FunctionsToExport = @(
    'Get-DbaDatabase'
    'Get-DbaNewFeature'  # ADD HERE
    'Set-DbaDatabase'
    # ... other commands
)

# 2. In dbatools.psm1, add to explicit exports section:
Export-ModuleMember -Function @(
    'Get-DbaDatabase'
    'Get-DbaNewFeature'  # ADD HERE
    'Set-DbaDatabase'
    # ... other commands
)
```

Failure to register in both locations will result in the command not being available when users import the module.

### Pull Request Naming

**PR titles should follow this format:**

```
<CommandName or PrimaryFile> - <Description>
```

**Examples:**
- `Get-DbaDatabase - Add support for filtering by recovery model`
- `Set-DbaAgentJobStep - Fix proxy removal and prevent unwanted parameter resets`
- `Invoke-DbaQuery - Improve error handling for connection timeouts`
- `dbatools.psm1 - Update module initialization logic`

**Guidelines:**
- Start with the primary command or file affected (PascalCase for commands)
- Use a hyphen and space as separator: ` - `
- Keep the description concise and descriptive (not vague)
- Focus on what the change does, not implementation details

### Parameter Validation Pattern

```powershell
Context "Parameter validation" {
    It "Should have the expected parameters" {
        $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
        $expectedParameters = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "EnableException"
        )
        Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
    }
}
```

### EnableException Handling

For integration tests, use EnableException to ensure test setup/cleanup failures are detected:

```powershell
BeforeAll {
    # Set EnableException for setup to catch failures
    $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

    # Perform setup operations
    $null = New-DbaDatabase -SqlInstance $instance -Name $testDb

    # Remove EnableException for actual test execution
    $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
}

AfterAll {
    # Re-enable for cleanup
    $PSDefaultParameterValues['*-Dba*:EnableException'] = $true
    $null = Remove-DbaDatabase -SqlInstance $instance -Database $testDb
}
```

### Test Management Guidelines

The dbatools test suite must remain manageable in size while ensuring adequate coverage for important functionality. Follow these guidelines:
The dbatools test suite must remain manageable in size while ensuring adequate coverage for important functionality. Follow these guidelines:

**When to Update Tests:**
- **ALWAYS update parameter validation tests** when parameters are added or removed from a command
- **ADD tests for new functionality** - When adding new parameters or features, include tests that verify the new functionality works correctly
- **ADD regression tests** when fixing a specific bug that needs to be prevented from recurring
- **AVOID bloat** - Don't add generic coverage tests for basic operations unless they test a specific fix or new feature
- **ADD tests for new functionality** - When adding new parameters or features, include tests that verify the new functionality works correctly
- **ADD regression tests** when fixing a specific bug that needs to be prevented from recurring
- **AVOID bloat** - Don't add generic coverage tests for basic operations unless they test a specific fix or new feature

**Parameter Validation Updates:**

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

**Tests for New Features:**

When adding new parameters or functionality, include tests that verify the new feature works:

```powershell
# GOOD - Test for a new parameter that filters results
Context "Filter by recovery model" {
    It "Should return only databases with Full recovery model" {
        $splatFilter = @{
            SqlInstance   = $instance
            RecoveryModel = "Full"
        }
        $result = Get-DbaDatabase @splatFilter
        $result.RecoveryModel | Should -All -Be "Full"
    }
}

# GOOD - Test for a new switch parameter
Context "Force parameter" {
    It "Should skip confirmation when -Force is used" {
        $splatForce = @{
            SqlInstance = $instance
            Database    = $testDb
            Force       = $true
            Confirm     = $false
        }
        { Remove-DbaDatabase @splatForce } | Should -Not -Throw
    }
}
```

**Tests for New Features:**

When adding new parameters or functionality, include tests that verify the new feature works:

```powershell
# GOOD - Test for a new parameter that filters results
Context "Filter by recovery model" {
    It "Should return only databases with Full recovery model" {
        $splatFilter = @{
            SqlInstance   = $instance
            RecoveryModel = "Full"
        }
        $result = Get-DbaDatabase @splatFilter
        $result.RecoveryModel | Should -All -Be "Full"
    }
}

# GOOD - Test for a new switch parameter
Context "Force parameter" {
    It "Should skip confirmation when -Force is used" {
        $splatForce = @{
            SqlInstance = $instance
            Database    = $testDb
            Force       = $true
            Confirm     = $false
        }
        { Remove-DbaDatabase @splatForce } | Should -Not -Throw
    }
}
```

**Regression Tests:**

Add regression tests when fixing bugs:
- Fixing a specific, reproducible bug that should be prevented from recurring
Add regression tests when fixing bugs:
- Fixing a specific, reproducible bug that should be prevented from recurring
- The bug is significant enough to warrant long-term protection
- The test demonstrates the bug is fixed and prevents regression
- The test demonstrates the bug is fixed and prevents regression

Example of when to add a regression test:

```powershell
# GOOD - Regression test for a specific bug fix
Context "Regression tests" {
    It "Should not remove proxy when updating unrelated job step properties (issue #1234)" {
        # Test for specific bug that was fixed
        $splatUpdate = @{
            SqlInstance = $instance
            Job         = $jobName
            StepName    = $stepName
            Database    = "newdb"
        }
        $result = Set-DbaAgentJobStep @splatUpdate
        $result.ProxyName | Should -Be $originalProxyName
    }
}
```

**What NOT to do:**

```powershell
# WRONG - Adding general coverage tests for existing functionality without a fix
# WRONG - Adding general coverage tests for existing functionality without a fix
It "Should return correct number of databases" { }
It "Should handle empty result sets" { }
It "Should work with pipeline input" { }

# WRONG - Generic edge case tests unrelated to changes
It "Should handle null parameters gracefully" { }
It "Should work with special characters in names" { }

# WRONG - Generic edge case tests unrelated to changes
It "Should handle null parameters gracefully" { }
It "Should work with special characters in names" { }
```

Don't add tests for existing functionality unless you're fixing a bug or adding a new feature that needs verification.
Don't add tests for existing functionality unless you're fixing a bug or adding a new feature that needs verification.

## VERIFICATION CHECKLIST

**Comment and Parameter Preservation:**
- [ ] All comments preserved exactly as in original
- [ ] Parameter names match original exactly without modification
- [ ] No backticks used for line continuation
- [ ] No `= $true` used in parameter attributes (use modern syntax)
- [ ] Splats used only for 3+ parameters

**Version Compatibility:**
- [ ] No `::new()` syntax used (PowerShell v3+ compatible)
- [ ] No v5+ language features used
- [ ] `New-Object` used for object instantiation

**Style Requirements:**
- [ ] Double quotes used for all strings
- [ ] **MANDATORY**: Hashtable assignments perfectly aligned
- [ ] Splat variables use descriptive `$splat<Purpose>` format
- [ ] Variable names are unique across scopes
- [ ] OTBS formatting applied throughout
- [ ] No trailing spaces anywhere

**dbatools Patterns:**
- [ ] EnableException handling correctly implemented
- [ ] Parameter validation follows dbatools pattern
- [ ] Where-Object conversions applied appropriately
- [ ] Temporary resource cleanup implemented properly
- [ ] Splat usage follows 3+ parameter rule strictly
- [ ] Microsoft SMO property typos preserved (e.g., AvailabilityDateabaseId)

**Command Registration (if adding new commands):**
- [ ] Command name uses singular nouns (not plural)
- [ ] Command uses approved PowerShell verb
- [ ] Command follows `<Verb>-Dba<Noun>` naming pattern
- [ ] Command name uses singular nouns (not plural)
- [ ] Command uses approved PowerShell verb
- [ ] Command follows `<Verb>-Dba<Noun>` naming pattern
- [ ] Command added to `FunctionsToExport` in dbatools.psd1
- [ ] Command added to `Export-ModuleMember` in dbatools.psm1

**Test Management:**
- [ ] Parameter validation test updated if parameters were added/removed
- [ ] Tests added for new functionality and parameters (not just bloat)
- [ ] Regression tests added for significant bug fixes
- [ ] Generic coverage tests avoided unless testing a specific fix or new feature
- [ ] Test suite remains manageable and focused
- [ ] Tests added for new functionality and parameters (not just bloat)
- [ ] Regression tests added for significant bug fixes
- [ ] Generic coverage tests avoided unless testing a specific fix or new feature
- [ ] Test suite remains manageable and focused

## SUMMARY

The golden rules for dbatools code:

1. **NEVER use backticks** - Use splats for 3+ parameters, direct syntax for 1-2
2. **NEVER use `= $true` in parameter attributes** - Use modern syntax: `[Parameter(Mandatory)]` not `[Parameter(Mandatory = $true)]`
3. **NEVER use `::new()` syntax** - Use `New-Object` for PowerShell v3 compatibility
4. **NEVER "fix" Microsoft SMO typos** - Properties like `AvailabilityDateabaseId` are correct as-is
5. **ALWAYS align hashtables** - Equals signs must line up vertically
6. **ALWAYS preserve comments** - Every comment stays exactly as written
7. **ALWAYS use double quotes** - SQL Server module standard
8. **ALWAYS use unique variable names** - Prevent scope collisions
9. **ALWAYS use descriptive splatnames** - `$splatConnection`, not `$splat`
10. **ALWAYS register new commands** - Add to both dbatools.psd1 and dbatools.psm1
11. **ALWAYS use singular nouns** - Command names use singular, not plural
