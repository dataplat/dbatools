# Pester v5 Test Standards
## Objective
Transform PowerShell test files to comply with Pester v5 standards for the dbatools module. Maintain all existing functionality while enforcing consistent structure and style.

## Core Requirements

### Required Header
```powershell
#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "StaticCommandName",  # Always use static command name, never derive from file
    $PSDefaultParameterValues = $TestConfig.Defaults
)
```
The `$CommandName` must always be a static string matching the command being tested.

## Test Structure

### Describe Blocks
- Use the `$CommandName` variable for Describe block names
- Include appropriate tags (`-Tag UnitTests` or `-Tag IntegrationTests`)
- **Never use `-ForEach` parameter on any test blocks**

```powershell
Describe $CommandName -Tag UnitTests {
    # tests here
}
```

### Context Blocks
- Describe specific scenarios or states
- Use clear, descriptive names that explain the test scenario
- Example: "When getting all databases", "When database is offline"

### Test Code Placement
- All setup code goes in `BeforeAll` or `BeforeEach` blocks
- All cleanup code goes in `AfterAll` or `AfterEach` blocks
- All test assertions go in `It` blocks
- No loose code in `Describe` or `Context` blocks
- Set and remove EnableException in BeforeAll/AfterAll for integration tests

```powershell
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true
        $filesToRemove = @()
        # setup code here
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true
        Remove-Item -Path $filesToRemove -ErrorAction SilentlyContinue
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

## Style Guidelines

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

### Where-Object Usage
Avoid script blocks in Where-Object when possible:
```powershell
# Good - direct property comparison
$master    = $databases | Where-Object Name -eq "master"
$systemDbs = $databases | Where-Object Name -in "master", "model", "msdb", "tempdb"

# Required - script block for Parameters.Keys or filtering
$hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ('WhatIf', 'Confirm') }
```

### Parameter & Variable Naming Rules
- Use direct parameters for 1-2 parameters
- Use `$splat<Purpose>` for 3+ parameters (never plain `$splat`)
- Align splat hashtable assignments with consistent spacing for readability

```powershell
# Direct parameters
$ag = Get-DbaLogin -SqlInstance $instance -Login $loginName

# Splat with purpose suffix - note aligned = signs
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

### Temporary Files and Cleanup

- Create temporary test files/directories with unique names using Get-Random
- Always clean up temporary resources in AfterAll or AfterEach blocks

```powershell
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # Create unique temp path for this test run
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory
    }

    AfterAll {
        # Always clean up temp files
        Remove-Item -Path $backupPath -Recurse
    }

    Context "When performing backups" {
        # test code here
    }
}
```

## Test Implementation Examples

### Good Parameter Test
```powershell
Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ('WhatIf', 'Confirm') }
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

## Additional Requirements

### Syntax Requirements
- Use $PSItem instead of $_ (except where $_ is required for compatibility)
- Match parameter names from original tests exactly

### Must Use
- Static `$CommandName` parameter in param block
- The approach shown for parameter validation with filtering out WhatIf/Confirm

### Must Not Use
- Dynamic command name derivation from file paths
- Old knownParameters validation approach
- Assumed parameter names - match original tests exactly

## Critical Instruction
ALL comments must be preserved exactly as they appear in the original code, including seemingly unrelated or end-of-file comments. Even comments that appear to be development notes or temporary must be kept. This is especially important for comments related to CI/CD systems like AppVeyor.
