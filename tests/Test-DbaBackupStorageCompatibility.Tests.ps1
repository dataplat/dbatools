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
        BeforeEach {
            $script:mockStorageServer = [PSCustomObject]@{
                ComputerName       = "sql1"
                ServiceName        = "MSSQLSERVER"
                DomainInstanceName = "sql1"
                Databases          = @(
                    [PSCustomObject]@{
                        Name         = "TestDb"
                        IsAccessible = $true
                    }
                )
            }

            Mock Connect-DbaInstance {
                $script:mockStorageServer
            }
            Mock Stop-Function
        }

        It "calculates S3 parts from compressed backup size and recommends more files" {
            Mock Get-DbaDbBackupHistory -RemoveParameterType "SqlInstance" {
                [PSCustomObject]@{
                    Start                = Get-Date "2026-01-01"
                    TotalSize            = 220GB
                    CompressedBackupSize = 200GB
                    Path                 = @("s3://bucket/a.bak", "s3://bucket/b.bak")
                }
            }

            $result = Test-DbaBackupStorageCompatibility -SqlInstance "sql1" -Database "TestDb"

            $result.Type | Should -Be "S3"
            $result.EffectiveBackupSizeBytes | Should -Be 214748364800
            $result.BackupFileCount | Should -Be 2
            $result.EstimatedPartsPerFile | Should -Be 10240
            $result.PercentOfLimit | Should -Be 102.4
            $result.IsCompatible | Should -BeFalse
            $result.Status | Should -Be "ExceedsPartLimit"
            $result.RecommendedFileCount | Should -Be 3
            Should -Invoke Connect-DbaInstance -Times 1 -Exactly -ParameterFilter { $MinimumVersion -eq 16 }
        }

        It "treats exactly ten thousand parts as compatible" {
            Mock Get-DbaDbBackupHistory -RemoveParameterType "SqlInstance" {
                [PSCustomObject]@{
                    Start                = Get-Date "2026-01-01"
                    TotalSize            = 104857600000
                    CompressedBackupSize = 0
                    Path                 = @("s3://bucket/a.bak")
                }
            }

            $result = Test-DbaBackupStorageCompatibility -SqlInstance "sql1"

            $result.EstimatedPartsPerFile | Should -Be 10000
            $result.IsCompatible | Should -BeTrue
            $result.Status | Should -Be "Warning"
        }

        It "returns only risks and signals once in monitor mode" {
            Mock Get-DbaDbBackupHistory -RemoveParameterType "SqlInstance" {
                [PSCustomObject]@{
                    Start                = Get-Date "2026-01-01"
                    TotalSize            = 220GB
                    CompressedBackupSize = 200GB
                    Path                 = @("s3://bucket/a.bak", "s3://bucket/b.bak")
                }
            }

            $result = Test-DbaBackupStorageCompatibility -SqlInstance "sql1" -Monitor

            $result.Status | Should -Be "ExceedsPartLimit"
            Should -Invoke Stop-Function -Times 1 -Exactly -ParameterFilter {
                $Message -match "1 database" -and $Category -eq "InvalidResult"
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $databaseName = "dbatoolsci_backupstorage_$(Get-Random)"
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $null = New-DbaDatabase -SqlInstance $server -Name $databaseName
        $null = Backup-DbaDatabase -SqlInstance $server -Database $databaseName
        $result = Test-DbaBackupStorageCompatibility -SqlInstance $server -Database $databaseName

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $server -Database $databaseName

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "returns a compatible S3 estimate for a small full backup" {
        $result.Database | Should -Be $databaseName
        $result.Type | Should -Be "S3"
        $result.BackupFileCount | Should -BeGreaterThan 0
        $result.EstimatedPartsPerFile | Should -BeGreaterThan 0
        $result.IsCompatible | Should -BeTrue
    }

    It "returns the documented output properties" {
        $expectedProperties = @(
            "ComputerName",
            "InstanceName",
            "SqlInstance",
            "Database",
            "Type",
            "LastFullBackup",
            "BackupSizeBytes",
            "CompressedBackupSizeBytes",
            "EffectiveBackupSizeBytes",
            "BackupFileCount",
            "MaxTransferSize",
            "EstimatedPartsPerFile",
            "PercentOfLimit",
            "IsCompatible",
            "Status",
            "RecommendedFileCount",
            "RecommendedMaxTransferSizeBytes",
            "Recommendation"
        )

        $result.PSObject.Properties.Name | Should -Be $expectedProperties
    }
}
