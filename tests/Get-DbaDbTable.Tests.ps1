#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbTable",
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
                "IncludeSystemDBs",
                "Table",
                "EnableException",
                "InputObject",
                "Schema"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $dbname = "dbatoolsscidb_$(Get-Random)"
        $tablename = "dbatoolssci_$(Get-Random)"

        $null = New-DbaDatabase -SqlInstance $TestConfig.instance1 -Name $dbname -Owner sa
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Database $dbname -Query "Create table $tablename (col1 int)"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Database $dbname -Query "drop table $tablename"
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbname -Confirm:$false

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Should get the table" {
        It "Gets the table" {
            (Get-DbaDbTable -SqlInstance $TestConfig.instance1).Name | Should -Contain $tablename
            (Get-DbaDbTable -SqlInstance $TestConfig.instance1).Name | Should -Contain $tablename
        }

        It "Gets the table when you specify the database" {
            (Get-DbaDbTable -SqlInstance $TestConfig.instance1 -Database $dbname).Name | Should -Contain $tablename
            (Get-DbaDbTable -SqlInstance $TestConfig.instance1 -Database $dbname).Name | Should -Contain $tablename
        }
    }

    Context "Should not get the table if database is excluded" {
        It "Doesn't find the table" {
            (Get-DbaDbTable -SqlInstance $TestConfig.instance1 -ExcludeDatabase $dbname).Name | Should -Not -Contain $tablename
            (Get-DbaDbTable -SqlInstance $TestConfig.instance1 -ExcludeDatabase $dbname).Name | Should -Not -Contain $tablename
        }
    }
}