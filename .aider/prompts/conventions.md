# Tasks

1. **Restructure Test Code:**
   - Move all test code into appropriate blocks: `It`, `BeforeAll`, `BeforeEach`, `AfterAll`, or `AfterEach`.
   - Place any file setup code, including the import of `constants.ps1`, into the appropriate blocks at the beginning of each test file.

2. **Update `Describe` and `Context` Blocks:**
   - Ensure that no test code is directly inside `Describe` or `Context` blocks.
   - Properly nest `Context` blocks within `Describe` blocks.

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

- **Importing Constants:**
  - Include the contents of `constants.ps1` at the appropriate place in the test script.
  - Since the variables defined in `constants.ps1` are needed during the discovery phase (e.g., for `-ForEach` loops), import `constants.ps1` within the `BeforeDiscovery` block.
  - This ensures that all global variables are available during both the discovery and execution phases.

- **Variable Scoping:**
  - Replace all `$script:` variable scopes with `$global:` where required for Pester v5 scoping.

- **Comments and Debugging Notes:**
  - Leave comments like `#$script:instance2 for appveyor` intact for debugging purposes.
  - But change `$script:instance2` to `$global:instance2` for proper scoping.
  - So it should look like this: `#$global:instance2 for appveyor`.

- **Consistency with Example:**
  - Follow the structure and conventions used in the example Pester v5 test script provided below.

- **SQL Server-Specific Scenarios:**
  - If you encounter any SQL Server-specific testing scenarios that require special handling, implement the necessary adjustments while maintaining the integrity of the tests.

## Example Pester v5 Test Script

Be literal, even with `Describe "$($TestConfig.CommandName)"`

```powershell
#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param($ModuleName = 'dbatools')
$global:TestConfig = Get-TestConfig

Describe $TestConfig.CommandName {
    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command $TestConfig.CommandName
        }
        $parms = @(
            "SqlInstance",
            "SqlCredential",
            "Database"
        )
        It "Has required parameter: <_>" -ForEach $parms {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "Connects using newly created login" -ForEach $TestConfig.Instances {
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

Describe $TestConfig.CommandName {
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
* start with `#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}` like in the example above.
* Second line must be `param($ModuleName = 'dbatools')` like in the example above.
* -Skip:(whatever) should return true or false, not a string


## Style and instructions

Remember to REMOVE the knownparameters and validate parameters this way:

```powershell
Context "Validate parameters" {
    BeforeAll {
        $command = Get-Command Connect-DbaInstance
    }
    $parms = @(
        "SqlInstance",
        "SqlCredential",
        "Database"
    )
    It "Has required parameter: <_>" -ForEach $parms {
        $command | Should -HaveParameter $PSItem
    }
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

## DO use the $parms variable when referencing parameters

## more instructions

DO NOT USE:
$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")

DO USE:
The static command name provided in the prompt

DO USE:
Double quotes when possible. We are a SQL Server module and single quotes are reserved in T-SQL.