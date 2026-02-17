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
    BeforeAll {
        $global:dbatoolsciOutput = New-DbaScriptingOption
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput | Should -BeOfType [Microsoft.SqlServer.Management.Smo.ScriptingOptions]
        }

        It "Should have expected boolean properties" {
            $global:dbatoolsciOutput.ScriptDrops | Should -BeOfType [bool]
            $global:dbatoolsciOutput.WithDependencies | Should -BeOfType [bool]
            $global:dbatoolsciOutput.Indexes | Should -BeOfType [bool]
            $global:dbatoolsciOutput.Triggers | Should -BeOfType [bool]
            $global:dbatoolsciOutput.Permissions | Should -BeOfType [bool]
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.ScriptingOptions"
        }
    }
}