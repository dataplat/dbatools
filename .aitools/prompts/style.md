# dbatools Test Style Guide

## COMMENT PRESERVATION REQUIREMENT

**ABSOLUTE MANDATE**: ALL COMMENTS MUST BE PRESERVED EXACTLY as they appear in the original code. This includes:
- Development notes and temporary comments
- End-of-file comments
- CI/CD system comments (especially AppVeyor)
- Seemingly unrelated comments
- Any comment that appears to be a note or reminder
- Do not delete anything that says #$TestConfig.instance...

**NO EXCEPTIONS** - Every single comment must remain intact in its original location and format.

## DBATOOLS-SPECIFIC CONVENTIONS

### Module-Specific Header
```powershell
#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDatabase",  # Static command name for dbatools
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
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
    }

    AfterAll {
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
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
- Use `$results.Status.Count` for accurate counting in dbatools context
- Remove unnecessary quotes from parameter values
- Preserve all original parameter names exactly as written - make no assumptions about parameter naming

## DBATOOLS REQUIREMENTS SUMMARY

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

## DBATOOLS VERIFICATION CHECKLIST

**Comment and Parameter Preservation:**
- [ ] All comments preserved exactly as in original
- [ ] Parameter names match original tests exactly without modification

**Style Requirements:**
- [ ] Double quotes used for all strings
- [ ] **MANDATORY**: Hashtable assignments perfectly aligned
- [ ] Splat variables use descriptive `$splat<Purpose>` format
- [ ] Variable names are unique across scopes
- [ ] OTBS formatting applied throughout

**dbatools Patterns:**
- [ ] EnableException handling correctly implemented
- [ ] Parameter validation follows dbatools pattern
- [ ] Where-Object conversions applied appropriately
- [ ] Temporary resource cleanup implemented properly
- [ ] Integration tests follow dbatools structure