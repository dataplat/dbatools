#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaSpn",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When getting SPN information" {
        BeforeAll {
            $results = Test-DbaSpn -ComputerName $TestConfig.InstanceSingle
        }

        It "Returns some results" {
            $results.RequiredSPN | Should -Not -BeNullOrEmpty
        }

        It "Has the required properties for all results" {
            foreach ($result in $results) {
                $result.RequiredSPN | Should -Match "MSSQLSvc"
                $result.TcpEnabled | Should -Be $true
                $result.IsSet | Should -BeOfType [bool]
            }
        }
    }
}