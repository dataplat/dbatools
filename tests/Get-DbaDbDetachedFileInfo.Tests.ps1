#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbDetachedFileInfo",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Path",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $versionName = $server.GetSqlServerVersionName()
        $random = Get-Random
        $dbname = "dbatoolsci_detatch_$random"
        $server.Query("CREATE DATABASE $dbname")
        $path = (Get-DbaDbFile -SqlInstance $TestConfig.instance2 -Database $dbname | Where-Object PhysicalName -like "*.mdf").PhysicalName
        Detach-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname -Force
    }

    AfterAll {
        $server.Query("CREATE DATABASE $dbname
            ON (FILENAME = '$path')
            FOR ATTACH")
        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname -Confirm:$false
    }

    Context "Command actually works" {
        BeforeAll {
            $results = Get-DbaDbDetachedFileInfo -SqlInstance $TestConfig.instance2 -Path $path
        }

        It "Gets Results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should be created database" {
            $results.Name | Should -Be $dbname
        }

        It "Should be the correct version" {
            $results.Version | Should -Be $versionName
        }

        It "Should have Data files" {
            $results.DataFiles | Should -Not -BeNullOrEmpty
        }

        It "Should have Log files" {
            $results.LogFiles | Should -Not -BeNullOrEmpty
        }
    }
}