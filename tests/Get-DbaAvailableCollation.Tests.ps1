#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaAvailableCollation",
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
    Context "Available Collations" {
        It "finds a collation that matches Slovenian" {
            $results = Get-DbaAvailableCollation -SqlInstance $TestConfig.InstanceSingle
            ($results.Name -match "Slovenian").Count | Should -BeGreaterThan 10
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaAvailableCollation -SqlInstance $TestConfig.InstanceSingle -EnableException
        }

        It "Returns the documented output type" {
            $result[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Collation]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Name',
                'CodePage',
                'CodePageName',
                'LocaleID',
                'LocaleName',
                'Description'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Returns multiple collation objects" {
            $result.Count | Should -BeGreaterThan 100 -Because "SQL Server supports many collations"
        }

        It "Has ComputerName property populated by dbatools" {
            $result[0].ComputerName | Should -Not -BeNullOrEmpty
        }

        It "Has InstanceName property populated by dbatools" {
            $result[0].InstanceName | Should -Not -BeNullOrEmpty
        }

        It "Has SqlInstance property populated by dbatools" {
            $result[0].SqlInstance | Should -Not -BeNullOrEmpty
        }

        It "Has CodePageName property populated by dbatools" {
            $result | Where-Object CodePageName | Should -Not -BeNullOrEmpty
        }

        It "Has LocaleName property populated by dbatools" {
            $result | Where-Object LocaleName | Should -Not -BeNullOrEmpty
        }
    }
}