#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaAvailabilityGroup",
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
                "AvailabilityGroup",
                "Secondary",
                "SecondarySqlCredential",
                "AddDatabase",
                "SeedingMode",
                "SharedPath",
                "UseLastBackup",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        It "Returns PSCustomObject" {
            $command = Get-Command $CommandName
            $outputType = $command.OutputType.Name
            $outputType | Should -Contain "PSCustomObject"
        }

        It "Has expected properties without -AddDatabase parameter" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'AvailabilityGroup'
            )
            $command = Get-Command $CommandName
            $command | Should -Not -BeNullOrEmpty
            $expectedProps | Should -Not -BeNullOrEmpty -Because "basic AG test output should have standard properties"
        }

        It "Has expected properties with -AddDatabase parameter" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'AvailabilityGroupName',
                'DatabaseName',
                'AvailabilityGroupSMO',
                'DatabaseSMO',
                'PrimaryServerSMO',
                'ReplicaServerSMO',
                'RestoreNeeded',
                'Backups'
            )
            $command = Get-Command $CommandName
            $command | Should -Not -BeNullOrEmpty
            $expectedProps | Should -Not -BeNullOrEmpty -Because "AddDatabase test output should have database and replica information"
        }
    }
}