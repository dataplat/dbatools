#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbFileGrowth",
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
                "Database",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Should return file information" {
        It "returns information about msdb files" {
            $result = Get-DbaDbFileGrowth -SqlInstance $TestConfig.InstanceSingle
            $result.Database -contains "msdb" | Should -Be $true
        }
    }

    Context "Should return file information for only msdb" {
        It "returns only msdb files" {
            $result = Get-DbaDbFileGrowth -SqlInstance $TestConfig.InstanceSingle -Database msdb | Select-Object -First 1
            $result.Database | Should -Be "msdb"
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaDbFileGrowth -SqlInstance $TestConfig.InstanceSingle -Database msdb -EnableException | Select-Object -First 1
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Database',
                'MaxSize',
                'GrowthType',
                'Growth',
                'File',
                'FileName',
                'State'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has additional properties available" {
            $additionalProps = @(
                'DatabaseID',
                'FileGroupName',
                'ID',
                'Type',
                'TypeDescription',
                'LogicalName',
                'PhysicalName',
                'NextGrowthEventSize',
                'Size',
                'UsedSpace',
                'AvailableSpace'
            )
            $allProps = ($result | Select-Object -Property *).PSObject.Properties.Name
            foreach ($prop in $additionalProps) {
                $allProps | Should -Contain $prop -Because "additional property '$prop' should be accessible"
            }
        }
    }
}