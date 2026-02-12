#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaDiskAlignment",
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
                "SqlCredential",
                "NoSqlCheck",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        It "Should return a result" {
            $results = Test-DbaDiskAlignment -ComputerName $TestConfig.InstanceSingle
            $results | Should -Not -Be $null
        }

        It "Should return a result not using sql" {
            $script:outputForValidation = Test-DbaDiskAlignment -NoSqlCheck -ComputerName $TestConfig.InstanceSingle
            $script:outputForValidation | Should -Not -Be $null
        }

        Context "Output validation" {
            It "Returns output of the expected type" {
                $script:outputForValidation | Should -Not -BeNullOrEmpty
                $script:outputForValidation[0] | Should -BeOfType PSCustomObject
            }

            It "Has the expected properties" {
                if (-not $script:outputForValidation) { Set-ItResult -Skipped -Because "no result to validate" }
                $expectedProps = @("ComputerName", "Name", "PartitionSize", "PartitionType", "TestingStripeSize", "OffsetModuluCalculation", "StartingOffset", "IsOffsetBestPractice", "IsBestPractice", "NumberOfBlocks", "BootPartition", "PartitionBlockSize", "IsDynamicDisk")
                foreach ($prop in $expectedProps) {
                    $script:outputForValidation[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present on the output object"
                }
            }
        }
    }
}