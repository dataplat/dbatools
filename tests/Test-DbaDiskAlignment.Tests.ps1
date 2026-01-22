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
            $results = Test-DbaDiskAlignment -NoSqlCheck -ComputerName $TestConfig.InstanceSingle
            $results | Should -Not -Be $null
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Test-DbaDiskAlignment -ComputerName $TestConfig.InstanceSingle -NoSqlCheck -EnableException
        }

        It "Returns PSCustomObject" {
            $result[0].PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected properties" {
            $expectedProps = @(
                "ComputerName",
                "Name",
                "PartitionSize",
                "PartitionType",
                "TestingStripeSize",
                "OffsetModuluCalculation",
                "StartingOffset",
                "IsOffsetBestPractice",
                "IsBestPractice",
                "NumberOfBlocks",
                "BootPartition",
                "PartitionBlockSize",
                "IsDynamicDisk"
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in output"
            }
        }

        It "Returns multiple objects per partition (one per stripe size tested)" {
            $result.Count | Should -BeGreaterOrEqual 5 -Because "at least one partition should return 5 stripe size test results"
        }

        It "Has DbaSize type properties for size-related fields" {
            $result[0].PartitionSize | Should -BeOfType [Dataplat.Dbatools.Utility.DbaSize]
            $result[0].TestingStripeSize | Should -BeOfType [Dataplat.Dbatools.Utility.DbaSize]
            $result[0].OffsetModuluCalculation | Should -BeOfType [Dataplat.Dbatools.Utility.DbaSize]
            $result[0].StartingOffset | Should -BeOfType [Dataplat.Dbatools.Utility.DbaSize]
        }

        It "Tests all common stripe unit sizes" {
            $stripesSizes = $result.TestingStripeSize.Byte | Select-Object -Unique | Sort-Object
            $expectedSizes = @(65536, 131072, 262144, 524288, 1048576) # 64KB, 128KB, 256KB, 512KB, 1024KB in bytes
            $stripesSizes | Should -Be $expectedSizes -Because "should test against all 5 common stripe unit sizes"
        }
    }
}