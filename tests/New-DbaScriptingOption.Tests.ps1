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

    Context "Output Validation" {
        BeforeAll {
            $result = New-DbaScriptingOption
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.ScriptingOptions]
        }

        It "Has commonly used ScriptingOptions properties" {
            $expectedProps = @(
                'ScriptDrops',
                'WithDependencies',
                'AgentAlertJob',
                'AgentNotify',
                'Indexes',
                'Triggers',
                'Permissions',
                'TargetServerVersion'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be accessible on ScriptingOptions object"
            }
        }

        It "Returns a single object" {
            $result | Should -HaveCount 1
        }

        It "Has modifiable properties" {
            $result.ScriptDrops = $true
            $result.ScriptDrops | Should -Be $true
            $result.WithDependencies = $false
            $result.WithDependencies | Should -Be $false
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>