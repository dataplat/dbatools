#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName   = "dbatools",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Test-DbaDbCollation" -Tag 'UnitTests' {
    Context "Validate parameters" {
        It "Should only contain our specific parameters" {
            $command = Get-Command Test-DbaDbCollation
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                'SqlInstance',
                'SqlCredential',
                'Database',
                'ExcludeDatabase',
                'EnableException'
            )
            $actualParameters = $command.Parameters.Keys | Where-Object { $PSItem -notin "WhatIf", "Confirm" }
            $actualParameters | Should -BeIn $expectedParameters
            $expectedParameters | Should -BeIn $actualParameters
        }
    }
}

Describe "Test-DbaDbCollation Integration Tests" -Tags "IntegrationTests" {

    Context "testing collation of a single database" {
        It "confirms the db is the same collation as the server" {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.Instance1
            $db1 = "dbatoolsci_collation"
            Get-DbaDatabase -SqlInstance $server -Database $db1 | Remove-DbaDatabase -Confirm:$false
            $server.Query("CREATE DATABASE $db1")

            try {
                $result = Test-DbaDbCollation -SqlInstance $TestConfig.Instance1 -Database $db1
                $result.IsEqual | Should -Be $true
            } catch {
                Get-DbaDatabase -SqlInstance $server -Database $db1 | Remove-DbaDatabase -Confirm:$false
            }
        }
    }
}