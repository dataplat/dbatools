#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbClone",
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
                "CloneDatabase",
                "ExcludeStatistics",
                "ExcludeQueryStore",
                "UpdateStatistics",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command functions as expected" {
        BeforeAll {
            $dbname = "dbatoolsci_clonetest"
            $clonedb = "dbatoolsci_clonetest_CLONE"
            $clonedb2 = "dbatoolsci_clonetest_CLONE2"

            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $server.Query("CREATE DATABASE $dbname")
        }

        AfterAll {
            Get-DbaDatabase -SqlInstance $server -Database $dbname, $clonedb, $clonedb2 | Remove-DbaDatabase
        }

        It "warns if destination database already exists" {
            $results = Invoke-DbaDbClone -SqlInstance $TestConfig.InstanceSingle -Database $dbname -CloneDatabase tempdb -WarningAction SilentlyContinue
            $WarnVar | Should -Match "exists"
        }

        It "warns if a system db is specified to clone" {
            $results = Invoke-DbaDbClone -SqlInstance $TestConfig.InstanceSingle -Database master -CloneDatabase $clonedb -WarningAction SilentlyContinue
            $WarnVar | Should -Match "user database"
        }

        It "returns 1 result" {
            $results = Invoke-DbaDbClone -SqlInstance $TestConfig.InstanceSingle -Database $dbname -CloneDatabase $clonedb -WarningAction SilentlyContinue
            $results | Should -HaveCount 1
            $results.Name | Should -Be $clonedb
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Invoke-DbaDbClone -SqlInstance $TestConfig.InstanceSingle -Database $dbname -CloneDatabase $clonedb2 -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Database]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Name',
                'Status',
                'IsAccessible',
                'RecoveryModel',
                'LogReuseWaitStatus',
                'Size',
                'Owner',
                'Collation',
                'Encrypted'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}