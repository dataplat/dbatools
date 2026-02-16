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
            $results = Get-DbaIoLatency -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"
            $results.Count -gt 0 | Should -Be $true
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
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
                "SizeOnDiskBytes",
                "FileHandle",
                "ReadLatency",
                "WriteLatency",
                "Latency",
                "AvgBPerRead",
                "AvgBPerWrite",
                "AvgBPerTransfer"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
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
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}