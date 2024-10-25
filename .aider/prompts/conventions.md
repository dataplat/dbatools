# Tasks

1. **Restructure Test Code:**
   - Move all test code into appropriate blocks: `It`, `BeforeAll`, `BeforeEach`, `AfterAll`, or `AfterEach`.
   - Place any file setup code into the appropriate blocks at the beginning of each test file.

2. **Write Clear Test Hierarchies**
- Each `Describe` block should represent a unit of functionality
- Each `Context` block should represent a specific scenario or state
- All test code should be inside `It` blocks
- Avoid loose code in `Describe` or `Context` blocks

Example:
```powershell
# ❌ Avoid this
Describe "Get-DbaDatabase" {
    $results = Get-DbaDatabase # Loose code!

    Context "Basic tests" {
        $databases = $results # More loose code!

        It "Returns results" {
            $databases | Should -Not -BeNullOrEmpty
        }
    }
}

# ✅ Do this instead
Describe "Get-DbaDatabase" {
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

3. **Refactor Skip Conditions:**
   - Move skip logic outside of `BeforeAll` blocks.
   - Use global read-only variables for skip conditions where appropriate.
   - Ensure that `-Skip` parameters evaluate to `$true` or `$false`, not a string.

4. **Update `TestCases`:**
   - Define `TestCases` in a way that is compatible with Pester v5's discovery phase.

5. **Update Assertion Syntax:**
   - Replace assertions like `Should Be` with `Should -Be`.
   - Update other assertion operators as needed (e.g., `Should Throw` to `Should -Throw`).

6. **Modify `InModuleScope` Usage:**
   - Remove `InModuleScope` from around `Describe` and `It` blocks.
   - Use the `-ModuleName` parameter on `Mock` commands where possible.

7. **Update `Invoke-Pester` Calls:**
   - Modify `Invoke-Pester` parameters to align with Pester v5's simple or advanced interface.
   - **Do not use the Legacy parameter set**, as it is deprecated and may not work correctly.

8. **Adjust Mocking Syntax:**
   - Update any mock definitions to Pester v5 syntax.

9. **Remove Parameter Testing Using `knownparameters`:**
   - Identify any existing "Validate parameters" contexts that use `knownparameters` sections
   - Remove the entire "Validate parameters" context and replace it with the Pester v5 approach using `Should -HaveParameter`, as shown in the example Pester v5 test script.

10. **Use TestCases Whenever Possible:**
    - Look for opportunities to use TestCases in the test code.
    - Convert existing tests to use TestCases when applicable.
    - Define TestCases using the `ForEach` parameter in the `It` block, as shown in the example below.

## Instructions

- **Variable Scoping:**
  - Replace all `$script:` variable scopes with `$global:` where required for Pester v5 scoping.

- **Comments and Debugging Notes:**
  - Leave comments like `#$TestConfig.instance2 for appveyor` intact for debugging purposes.

- **SQL Server-Specific Scenarios:**
  - If you encounter any SQL Server-specific testing scenarios that require special handling, implement the necessary adjustments while maintaining the integrity of the tests.

- **Consistency with Example:**
  - Follow the structure and conventions used in the example Pester v5 test script provided below.

## Example Pester v5 Test Script

```powershell
#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param($ModuleName = 'dbatools')
$global:TestConfig = Get-TestConfig

Describe "Measure-DbaDiskSpaceRequirement" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command $TestConfig.CommandName

            $expectedParameters = @(
                'Source'
                'Database'
                'SourceSqlCredential'
                'Destination'
                'DestinationDatabase'
                'DestinationSqlCredential'
                'Credential'
                'EnableException'
            )

            $actualParameters = $command.Parameters | Where-Object Keys -notin 'WhatIf', 'Confirm'
        }

        It "Should have the expected number of parameters" {
            $difference = Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $actualParameters.Keys
            $difference | Should -BeNullOrEmpty
        }

        # You can still include your individual parameter checks too
        It "Has parameter: <_>" -ForEach $expectedParameters {
            $command | Should -HaveParameter $PSItem
        }
    }
}

Describe "Measure-DbaDiskSpaceRequirement" -Tag "IntegrationTests" {
    Context "Successfully connects using newly created login" -ForEach $TestConfig.Instances {
        BeforeAll {
            $loginName = "dbatoolsci_login_$(Get-Random)"
            $securePassword = ConvertTo-SecureString -String "P@ssw0rd$(Get-Random)" -AsPlainText -Force
            $credential = [PSCredential]::new($loginName, $securePassword)
            New-DbaLogin -SqlInstance $PSItem -Login $loginName -Password $securePassword -Confirm:$false
        }

        AfterAll {
            Remove-DbaLogin -SqlInstance $PSItem -Login $loginName -Confirm:$false
        }

        It "Connects successfully" {
            $instance = Connect-DbaInstance -SqlInstance $PSItem -SqlCredential $credential
            $instance.Name | Should -Be $PSItem.Split('\')[0]
        }
    }
}
```

## Example Pester v5 Test Script with TestCases

```powershell
#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param($ModuleName = 'dbatools')
$global:TestConfig = Get-TestConfig

Describe "Measure-DbaSomething" {
    It "Should calculate the correct result" -ForEach @(
        @{ Input1 = 1; Input2 = 2; Expected = 3 }
        @{ Input1 = 2; Input2 = 3; Expected = 5 }
        @{ Input1 = 3; Input2 = 4; Expected = 7 }
    ) {
        $result = Add-Numbers -Number1 $Input1 -Number2 $Input2
        $result | Should -Be $Expected
    }
}
```

## Additional Guidelines
* Start with `#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}` like in the example above
* Second line must be `param($ModuleName = 'dbatools')` like in the example above
* -Skip:(whatever) should return true or false, not a string
* Update our Contexts to be more descriptive of the tests

## Style and instructions

Remember to REMOVE the knownparameters and validate parameters this way:

```powershell
It "Has parameter: <_>" -ForEach $expectedParameters {
    $command | Should -HaveParameter $PSItem
}
```

## DO NOT list parameters like this

```powershell
$parms = @('SqlInstance','SqlCredential','Database')
```

## DO list parameters like this

```powershell
$parms = @(
    "SqlInstance",
    "SqlCredential",
    "Database"
)
```

## Important instructions

DO NOT USE:
$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")

DO USE:
The static command name provided in the prompt

DO USE:
Double quotes when possible. We are a SQL Server module and single quotes are reserved in T-SQL.

DO NOT:
Add back constants.ps1 or the old style $knownParameters test: we removed those requirements