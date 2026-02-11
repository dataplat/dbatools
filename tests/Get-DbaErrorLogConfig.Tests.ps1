#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaErrorLogConfig",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Get NumberErrorLog for multiple instances" {
        BeforeAll {
            $allResults = @()
            $allResults += Get-DbaErrorLogConfig -SqlInstance $TestConfig.InstanceMulti2, $TestConfig.InstanceMulti1
        }

        It "Returns error log configuration objects" {
            $allResults | Should -Not -BeNullOrEmpty
        }

        It "Returns 3 values for each instance" {
            foreach ($result in $allResults) {
                $result.LogCount | Should -Not -Be $null
                $result.LogSize | Should -Not -Be $null
                $result.LogPath | Should -Not -Be $null
            }
        }
    }

    Context "Output validation" {
        BeforeAll {
            $result = Get-DbaErrorLogConfig -SqlInstance $TestConfig.InstanceMulti1
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected properties" {
            $result | Should -Not -BeNullOrEmpty
            $expectedProps = @("ComputerName", "InstanceName", "SqlInstance", "LogCount", "LogSize", "LogPath")
            foreach ($prop in $expectedProps) {
                $result.PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }
    }
}