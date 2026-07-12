#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaScriptingOption",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It -Skip "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    # Characterization tests (TA-035): the command news up an SMO ScriptingOptions object
    # locally - no SQL instance or network needed.

    Context "Scripting options object" {
        It "Returns a Microsoft.SqlServer.Management.Smo.ScriptingOptions object" {
            $options = New-DbaScriptingOption
            $options | Should -BeOfType Microsoft.SqlServer.Management.Smo.ScriptingOptions
        }

        It "Returns a fresh instance on every call" {
            $first = New-DbaScriptingOption
            $second = New-DbaScriptingOption
            $first.ScriptDrops = $true
            $second.ScriptDrops | Should -BeFalse
        }

        It "Carries the SMO defaults for the documented toggles" {
            $options = New-DbaScriptingOption
            $options.ScriptDrops | Should -BeFalse
            $options.WithDependencies | Should -BeFalse
            $options.IncludeIfNotExists | Should -BeFalse
            $options.NoCollation | Should -BeFalse
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>