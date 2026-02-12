#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaIoLatency",
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
    Context "When connecting to SQL Server" {
        It "Returns results" {
            $results = Get-DbaIoLatency -SqlInstance $TestConfig.InstanceSingle
            $results.Count -gt 0 | Should -Be $true
        }
    }

    Context "Output validation" {
        BeforeAll {
            $result = Get-DbaIoLatency -SqlInstance $TestConfig.InstanceSingle
        }

        It "Returns output of the expected type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected default display properties" {
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "DatabaseId",
                "DatabaseName",
                "FileId",
                "PhysicalName",
                "NumberOfReads",
                "IoStallRead",
                "NumberOfwrites",
                "IoStallWrite",
                "IoStall",
                "NumberOfBytesRead",
                "NumberOfBytesWritten",
                "SampleMilliseconds",
                "SizeOnDiskBytes"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has the excluded properties available but not in default display" {
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $excludedProps = @(
                "FileHandle",
                "ReadLatency",
                "WriteLatency",
                "Latency",
                "AvgBPerRead",
                "AvgBPerWrite",
                "AvgBPerTransfer"
            )
            foreach ($prop in $excludedProps) {
                $defaultProps | Should -Not -Contain $prop -Because "property '$prop' should be excluded from default display"
                $result[0].psobject.Properties[$prop] | Should -Not -BeNullOrEmpty -Because "property '$prop' should still exist on the object"
            }
        }
    }
}