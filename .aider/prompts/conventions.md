# Pester v5 Test Standards

## Core Requirements
```powershell
#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param($ModuleName = "dbatools")
$global:TestConfig = Get-TestConfig
```
These three lines must start every test file.

## Test Structure

### Describe Blocks
- Name your Describe blocks with static command names
- Include appropriate tags (`-Tag "UnitTests"` or `-Tag "IntegrationTests"`)
- One command per Describe block

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

## TestCases
Use the `-ForEach` parameter in `It` blocks for multiple test cases:

```powershell
It "Should calculate correctly" -ForEach @(
    @{ Input = 1; Expected = 2 }
    @{ Input = 2; Expected = 4 }
    @{ Input = 3; Expected = 6 }
) {
    $result = Get-Double -Number $Input
    $result | Should -Be $Expected
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
$actualParameters = $command.Parameters.Keys | Where-Object { $PSItem -notin "WhatIf", "Confirm" }
```

## DO NOT
- DO NOT use `$MyInvocation.MyCommand.Name` to get command names
- DO NOT use the old `knownParameters` validation approach
- DO NOT include loose code outside of proper test blocks
- DO NOT remove comments like "#TestConfig.instance3" or "#$TestConfig.instance2 for appveyor"

## Examples

### Good Parameter Test

```powershell
Describe "Get-DbaDatabase" -Tag "UnitTests" {
   Context "Parameter validation" {
       BeforeAll {
           $command = Get-Command Get-DbaDatabase
           $expectedParameters  = $TestConfig.CommonParameters

           $expectedParameters += @(
               "SqlInstance",
               "SqlCredential",
               "Database"
           )
       }

       It "Should have exactly the expected parameters" {
           $actualParameters = $command.Parameters.Keys | Where-Object { $PSItem -notin "WhatIf", "Confirm" }
           Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $actualParameters | Should -BeNullOrEmpty
       }

       It "Has parameter: <_>" -ForEach $expectedParameters {
           $command | Should -HaveParameter $PSItem
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

### Good parameter splat usage
- Use splatting for commands with 4+ parameters
- Use $splat/@splat variable names

```powershell
# Good - direct parameters for 1-3 parameters
$ag = New-DbaLogin -SqlInstance $instance -Login $loginName -Password $password

# Good - splatting for 4+ parameters
$splat = @{
    Primary       = $TestConfig.instance3
    Name          = $agname
    ClusterType   = "None"
    FailoverMode  = "Manual"
    Certificate   = "dbatoolsci_AGCert"
    Confirm       = $false
}
$ag = New-DbaAvailabilityGroup @splat
```