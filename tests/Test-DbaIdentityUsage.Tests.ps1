#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaIdentityUsage",
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
                "ExcludeDatabase",
                "Threshold",
                "ExcludeSystem",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Verify Test Identity Usage on TinyInt" {
        BeforeAll {
            $global:table1 = "TestTable_$(Get-Random)"
            $tableDDL = "CREATE TABLE $global:table1 (testId TINYINT IDENTITY(1,1),testData DATETIME2 DEFAULT getdate() )"
            Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Query $tableDDL -Database TempDb

            $insertSql = "INSERT INTO $global:table1 (testData) DEFAULT VALUES"
            for ($i = 1; $i -le 128; $i++) {
                Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Query $insertSql -Database TempDb
            }
            $global:results128 = Test-DbaIdentityUsage -SqlInstance $TestConfig.instance1 -Database TempDb | Where-Object Table -eq $global:table1

            for ($i = 1; $i -le 127; $i++) {
                Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Query $insertSql -Database TempDb
            }
            $global:results255 = Test-DbaIdentityUsage -SqlInstance $TestConfig.instance1 -Database TempDb | Where-Object Table -eq $global:table1
        }

        AfterAll {
            $cleanup = "Drop table $global:table1"
            Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Query $cleanup -Database TempDb
        }

        It "Identity column should have 128 uses" {
            $global:results128.NumberOfUses | Should -Be 128
        }

        It "TinyInt identity column with 128 rows inserted should be 50.20% full" {
            $global:results128.PercentUsed | Should -Be 50.20
        }

        It "Identity column should have 255 uses" {
            $global:results255.NumberOfUses | Should -Be 255
        }

        It "TinyInt with 255 rows should be 100% full" {
            $global:results255.PercentUsed | Should -Be 100
        }
    }

    Context "Verify Test Identity Usage with increment of 5" {
        BeforeAll {
            $global:table2 = "TestTable_$(Get-Random)"
            $tableDDL = "CREATE TABLE $global:table2 (testId tinyint IDENTITY(0,5),testData DATETIME2 DEFAULT getdate() )"
            Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Query $tableDDL -Database TempDb

            $insertSql = "INSERT INTO $global:table2 (testData) DEFAULT VALUES"
            for ($i = 1; $i -le 25; $i++) {
                Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Query $insertSql -Database TempDb
            }
            $global:results25 = Test-DbaIdentityUsage -SqlInstance $TestConfig.instance1 -Database TempDb | Where-Object Table -eq $global:table2
        }

        AfterAll {
            $cleanup = "Drop table $global:table2"
            Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Query $cleanup -Database TempDb
        }

        It "Identity column should have 24 uses" {
            $global:results25.NumberOfUses | Should -Be 24
        }

        It "TinyInt identity column with 25 rows using increment of 5 should be 47.06% full" {
            $global:results25.PercentUsed | Should -Be 47.06
        }
    }
}