#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbCompatibility",
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
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $compatibilityLevel = $server.Databases["master"].CompatibilityLevel
    }

    Context "Gets compatibility for multiple databases" {
        BeforeAll {
            $results = Get-DbaDbCompatibility -SqlInstance $TestConfig.InstanceSingle
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should return correct compatibility level for system databases" {
            foreach ($row in $results) {
                # Only test system databases as there might be leftover databases from other tests
                if ($row.DatabaseId -le 4) {
                    $row.Compatibility | Should -Be $compatibilityLevel
                }
                $dbId = (Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $row.Database).Id
                $row.DatabaseId | Should -Be $dbId
            }
        }
    }

    Context "Gets compatibility for one database" {
        BeforeAll {
            $results = Get-DbaDbCompatibility -SqlInstance $TestConfig.InstanceSingle -Database master
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should return correct compatibility level for master database" {
            $results.Compatibility | Should -Be $compatibilityLevel
            $masterDbId = (Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database master).Id
            $results.DatabaseId | Should -Be $masterDbId
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaDbCompatibility -SqlInstance $TestConfig.InstanceSingle -Database master -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "DatabaseId",
                "Compatibility"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in output"
            }
        }

        It "Has ComputerName property with a value" {
            $result.ComputerName | Should -Not -BeNullOrEmpty
        }

        It "Has InstanceName property with a value" {
            $result.InstanceName | Should -Not -BeNullOrEmpty
        }

        It "Has SqlInstance property with a value" {
            $result.SqlInstance | Should -Not -BeNullOrEmpty
        }

        It "Has Database property with expected value" {
            $result.Database | Should -Be "master"
        }

        It "Has DatabaseId property with a value" {
            $result.DatabaseId | Should -BeOfType [System.Int32]
            $result.DatabaseId | Should -BeGreaterThan 0
        }

        It "Has Compatibility property with a value" {
            $result.Compatibility | Should -Not -BeNullOrEmpty
        }
    }
}