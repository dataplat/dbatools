#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaDiskAllocation",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "NoSqlCheck",
                "SqlCredential",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        It "Should return a result" {
            $results = Test-DbaDiskAllocation -ComputerName $TestConfig.InstanceSingle
            $results | Should -Not -Be $null
        }

        It "Should return a result not using sql" {
            $results = Test-DbaDiskAllocation -NoSqlCheck -ComputerName $TestConfig.InstanceSingle
            $results | Should -Not -Be $null
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Test-DbaDiskAllocation -ComputerName $TestConfig.InstanceSingle -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'DiskName',
                'DiskLabel',
                'BlockSize',
                'IsSqlDisk',
                'IsBestPractice'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has backward compatibility aliases" {
            $result[0].Server | Should -Be $result[0].ComputerName
            $result[0].Name | Should -Be $result[0].DiskName
            $result[0].Label | Should -Be $result[0].DiskLabel
        }
    }

    Context "Output with -NoSqlCheck" {
        BeforeAll {
            $result = Test-DbaDiskAllocation -ComputerName $TestConfig.InstanceSingle -NoSqlCheck -EnableException
        }

        It "Omits IsSqlDisk property when -NoSqlCheck specified" {
            $actualProps = $result[0].PSObject.Properties.Name
            $actualProps | Should -Not -Contain 'IsSqlDisk' -Because "-NoSqlCheck should skip SQL Server detection"
        }

        It "Still includes core properties" {
            $expectedProps = @(
                'ComputerName',
                'DiskName',
                'DiskLabel',
                'BlockSize',
                'IsBestPractice'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop
            }
        }
    }
}