# Pester v5 Test Standards

## Core Requirements
```powershell
#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)
```
These lines must start every test file.

## Test Structure

### Describe Blocks
- Name your Describe blocks with static command names from the primary command being tested
- Include appropriate tags (`-Tag "UnitTests"` or `-Tag "IntegrationTests"`)

```powershell
Describe "Get-DbaDatabase" -Tag "UnitTests" {
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

```powershell
Describe "Get-DbaDatabase" -Tag "IntegrationTests" {
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
- Avoid script blocks in Where-Object when possible:
```powershell
# Good - direct property comparison
$master = $databases | Where-Object Name -eq "master"
$systemDbs = $databases | Where-Object Name -in "master", "model", "msdb", "tempdb"

# Required - script block for Parameters.Keys
$newParameters = $command.Parameters.Values.Name | Where-Object { $PSItem -notin "WhatIf", "Confirm" }
```

### Parameter & Variable Naming Rules
- Use direct parameters for 1-2 parameters
- Use `$splat<Purpose>` for 3+ parameters (never plain `$splat`)

```powershell
# Direct parameters
$ag = Get-DbaLogin -SqlInstance $instance -Login $loginName

# Splat with purpose suffix
$splatPrimary = @{
    Primary = $TestConfig.instance3
    Name = $primaryAgName
    ClusterType = "None"
    FailoverMode = "Manual"
    Certificate = "dbatoolsci_AGCert"
    Confirm = $false
}
$primaryAg = New-DbaAvailabilityGroup @splatPrimary
```

### Unique names across scopes

- Use unique, descriptive variable names across scopes to avoid collisions
- Play particlar attention to variable names in the BeforeAll

```powershell
Describe "Add-DbaAgReplica" -Tag "IntegrationTests" {
    BeforeAll {
        $primaryAgName = "dbatoolsci_agroup"
        $splatPrimary = @{
            Primary = $TestConfig.instance3
            Name = $primaryAgName
            ...
        }
        $ag = New-DbaAvailabilityGroup @splatPrimary
    }

    Context "When adding AG replicas" {
        BeforeAll {
            $replicaAgName = "dbatoolsci_add_replicagroup"
            $splatRepAg = @{
                Primary = $TestConfig.instance3
                Name = $replicaAgName
                ...
            }
            $replicaAg = New-DbaAvailabilityGroup @splatRepAg
        }
    }
}
```

## Examples

### Good Parameter Test

```powershell
Describe "Get-DbaDatabase" -Tag "UnitTests" {
   Context "Parameter validation" {
       BeforeAll {
           $command = Get-Command Get-DbaDatabase
           $expected = $TestConfig.CommonParameters
           $expected += @(
               "SqlInstance",
               "SqlCredential",
               "Database",
               "Confirm",
               "WhatIf"
           )
       }

       It "Has parameter: <_>" -ForEach $expected {
           $command | Should -HaveParameter $PSItem
       }

       It "Should have exactly the number of expected parameters ($($expected.Count))" {
           $hasparms = $command.Parameters.Values.Name
           Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
       }
   }
}
```

### Good Integration Test
```powershell
Describe "Get-DbaDatabase" -Tag "IntegrationTests" {
    Context "When connecting to SQL Server" -ForEach $TestConfig.Instances {
        BeforeAll {
            $databases = Get-DbaDatabase -SqlInstance $PSItem
        }

        It "Returns database objects with required properties" {
            $databases | Should -BeOfType Microsoft.SqlServer.Management.Smo.Database
            $databases[0].Name | Should -Not -BeNullOrEmpty
        }

        It "Always includes system databases" {
            $systemDbs = $databases | Where-Object Name -in "master", "model", "msdb", "tempdb"
            $systemDbs.Count | Should -Be 4
        }
    }
}
```

## Additional Instructions

### Test Structure
- Parameter validation must be tagged as Unit Test
- No loose code outside of proper test blocks
- Must maintain all instance reference comments (#TestConfig.instance3, etc.)

### Syntax Requirements
- Use $PSItem instead of $_
- No trailing spaces
- Use $results.Status.Count for accurate counting

### Must Not Use
- $MyInvocation.MyCommand.Name for command names
- Old knownParameters validation approach
- Assumed parameter names - match original tests exactly

# Important
ALL comments must be preserved exactly as they appear in the original code, including seemingly unrelated or end-of-file comments. Even comments that appear to be development notes or temporary must be kept. This is especially important for comments related to CI/CD systems like AppVeyor.