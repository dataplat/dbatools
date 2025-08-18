#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbSynonym",
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
                "Schema",
                "ExcludeSchema",
                "Synonym",
                "ExcludeSynonym",
                "InputObject",
                "EnableException"
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
        $dbname2 = "dbatoolsscidb2_$(Get-Random)"

        $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $dbname
        $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $dbname2
        $null = New-DbaDbSchema -SqlInstance $TestConfig.instance2 -Database $dbname2 -Schema sch2
        $null = New-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Database $dbname -Synonym syn1 -BaseObject obj1
        $null = New-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Database $dbname2 -Synonym syn2 -BaseObject obj2
        $null = New-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Database $dbname2 -Schema sch2 -Synonym syn3 -BaseObject obj2

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname, $dbname2 -Confirm:$false
        $null = Remove-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Confirm:$false

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Functionality" {
        It "Returns Results" {
            $result1 = Get-DbaDbSynonym -SqlInstance $TestConfig.instance2

            $result1.Count | Should -BeGreaterThan 0
        }

        It "Returns all synonyms for all databases" {
            $result2 = Get-DbaDbSynonym -SqlInstance $TestConfig.instance2

            $uniqueDatabases = $result2.Database | Select-Object -Unique
            $uniqueDatabases.Count | Should -BeGreaterThan 1
            $result2.Count | Should -BeGreaterThan 2
        }

        It "Accepts a list of databases" {
            $result3 = Get-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Database $dbname, $dbname2

            $result3.Database | Select-Object -Unique | Should -Be $dbname, $dbname2
        }
        It "Excludes databases" {
            $result4 = Get-DbaDbSynonym -SqlInstance $TestConfig.instance2 -ExcludeDatabase $dbname2

            $uniqueDatabases = $result4.Database | Select-Object -Unique
            $uniqueDatabases | Should -Not -Contain $dbname2
        }

        It "Accepts a list of synonyms" {
            $result5 = Get-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Synonym "syn1", "syn2"

            $result5.Name | Select-Object -Unique | Should -Be "syn1", "syn2"
            $result5.Name | Select-Object -Unique | Should -Be "syn1", "syn2"
        }

        It "Excludes synonyms" {
            $result6 = Get-DbaDbSynonym -SqlInstance $TestConfig.instance2 -ExcludeSynonym "syn2"

            $result6.Name | Select-Object -Unique | Should -Not -Contain "syn2"
            $result6.Name | Select-Object -Unique | Should -Not -Contain "syn2"
        }

        It "Finds synonyms for specified schema only" {
            $result7 = Get-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Schema "sch2"

            $result7.Count | Should -Be 1
        }

        It "Accepts a list of schemas" {
            $result8 = Get-DbaDbSynonym -SqlInstance $TestConfig.instance2 -Schema "dbo", "sch2"

            $result8.Schema | Select-Object -Unique | Should -Be "dbo", "sch2"
            $result8.Schema | Select-Object -Unique | Should -Be "dbo", "sch2"
        }

        It "Excludes schemas" {
            $result9 = Get-DbaDbSynonym -SqlInstance $TestConfig.instance2 -ExcludeSchema "dbo"

            $result9.Schema | Select-Object -Unique | Should -Not -Contain "dbo"
            $result9.Schema | Select-Object -Unique | Should -Not -Contain "dbo"
        }

        It "Input is provided" {
            $result10 = Get-DbaDbSynonym -WarningAction SilentlyContinue -WarningVariable warn > $null

            $warn | Should -Match "You must pipe in a database or specify a SqlInstance"
            $warn | Should -Match "You must pipe in a database or specify a SqlInstance"
        }
    }
}