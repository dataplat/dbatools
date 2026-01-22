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

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaIoLatency -SqlInstance $TestConfig.instance1 -EnableException
        }

        It "Returns PSCustomObject" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
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
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has the expected hidden properties accessible via Select-Object *" {
            $hiddenProps = @(
                "FileHandle",
                "ReadLatency",
                "WriteLatency",
                "Latency",
                "AvgBPerRead",
                "AvgBPerWrite",
                "AvgBPerTransfer"
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $hiddenProps) {
                $actualProps | Should -Contain $prop -Because "hidden property '$prop' should be accessible"
            }
        }
    }
}