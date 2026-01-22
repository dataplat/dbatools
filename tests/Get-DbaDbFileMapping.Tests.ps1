#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbFileMapping",
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
    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaDbFileMapping -SqlInstance $TestConfig.InstanceSingle -Database master -EnableException
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
                'FileMapping'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "FileMapping property is a hashtable" {
            $result.FileMapping | Should -BeOfType [hashtable]
        }

        It "FileMapping contains logical-to-physical file mappings" {
            $result.FileMapping.Keys.Count | Should -BeGreaterThan 0 -Because "database should have at least one file"
        }
    }

    Context "Should return file information" {
        It "returns information about multiple databases" {
            $results = Get-DbaDbFileMapping -SqlInstance $TestConfig.InstanceSingle
            $results.Database -contains "tempdb" | Should -Be $true
            $results.Database -contains "master" | Should -Be $true
        }
    }

    Context "Should return file information for a single database" {
        It "returns information about tempdb" {
            $results = Get-DbaDbFileMapping -SqlInstance $TestConfig.InstanceSingle -Database tempdb
            $results.Database -contains "tempdb" | Should -Be $true
            $results.Database -contains "master" | Should -Be $false
        }
    }
}