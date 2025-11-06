#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Install-DbaMaintenanceSolution",
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
                "BackupLocation",
                "CleanupTime",
                "OutputFileDirectory",
                "ReplaceExisting",
                "LogToTable",
                "Solution",
                "InstallJobs",
                "LocalFile",
                "InstallParallel",
                "AutoScheduleJobs",
                "StartTime",
                "Force",
                "ChangeBackupType",
                "Compress",
                "CopyOnly",
                "Verify",
                "CheckSum",
                "ModificationLevel",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Limited testing of Maintenance Solution installer" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Clean up any existing maintenance solution objects in tempdb from previous runs on BOTH instances
            $cleanupQuery = "
                IF OBJECT_ID('dbo.CommandExecute', 'P') IS NOT NULL DROP PROCEDURE dbo.CommandExecute;
                IF OBJECT_ID('dbo.DatabaseBackup', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseBackup;
                IF OBJECT_ID('dbo.DatabaseIntegrityCheck', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseIntegrityCheck;
                IF OBJECT_ID('dbo.IndexOptimize', 'P') IS NOT NULL DROP PROCEDURE dbo.IndexOptimize;
                IF OBJECT_ID('dbo.CommandLog', 'U') IS NOT NULL DROP TABLE dbo.CommandLog;
                IF OBJECT_ID('dbo.Queue', 'U') IS NOT NULL DROP TABLE dbo.Queue;
                IF OBJECT_ID('dbo.QueueDatabase', 'U') IS NOT NULL DROP TABLE dbo.QueueDatabase;
            "
            # Clean both instance2 and instance3 to handle leftovers from failed test runs
            $splatCleanup = @{
                SqlInstance = $TestConfig.instance2, $TestConfig.instance3
                Database    = "tempdb"
                Query       = $cleanupQuery
            }
            Invoke-DbaQuery @splatCleanup

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Clean up maintenance solution procedures and tables on BOTH instances
            $cleanupQuery = "
                IF OBJECT_ID('dbo.CommandExecute', 'P') IS NOT NULL DROP PROCEDURE dbo.CommandExecute;
                IF OBJECT_ID('dbo.DatabaseBackup', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseBackup;
                IF OBJECT_ID('dbo.DatabaseIntegrityCheck', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseIntegrityCheck;
                IF OBJECT_ID('dbo.IndexOptimize', 'P') IS NOT NULL DROP PROCEDURE dbo.IndexOptimize;
                IF OBJECT_ID('dbo.CommandLog', 'U') IS NOT NULL DROP TABLE dbo.CommandLog;
                IF OBJECT_ID('dbo.Queue', 'U') IS NOT NULL DROP TABLE dbo.Queue;
                IF OBJECT_ID('dbo.QueueDatabase', 'U') IS NOT NULL DROP TABLE dbo.QueueDatabase;
            "
            # Clean both instance2 and instance3
            $splatCleanup = @{
                SqlInstance = $TestConfig.instance2, $TestConfig.instance3
                Database    = "tempdb"
                Query       = $cleanupQuery
            }
            Invoke-DbaQuery @splatCleanup

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "does not overwrite existing" {
            # First installation should succeed
            $results = Install-DbaMaintenanceSolution -SqlInstance $TestConfig.instance2 -Database tempdb
            $results | Should -Not -BeNullOrEmpty

            # Second installation should warn about already existing
            $results = Install-DbaMaintenanceSolution -SqlInstance $TestConfig.instance2 -Database tempdb -WarningVariable warnVar -WarningAction SilentlyContinue
            $warnVar | Should -Match "already exists"
        }

        It "Continues the installation on other servers" {
            $results = Install-DbaMaintenanceSolution -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database tempdb -WarningAction SilentlyContinue
            $sproc = Get-DbaModule -SqlInstance $TestConfig.instance3 -Database tempdb | Where-Object { $_.Name -eq "CommandExecute" }
            $sproc | Should -Not -BeNullOrEmpty
        }
    }

    Context "Additional backup parameters" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Clean up any leftover test databases from previous runs
            $oldTestDbs = Get-DbaDatabase -SqlInstance $TestConfig.instance3 | Where-Object Name -like "dbatoolsci_maintenancesolution_*"
            if ($oldTestDbs) {
                $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $oldTestDbs.Name -Confirm:$false
            }

            # Clean up any leftover Hallengren jobs
            $oldJobs = Get-DbaAgentJob -SqlInstance $TestConfig.instance3 | Where-Object Description -match "hallengren"
            if ($oldJobs) {
                $null = Remove-DbaAgentJob -SqlInstance $TestConfig.instance3 -Job $oldJobs.Name -Confirm:$false
            }

            # Clean up any leftover Hallengren procedures in tempdb from the first Context
            $cleanupTempdb = "
                IF OBJECT_ID('tempdb.dbo.CommandExecute', 'P') IS NOT NULL DROP PROCEDURE tempdb.dbo.CommandExecute;
                IF OBJECT_ID('tempdb.dbo.DatabaseBackup', 'P') IS NOT NULL DROP PROCEDURE tempdb.dbo.DatabaseBackup;
                IF OBJECT_ID('tempdb.dbo.DatabaseIntegrityCheck', 'P') IS NOT NULL DROP PROCEDURE tempdb.dbo.DatabaseIntegrityCheck;
                IF OBJECT_ID('tempdb.dbo.IndexOptimize', 'P') IS NOT NULL DROP PROCEDURE tempdb.dbo.IndexOptimize;
                IF OBJECT_ID('tempdb.dbo.CommandLog', 'U') IS NOT NULL DROP TABLE tempdb.dbo.CommandLog;
                IF OBJECT_ID('tempdb.dbo.Queue', 'U') IS NOT NULL DROP TABLE tempdb.dbo.Queue;
                IF OBJECT_ID('tempdb.dbo.QueueDatabase', 'U') IS NOT NULL DROP TABLE tempdb.dbo.QueueDatabase;
            "
            $splatCleanupTempdb = @{
                SqlInstance = $TestConfig.instance3
                Query       = $cleanupTempdb
            }
            Invoke-DbaQuery @splatCleanupTempdb

            $testDbName = "dbatoolsci_maintenancesolution_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.instance3 -Name $testDbName

            $splatInstall = @{
                SqlInstance      = $TestConfig.instance3
                Database         = $testDbName
                InstallJobs      = $true
                ReplaceExisting  = $true
                CleanupTime      = 168
                ChangeBackupType = $true
                Compress         = $true
                Verify           = $true
                CheckSum         = $true
            }
            $installResult = Install-DbaMaintenanceSolution @splatInstall

            # Verify installation succeeded before running tests
            # Skip tests if installation failed (eg. due to event log limitations on AppVeyor or SQL Agent not running)
            $script:installationSucceeded = $false
            if ($installResult) {
                $splatJobCheck = @{
                    SqlInstance = $TestConfig.instance3
                }
                $fullBackupJob = Get-DbaAgentJob @splatJobCheck | Where-Object Name -eq "DatabaseBackup - USER_DATABASES - FULL"
                if ($fullBackupJob) {
                    $script:installationSucceeded = $true
                }
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $testDbName -Confirm:$false
            $jobs = Get-DbaAgentJob -SqlInstance $TestConfig.instance3 | Where-Object Description -match "hallengren"
            if ($jobs) {
                $null = Remove-DbaAgentJob -SqlInstance $TestConfig.instance3 -Job $jobs.Name -Confirm:$false
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should add ChangeBackupType parameter to DIFF backup job" -Skip:(-not $script:installationSucceeded) {
            $splatJobStep = @{
                SqlInstance = $TestConfig.instance3
                Job         = "DatabaseBackup - USER_DATABASES - DIFF"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@ChangeBackupType = 'Y'"
        }

        It "Should add ChangeBackupType parameter to LOG backup job" -Skip:(-not $script:installationSucceeded) {
            $splatJobStep = @{
                SqlInstance = $TestConfig.instance3
                Job         = "DatabaseBackup - USER_DATABASES - LOG"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@ChangeBackupType = 'Y'"
        }

        It "Should NOT add ChangeBackupType parameter to FULL backup job" -Skip:(-not $script:installationSucceeded) {
            $splatJobStep = @{
                SqlInstance = $TestConfig.instance3
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Not -Match "@ChangeBackupType = 'Y'"
        }

        It "Should add Compress parameter to all backup jobs" -Skip:(-not $script:installationSucceeded) {
            $splatJobStep = @{
                SqlInstance = $TestConfig.instance3
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@Compress = 'Y'"
        }

        It "Should have Verify parameter set to Y in backup jobs" -Skip:(-not $script:installationSucceeded) {
            $splatJobStep = @{
                SqlInstance = $TestConfig.instance3
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@Verify = 'Y'"
        }

        It "Should have CheckSum parameter set to Y in backup jobs" -Skip:(-not $script:installationSucceeded) {
            $splatJobStep = @{
                SqlInstance = $TestConfig.instance3
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@CheckSum = 'Y'"
        }
    }
}