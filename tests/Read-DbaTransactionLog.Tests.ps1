#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Read-DbaTransactionLog",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "IgnoreLimit",
                "RowLimit",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>

Describe $CommandName -Tag IntegrationTests {
    Context "When reading transaction log" {
        BeforeAll {
            $splatRead = @{
                SqlInstance = $TestConfig.instance2
                Database    = "master"
                RowLimit    = 10
            }
            $result = @(Read-DbaTransactionLog @splatRead -OutVariable "global:dbatoolsciOutput")
        }

        It "Should return results" {
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should respect the RowLimit parameter" {
            $result.Count | Should -BeLessOrEqual 10
        }

        It "Should have an Operation column" {
            $result[0].Operation | Should -Not -BeNullOrEmpty
        }

        It "Should have a Context column" {
            $result[0].Context | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [System.Data.DataRow]
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "System\.Data\.DataRow"
        }
    }
}