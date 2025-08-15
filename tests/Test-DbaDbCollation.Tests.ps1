#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName               = "dbatools",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Test-DbaDbCollation" -Tag 'UnitTests' {
    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Test-DbaDbCollation
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                'SqlInstance',
                'SqlCredential',
                'Database',
                'ExcludeDatabase',
                'EnableException'
            )
        }
        It "Should only contain our specific parameters" {
            $actualParameters = $command.Parameters.Keys | Where-Object { $PSItem -notin "WhatIf", "Confirm" }
            $actualParameters | Should -BeIn $expectedParameters
            $expectedParameters | Should -BeIn $actualParameters
        }
    }
}

Describe "Test-DbaDbCollation Integration Tests" -Tags "IntegrationTests" {

    Context "testing collation of a single database" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.Instance1
            $db1 = "dbatoolsci_collation"
            Get-DbaDatabase -SqlInstance $server -Database $db1 | Remove-DbaDatabase -Confirm:$false
            $server.Query("CREATE DATABASE $db1")
        }
        AfterAll {
            Get-DbaDatabase -SqlInstance $server -Database $db1 | Remove-DbaDatabase -Confirm:$false
        }

        It "confirms the db is the same collation as the server" {
            $result = Test-DbaDbCollation -SqlInstance $TestConfig.Instance1 -Database $db1
            $result.IsEqual | Should -Be $true
        }
    }
}
