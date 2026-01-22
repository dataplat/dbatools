#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbRecoveryModel",
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
                "RecoveryModel",
                "Database",
                "ExcludeDatabase",
                "AllDatabases",
                "EnableException",
                "InputObject"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Recovery model is correctly set" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $dbname = "dbatoolsci_recoverymodel"
            Get-DbaDatabase -SqlInstance $server -Database $dbname | Remove-DbaDatabase
            $server.Query("CREATE DATABASE $dbname")

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname | Remove-DbaDatabase

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "sets the proper recovery model" {
            $results = Set-DbaDbRecoveryModel -SqlInstance $TestConfig.InstanceSingle -Database $dbname -RecoveryModel BulkLogged
            $results.RecoveryModel -eq "BulkLogged" | Should -Be $true
        }

        It "supports the pipeline" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname | Set-DbaDbRecoveryModel -RecoveryModel Simple
            $results.RecoveryModel -eq "Simple" | Should -Be $true
        }

        It "requires Database, ExcludeDatabase or AllDatabases" {
            $results = Set-DbaDbRecoveryModel -SqlInstance $TestConfig.InstanceSingle -RecoveryModel Simple -WarningAction SilentlyContinue -WarningVariable warn
            $warn -match "AllDatabases" | Should -Be $true
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Set-DbaDbRecoveryModel -SqlInstance $TestConfig.InstanceSingle -Database $dbname -RecoveryModel Full -EnableException
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
                'LastFullBackup',
                'LastDiffBackup',
                'LastLogBackup'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}