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
        $inst1CurrentMaxValue = (Get-DbaMaxMemory -SqlInstance $TestConfig.InstanceMulti1).MaxValue
        $inst2CurrentMaxValue = (Get-DbaMaxMemory -SqlInstance $TestConfig.InstanceMulti2).MaxValue
    }

    AfterAll {
        $null = Set-DbaMaxMemory -SqlInstance $TestConfig.InstanceMulti1 -Max $inst1CurrentMaxValue -WarningAction SilentlyContinue
        $null = Set-DbaMaxMemory -SqlInstance $TestConfig.InstanceMulti2 -Max $inst2CurrentMaxValue -WarningAction SilentlyContinue
    }

    Context "Connects to multiple instances" {
        BeforeAll {
            $multiInstanceResults = Set-DbaMaxMemory -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Max 1024 -WarningAction SilentlyContinue
        }

        It "Returns 1024 for each instance" {
            foreach ($result in $multiInstanceResults) {
                $result.MaxValue | Should -Be 1024
            }
        }

        Context "Output validation" {
            It "Returns output of the documented type" {
                $multiInstanceResults | Should -Not -BeNullOrEmpty
                $multiInstanceResults | Should -BeOfType [PSCustomObject]
            }

            It "Has the expected default display properties" {
                if (-not $multiInstanceResults) { Set-ItResult -Skipped -Because "no result to validate" }
                $defaultProps = $multiInstanceResults[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
                $expectedDefaults = @(
                    "ComputerName",
                    "InstanceName",
                    "SqlInstance",
                    "Total",
                    "MaxValue",
                    "PreviousMaxValue"
                )
                foreach ($prop in $expectedDefaults) {
                    $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
                }
            }
        }
    }
}