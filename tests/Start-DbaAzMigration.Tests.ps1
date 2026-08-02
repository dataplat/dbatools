#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
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

        It "Rejects a falsey invalid export option before connecting" {
            $splatInvalidExportOption = @{
                Source          = "not-used"
                Destination     = "not-used"
                ExportDacOption = 0
                EnableException = $true
            }
            {
                Start-DbaAzMigration @splatInvalidExportOption
            } | Should -Throw "*Microsoft.SqlServer.Dac.DacExportOptions*"
        }

        It "Rejects a falsey invalid import option before connecting" {
            $splatInvalidImportOption = @{
                Source          = "not-used"
                Destination     = "not-used"
                ImportDacOption = ""
                EnableException = $true
            }
            {
                Start-DbaAzMigration @splatInvalidImportOption
            } | Should -Throw "*Microsoft.SqlServer.Dac.DacImportOptions*"
        }

        It "Rejects an explicitly bound blank string database selection before connecting" {
            $splatBlankDatabase = @{
                Source          = "not-used"
                Destination     = "not-used"
                Database        = ""
                EnableException = $true
            }

            { Start-DbaAzMigration @splatBlankDatabase } | Should -Throw "*at least one non-blank database name*"
        }

        It "Rejects an explicitly bound null database selection before connecting" {
            $splatNullDatabase = @{
                Source          = "not-used"
                Destination     = "not-used"
                Database        = $null
                EnableException = $true
            }

            { Start-DbaAzMigration @splatNullDatabase } | Should -Throw "*at least one non-blank database name*"
        }

        It "Rejects an explicitly bound empty array database selection before connecting" {
            $splatEmptyDatabaseArray = @{
                Source          = "not-used"
                Destination     = "not-used"
                Database        = @()
                EnableException = $true
            }

            { Start-DbaAzMigration @splatEmptyDatabaseArray } | Should -Throw "*at least one non-blank database name*"
        }

        It "Rejects a file path in friendly mode before connecting" {
            $filePath = Join-Path $TestDrive "not-a-directory.txt"
            Set-Content -LiteralPath $filePath -Value "not a directory"
            $warnings = @()
            $splatInvalidPath = @{
                Source          = "not-used"
                Destination     = "not-used"
                Path            = $filePath
                WarningVariable = "warnings"
            }

            $result = Start-DbaAzMigration @splatInvalidPath

            $result | Should -BeNullOrEmpty
            @($warnings | Where-Object Message -Like "*must be a directory*").Count | Should -BeGreaterOrEqual 1
            @($warnings | Where-Object Message -Like "*Failure connecting*") | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $script:testInstance = if ($TestConfig.InstanceSingle) { $TestConfig.InstanceSingle } else { "localhost" }
    }

    Context "Boundary validation" {
        It "Rejects an invalid export option before connecting" {
            $splatInvalidExportMigration = @{
                Source          = $script:testInstance
                Destination     = $script:testInstance
                ExportDacOption = [pscustomobject]@{ Name = "invalid" }
                EnableException = $true
            }
            if ($TestConfig.SqlCred) {
                $splatInvalidExportMigration.SourceSqlCredential = $TestConfig.SqlCred
                $splatInvalidExportMigration.DestinationSqlCredential = $TestConfig.SqlCred
            }

            { Start-DbaAzMigration @splatInvalidExportMigration } | Should -Throw "*Microsoft.SqlServer.Dac.DacExportOptions*"
        }

        It "Rejects an invalid import option before connecting" {
            $splatInvalidImportMigration = @{
                Source          = $script:testInstance
                Destination     = $script:testInstance
                ImportDacOption = [pscustomobject]@{ Name = "invalid" }
                EnableException = $true
            }
            if ($TestConfig.SqlCred) {
                $splatInvalidImportMigration.SourceSqlCredential = $TestConfig.SqlCred
                $splatInvalidImportMigration.DestinationSqlCredential = $TestConfig.SqlCred
            }

            { Start-DbaAzMigration @splatInvalidImportMigration } | Should -Throw "*Microsoft.SqlServer.Dac.DacImportOptions*"
        }

        It "Rejects a destination that is not Azure SQL Database" {
            $splatNonAzureDestinationMigration = @{
                Source          = $script:testInstance
                Destination     = $script:testInstance
                Database        = "dbatoolsci_azmigration_validation"
                EnableException = $true
            }
            if ($TestConfig.SqlCred) {
                $splatNonAzureDestinationMigration.SourceSqlCredential = $TestConfig.SqlCred
                $splatNonAzureDestinationMigration.DestinationSqlCredential = $TestConfig.SqlCred
            }

            { Start-DbaAzMigration @splatNonAzureDestinationMigration } | Should -Throw "*Azure SQL Database*Copy-DbaDatabase*"
        }
    }
}
