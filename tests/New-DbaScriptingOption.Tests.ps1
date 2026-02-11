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
    Context "Output validation" {
        BeforeAll {
            $result = New-DbaScriptingOption
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result.GetType().FullName | Should -Be "Microsoft.SqlServer.Management.Smo.ScriptingOptions"
        }

        It "Has common scripting option properties" {
            $result.psobject.Properties["ScriptDrops"] | Should -Not -BeNullOrEmpty
            $result.psobject.Properties["WithDependencies"] | Should -Not -BeNullOrEmpty
            $result.psobject.Properties["Indexes"] | Should -Not -BeNullOrEmpty
            $result.psobject.Properties["Triggers"] | Should -Not -BeNullOrEmpty
            $result.psobject.Properties["Permissions"] | Should -Not -BeNullOrEmpty
        }

        It "Has modifiable properties" {
            $result.ScriptDrops = $true
            $result.ScriptDrops | Should -BeTrue
            $result.ScriptDrops = $false
            $result.ScriptDrops | Should -BeFalse
        }
    }
}