#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaKerberos",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "ComputerName",
                "SqlCredential",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Should have SqlInstance in Instance parameter set" {
            $command = Get-Command $CommandName
            $instanceSet = $command.ParameterSets | Where-Object Name -eq "Instance"
            $instanceSet.Parameters.Name | Should -Contain "SqlInstance"
        }

        It "Should have ComputerName in Computer parameter set" {
            $command = Get-Command $CommandName
            $computerSet = $command.ParameterSets | Where-Object Name -eq "Computer"
            $computerSet.Parameters.Name | Should -Contain "ComputerName"
        }
    }
}

#$TestConfig.instance2
#$TestConfig.instance3
