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

    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $outputTestDb = "dbatoolsci_recmodel_output"
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $outputTestDb -ErrorAction SilentlyContinue -Confirm:$false
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $outputTestDb
            $result = Set-DbaDbRecoveryModel -SqlInstance $TestConfig.InstanceSingle -Database $outputTestDb -RecoveryModel Simple -Confirm:$false

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $outputTestDb -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Database"
        }

        It "Has the expected default display properties" {
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Name",
                "Status",
                "IsAccessible",
                "RecoveryModel",
                "LastFullBackup",
                "LastDiffBackup",
                "LastLogBackup"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has working alias properties" {
            $result[0].psobject.Properties["LastFullBackup"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["LastFullBackup"].MemberType | Should -Be "AliasProperty"
            $result[0].psobject.Properties["LastDiffBackup"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["LastDiffBackup"].MemberType | Should -Be "AliasProperty"
            $result[0].psobject.Properties["LastLogBackup"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["LastLogBackup"].MemberType | Should -Be "AliasProperty"
        }
    }
}