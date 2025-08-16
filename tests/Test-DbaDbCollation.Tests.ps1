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
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $dbName = "dbatoolsci_collation"
            $null = New-DbaDatabase -SqlInstance $TestConfig.Instance1 -Database $dbName

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Remove-DbaDatabase -SqlInstance $TestConfig.Instance1 -Name $dbName
        }

        It "confirms the db is the same collation as the server" {
            $result = Test-DbaDbCollation -SqlInstance $TestConfig.Instance1 -Database $dbName
            $result.IsEqual | Should -BeTrue
        }
    }
}