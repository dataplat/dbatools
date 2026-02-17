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
            $multiInstanceResults = Set-DbaMaxMemory -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Max 1024 -WarningAction SilentlyContinue -OutVariable "global:dbatoolsciOutput"
        }

        It "Returns 1024 for each instance" {
            foreach ($result in $multiInstanceResults) {
                $result.MaxValue | Should -Be 1024
            }
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Total",
                "MaxValue",
                "PreviousMaxValue"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}