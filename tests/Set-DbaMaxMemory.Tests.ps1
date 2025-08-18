#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaMaxMemory",
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
                "Max",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $inst1CurrentMaxValue = (Get-DbaMaxMemory -SqlInstance $TestConfig.instance1).MaxValue
        $inst2CurrentMaxValue = (Get-DbaMaxMemory -SqlInstance $TestConfig.instance2).MaxValue
    }

    AfterAll {
        $null = Set-DbaMaxMemory -SqlInstance $TestConfig.instance1 -Max $inst1CurrentMaxValue
        $null = Set-DbaMaxMemory -SqlInstance $TestConfig.instance2 -Max $inst2CurrentMaxValue
    }

    Context "Connects to multiple instances" {
        BeforeAll {
            $multiInstanceResults = Set-DbaMaxMemory -SqlInstance $TestConfig.instance1, $TestConfig.instance2 -Max 1024
        }

        It "Returns 1024 for each instance" {
            foreach ($result in $multiInstanceResults) {
                $result.MaxValue | Should -Be 1024
            }
        }
    }
}