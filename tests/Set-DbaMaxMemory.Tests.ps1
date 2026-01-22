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
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Set-DbaMaxMemory -SqlInstance $TestConfig.InstanceMulti1 -Max 2048 -WarningAction SilentlyContinue -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Total',
                'MaxValue',
                'PreviousMaxValue'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}