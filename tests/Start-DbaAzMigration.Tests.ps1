#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Start-DbaAzMigration",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "Destination",
                "SourceSqlCredential",
                "DestinationSqlCredential",
                "Database",
                "ExcludeDatabase",
                "Path",
                "ExportDacOption",
                "ImportDacOption",
                "Force",
                "KeepBacpac",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $script:testInstance = if ($TestConfig.InstanceSingle) { $TestConfig.InstanceSingle } else { "localhost" }
    }

    Context "Boundary validation" {
        It "Rejects an invalid export option before connecting" {
            $splatMigration = @{
                Source          = $script:testInstance
                Destination     = $script:testInstance
                ExportDacOption = [pscustomobject]@{ Name = "invalid" }
                EnableException = $true
            }
            if ($TestConfig.SqlCred) {
                $splatMigration.SourceSqlCredential = $TestConfig.SqlCred
                $splatMigration.DestinationSqlCredential = $TestConfig.SqlCred
            }

            { Start-DbaAzMigration @splatMigration } | Should -Throw "*Microsoft.SqlServer.Dac.DacExportOptions*"
        }

        It "Rejects an invalid import option before connecting" {
            $splatMigration = @{
                Source          = $script:testInstance
                Destination     = $script:testInstance
                ImportDacOption = [pscustomobject]@{ Name = "invalid" }
                EnableException = $true
            }
            if ($TestConfig.SqlCred) {
                $splatMigration.SourceSqlCredential = $TestConfig.SqlCred
                $splatMigration.DestinationSqlCredential = $TestConfig.SqlCred
            }

            { Start-DbaAzMigration @splatMigration } | Should -Throw "*Microsoft.SqlServer.Dac.DacImportOptions*"
        }

        It "Rejects a destination that is not Azure SQL Database" {
            $splatMigration = @{
                Source          = $script:testInstance
                Destination     = $script:testInstance
                Database        = "dbatoolsci_azmigration_validation"
                EnableException = $true
            }
            if ($TestConfig.SqlCred) {
                $splatMigration.SourceSqlCredential = $TestConfig.SqlCred
                $splatMigration.DestinationSqlCredential = $TestConfig.SqlCred
            }

            { Start-DbaAzMigration @splatMigration } | Should -Throw "*Azure SQL Database*Copy-DbaDatabase*"
        }
    }
}