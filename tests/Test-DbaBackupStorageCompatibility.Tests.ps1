#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaBackupStorageCompatibility",
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
                "Type",
                "MaxTransferSize",
                "Threshold",
                "Monitor",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        It "calculates multipart risk and recommends more files" {
            $result = Get-DbaS3BackupStorageEstimate -EffectiveBackupSizeBytes 200GB -BackupFileCount 2 -MaxTransferSize 10MB -Threshold 90

            $result.EstimatedPartsPerFile | Should -Be 10240
            $result.PercentOfLimit | Should -Be 102.4
            $result.IsCompatible | Should -BeFalse
            $result.Status | Should -Be "ExceedsPartLimit"
            $result.RecommendedFileCount | Should -Be 3
        }

        It "treats exactly ten thousand parts as compatible" {
            $result = Get-DbaS3BackupStorageEstimate -EffectiveBackupSizeBytes 104857600000 -BackupFileCount 1 -MaxTransferSize 10MB -Threshold 90

            $result.EstimatedPartsPerFile | Should -Be 10000
            $result.IsCompatible | Should -BeTrue
            $result.Status | Should -Be "Warning"
        }
    }
}
