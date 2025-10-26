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

## VERIFICATION CHECKLIST

**Comment and Parameter Preservation:**
- [ ] All comments preserved exactly as in original
- [ ] Parameter names match original exactly without modification
- [ ] No backticks used for line continuation
- [ ] No `= $true` used in parameter attributes (use modern syntax)
- [ ] Splats used only for 3+ parameters

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

## SUMMARY

The golden rules for dbatools code:

1. **NEVER use backticks** - Use splats for 3+ parameters, direct syntax for 1-2
2. **NEVER use `= $true` in parameter attributes** - Use modern syntax: `[Parameter(Mandatory)]` not `[Parameter(Mandatory = $true)]`
3. **ALWAYS align hashtables** - Equals signs must line up vertically
4. **ALWAYS preserve comments** - Every comment stays exactly as written
5. **ALWAYS use double quotes** - SQL Server module standard
6. **ALWAYS use unique variable names** - Prevent scope collisions
7. **ALWAYS use descriptive splatnames** - `$splatConnection`, not `$splat`
