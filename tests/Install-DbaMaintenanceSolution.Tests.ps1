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
            # Clean both InstanceSingle and instance3 to handle leftovers from failed test runs
            $splatCleanup = @{
                SqlInstance = $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2
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
            # Clean both InstanceSingle and instance3
            $splatCleanup = @{
                SqlInstance = $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2
                Database    = "tempdb"
                Query       = $cleanupQuery
            }
            Invoke-DbaQuery @splatCleanup

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "does not overwrite existing" {
            # First installation should succeed
            $results = Install-DbaMaintenanceSolution -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb
            $results | Should -Not -BeNullOrEmpty

            # Second installation should warn about already existing
            $results = Install-DbaMaintenanceSolution -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -WarningVariable warnVar -WarningAction SilentlyContinue
            $warnVar | Should -Match "already exists"
        }

        It "Continues the installation on other servers" {
            $results = Install-DbaMaintenanceSolution -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Database tempdb -WarningAction SilentlyContinue
            $sproc = Get-DbaModule -SqlInstance $TestConfig.InstanceMulti2 -Database tempdb | Where-Object { $_.Name -eq "CommandExecute" }
            $sproc | Should -Not -BeNullOrEmpty
        }
    }

    Context "Additional backup parameters all enabled" {
        AfterEach {
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti2 -Query $jobStep.Command -NoExec -EnableException
        }

        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Clean up any leftover test databases from previous runs
            $oldTestDbs = Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Name -like "dbatoolsci_maintenancesolution_*"
            if ($oldTestDbs) {
                $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $oldTestDbs.Name -Confirm:$false
            }

            # Clean up any leftover Hallengren jobs
            $oldJobs = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Description -match "hallengren"
            if ($oldJobs) {
                $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 -Job $oldJobs.Name -Confirm:$false
            }

            # Clean up any leftover Hallengren procedures in tempdb from the first Context
            $cleanupTempdb = "
                IF OBJECT_ID('dbo.CommandExecute', 'P') IS NOT NULL DROP PROCEDURE dbo.CommandExecute;
                IF OBJECT_ID('dbo.DatabaseBackup', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseBackup;
                IF OBJECT_ID('dbo.DatabaseIntegrityCheck', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseIntegrityCheck;
                IF OBJECT_ID('dbo.IndexOptimize', 'P') IS NOT NULL DROP PROCEDURE dbo.IndexOptimize;
                IF OBJECT_ID('dbo.CommandLog', 'U') IS NOT NULL DROP TABLE dbo.CommandLog;
                IF OBJECT_ID('dbo.Queue', 'U') IS NOT NULL DROP TABLE dbo.Queue;
                IF OBJECT_ID('dbo.QueueDatabase', 'U') IS NOT NULL DROP TABLE dbo.QueueDatabase;
            "
            $splatCleanupTempdb = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Database    = "tempdb"
                Query       = $cleanupTempdb
            }
            Invoke-DbaQuery @splatCleanupTempdb

            $testDbName = "dbatoolsci_maintenancesolution_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Name $testDbName

            $splatInstall = @{
                SqlInstance       = $TestConfig.InstanceMulti2
                Database          = $testDbName
                InstallJobs       = $true
                ReplaceExisting   = $true
                CleanupTime       = 168
                ChangeBackupType  = $true
                Compress          = $true
                CopyOnly          = $true
                Verify            = $true
                CheckSum          = $true
                ModificationLevel = 12
            }
            $installResult = Install-DbaMaintenanceSolution @splatInstall

            # Verify installation succeeded before running tests
            # Skip tests if installation failed (eg. due to event log limitations on AppVeyor or SQL Agent not running)
            $script:installationSucceeded = $false
            if ($installResult) {
                $splatJobCheck = @{
                    SqlInstance = $TestConfig.InstanceMulti2
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

            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $testDbName -Confirm:$false
            $jobs = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Description -match "hallengren"
            if ($jobs) {
                $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 -Job $jobs.Name -Confirm:$false
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should add ChangeBackupType parameter to DIFF backup job" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - DIFF"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@ChangeBackupType = 'Y'"
        }

        It "Should add ChangeBackupType parameter to LOG backup job" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - LOG"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@ChangeBackupType = 'Y'"
        }

        It "Should NOT add ChangeBackupType parameter to FULL backup job" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Not -Match "@ChangeBackupType = 'Y'"
        }

        It "Should add ModificationLevel parameter to DIFF backup job" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - DIFF"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@ModificationLevel = 12"
        }

        It "Should NOT add ModificationLevel parameter to LOG backup job" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - LOG"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Not -Match "@ModificationLevel"
        }

        It "Should NOT add ModificationLevel parameter to FULL backup job" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Not -Match "@ModificationLevel"
        }

        It "Should have Compress parameter set to Y in backup jobs" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@Compress = 'Y'"
        }

        It "Should have CopyOnly parameter set to Y in backup jobs" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@CopyOnly = 'Y'"
        }

        # Not a bug!
        # We probably should defend against this, but it is harmless.
        # From the docs: "If DIFFERENTIAL and COPY_ONLY are used together,
        # COPY_ONLY is ignored, and a differential backup is created."
        It "Should have CopyOnly parameter set to Y in DIFF backup jobs" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - DIFF"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@CopyOnly = 'Y'"
        }

        It "Should have Verify parameter set to Y in backup jobs" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@Verify = 'Y'"
        }

        It "Should have CheckSum parameter set to Y in backup jobs" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@CheckSum = 'Y'"
        }
    }

    Context "Additional backup parameters all disabled" {
        AfterEach {
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti2 -Query $jobStep.Command -NoExec -EnableException
        }

        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Clean up any leftover test databases from previous runs
            $oldTestDbs = Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Name -like "dbatoolsci_maintenancesolution_*"
            if ($oldTestDbs) {
                $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $oldTestDbs.Name -Confirm:$false
            }

            # Clean up any leftover Hallengren jobs
            $oldJobs = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Description -match "hallengren"
            if ($oldJobs) {
                $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 -Job $oldJobs.Name -Confirm:$false
            }

            # Clean up any leftover Hallengren procedures in tempdb from the first Context
            $cleanupTempdb = "
                IF OBJECT_ID('dbo.CommandExecute', 'P') IS NOT NULL DROP PROCEDURE dbo.CommandExecute;
                IF OBJECT_ID('dbo.DatabaseBackup', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseBackup;
                IF OBJECT_ID('dbo.DatabaseIntegrityCheck', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseIntegrityCheck;
                IF OBJECT_ID('dbo.IndexOptimize', 'P') IS NOT NULL DROP PROCEDURE dbo.IndexOptimize;
                IF OBJECT_ID('dbo.CommandLog', 'U') IS NOT NULL DROP TABLE dbo.CommandLog;
                IF OBJECT_ID('dbo.Queue', 'U') IS NOT NULL DROP TABLE dbo.Queue;
                IF OBJECT_ID('dbo.QueueDatabase', 'U') IS NOT NULL DROP TABLE dbo.QueueDatabase;
            "
            $splatCleanupTempdb = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Database    = "tempdb"
                Query       = $cleanupTempdb
            }
            Invoke-DbaQuery @splatCleanupTempdb

            $testDbName = "dbatoolsci_maintenancesolution_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Name $testDbName

            $splatInstall = @{
                SqlInstance      = $TestConfig.InstanceMulti2
                Database         = $testDbName
                InstallJobs      = $true
                ReplaceExisting  = $true
                CleanupTime      = 168
                ChangeBackupType = $false
                Compress         = $false
                CopyOnly         = $false
                Verify           = $false
                CheckSum         = $false
            }
            $installResult = Install-DbaMaintenanceSolution @splatInstall

            # Verify installation succeeded before running tests
            # Skip tests if installation failed (eg. due to event log limitations on AppVeyor or SQL Agent not running)
            $script:installationSucceeded = $false
            if ($installResult) {
                $splatJobCheck = @{
                    SqlInstance = $TestConfig.InstanceMulti2
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

            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $testDbName -Confirm:$false
            $jobs = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Description -match "hallengren"
            if ($jobs) {
                $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 -Job $jobs.Name -Confirm:$false
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should NOT add ChangeBackupType parameter to DIFF backup job" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - DIFF"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Not -Match "@ChangeBackupType = 'Y'"
        }

        It "Should NOT add ChangeBackupType parameter to LOG backup job" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - LOG"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Not -Match "@ChangeBackupType = 'Y'"
        }

        It "Should NOT add ChangeBackupType parameter to FULL backup job" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Not -Match "@ChangeBackupType = 'Y'"
        }

        It "Should NOT add ModificationLevel parameter to DIFF backup job" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - DIFF"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Not -Match "ModificationLevel"
        }

        It "Should NOT add ModificationLevel parameter to LOG backup job" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - LOG"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Not -Match "@ModificationLevel"
        }

        It "Should NOT add ModificationLevel parameter to FULL backup job" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Not -Match "@ModificationLevel"
        }

        It "Should NOT add CopyOnly parameter to backup jobs" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Not -Match "@CopyOnly"
        }

        It "Should NOT add CopyOnly parameter to DIFF backup jobs" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - DIFF"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Not -Match "@CopyOnly"
        }

        It "Should have Compress parameter set to N in backup jobs" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@Compress = 'N'"
        }

        It "Should have Verify parameter set to N in backup jobs" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@Verify = 'N'"
        }

        It "Should have CheckSum parameter set to N in backup jobs" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@CheckSum = 'N'"
        }
    }

    Context "Additional backup parameters all but Verify disabled" {
        AfterEach {
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti2 -Query $jobStep.Command -NoExec -EnableException
        }

        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Clean up any leftover test databases from previous runs
            $oldTestDbs = Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Name -like "dbatoolsci_maintenancesolution_*"
            if ($oldTestDbs) {
                $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $oldTestDbs.Name -Confirm:$false
            }

            # Clean up any leftover Hallengren jobs
            $oldJobs = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Description -match "hallengren"
            if ($oldJobs) {
                $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 -Job $oldJobs.Name -Confirm:$false
            }

            # Clean up any leftover Hallengren procedures in tempdb from the first Context
            $cleanupTempdb = "
                IF OBJECT_ID('dbo.CommandExecute', 'P') IS NOT NULL DROP PROCEDURE dbo.CommandExecute;
                IF OBJECT_ID('dbo.DatabaseBackup', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseBackup;
                IF OBJECT_ID('dbo.DatabaseIntegrityCheck', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseIntegrityCheck;
                IF OBJECT_ID('dbo.IndexOptimize', 'P') IS NOT NULL DROP PROCEDURE dbo.IndexOptimize;
                IF OBJECT_ID('dbo.CommandLog', 'U') IS NOT NULL DROP TABLE dbo.CommandLog;
                IF OBJECT_ID('dbo.Queue', 'U') IS NOT NULL DROP TABLE dbo.Queue;
                IF OBJECT_ID('dbo.QueueDatabase', 'U') IS NOT NULL DROP TABLE dbo.QueueDatabase;
            "
            $splatCleanupTempdb = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Database    = "tempdb"
                Query       = $cleanupTempdb
            }
            Invoke-DbaQuery @splatCleanupTempdb

            $testDbName = "dbatoolsci_maintenancesolution_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Name $testDbName

            $splatInstall = @{
                SqlInstance      = $TestConfig.InstanceMulti2
                Database         = $testDbName
                InstallJobs      = $true
                ReplaceExisting  = $true
                CleanupTime      = 168
                ChangeBackupType = $false
                Compress         = $false
                CopyOnly         = $false
                Verify           = $true
                CheckSum         = $false
            }
            $installResult = Install-DbaMaintenanceSolution @splatInstall

            # Verify installation succeeded before running tests
            # Skip tests if installation failed (eg. due to event log limitations on AppVeyor or SQL Agent not running)
            $script:installationSucceeded = $false
            if ($installResult) {
                $splatJobCheck = @{
                    SqlInstance = $TestConfig.InstanceMulti2
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

            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $testDbName -Confirm:$false
            $jobs = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Description -match "hallengren"
            if ($jobs) {
                $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 -Job $jobs.Name -Confirm:$false
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should NOT add ChangeBackupType parameter to DIFF backup job" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - DIFF"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Not -Match "@ChangeBackupType = 'Y'"
        }

        It "Should NOT add ChangeBackupType parameter to LOG backup job" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - LOG"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Not -Match "@ChangeBackupType = 'Y'"
        }

        It "Should NOT add ChangeBackupType parameter to FULL backup job" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Not -Match "@ChangeBackupType = 'Y'"
        }

        It "Should have Compress parameter set to N in backup jobs" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@Compress = 'N'"
        }

        It "Should have Verify parameter set to Y in backup jobs" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@Verify = 'Y'"
        }

        It "Should have CheckSum parameter set to N in backup jobs" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@CheckSum = 'N'"
        }
    }

    # Both CheckSum and Compress are special, so not in this context.
    # Aside from those, the documentation claims we have defaults for
    # Verify, BackupLocation, and StartTime.
    Context "Defaults for unspecified parameters are as documentation says" {
        # Note the lack of the usual AfterEach block.
        # We test schedules in one place here, so our usual trick is not applicable.

        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Clean up any leftover test databases from previous runs
            $oldTestDbs = Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Name -like "dbatoolsci_maintenancesolution_*"
            if ($oldTestDbs) {
                $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $oldTestDbs.Name -Confirm:$false
            }

            # Clean up any leftover Hallengren jobs
            $oldJobs = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Description -match "hallengren"
            if ($oldJobs) {
                $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 -Job $oldJobs.Name -Confirm:$false
            }

            # Clean up any leftover Hallengren procedures in tempdb from the first Context
            $cleanupTempdb = "
                IF OBJECT_ID('dbo.CommandExecute', 'P') IS NOT NULL DROP PROCEDURE dbo.CommandExecute;
                IF OBJECT_ID('dbo.DatabaseBackup', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseBackup;
                IF OBJECT_ID('dbo.DatabaseIntegrityCheck', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseIntegrityCheck;
                IF OBJECT_ID('dbo.IndexOptimize', 'P') IS NOT NULL DROP PROCEDURE dbo.IndexOptimize;
                IF OBJECT_ID('dbo.CommandLog', 'U') IS NOT NULL DROP TABLE dbo.CommandLog;
                IF OBJECT_ID('dbo.Queue', 'U') IS NOT NULL DROP TABLE dbo.Queue;
                IF OBJECT_ID('dbo.QueueDatabase', 'U') IS NOT NULL DROP TABLE dbo.QueueDatabase;
            "
            $splatCleanupTempdb = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Database    = "tempdb"
                Query       = $cleanupTempdb
            }
            Invoke-DbaQuery @splatCleanupTempdb

            $testDbName = "dbatoolsci_maintenancesolution_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Name $testDbName

            $splatInstall = @{
                SqlInstance      = $TestConfig.InstanceMulti2
                # We could test that the default database is master,
                # but that is currently enforced at the PowerShell level
                # so it could just be a unit test.
                Database         = $testDbName
                InstallJobs      = $true
                ReplaceExisting  = $true
                AutoScheduleJobs = "WeeklyFull"
            }
            $installResult = Install-DbaMaintenanceSolution @splatInstall

            # Verify installation succeeded before running tests
            # Skip tests if installation failed (eg. due to event log limitations on AppVeyor or SQL Agent not running)
            $script:installationSucceeded = $false
            if ($installResult) {
                $splatJobCheck = @{
                    SqlInstance = $TestConfig.InstanceMulti2
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

            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $testDbName -Confirm:$false
            $jobs = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Description -match "hallengren"
            if ($jobs) {
                $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 -Job $jobs.Name -Confirm:$false
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should have Verify parameter set to Y in backup jobs" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@Verify = 'Y'"
        }

        It "Should have StartTime set to 011500 in backup schedule" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $schedule = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceMulti2
            # We do not make any promises about job names,
            # so checking for times is all we can do.
            $schedule.ActiveStartTimeOfDay |
                Where-Object { $_.Hours -eq 1 -and $_.Minutes -eq 15 } |
                Should -Not -BeNullOrEmpty
        }

        It "Should have BackupLocation parameter set to instance default in backup jobs" {
            if (-not $script:installationSucceeded) {
                Set-ItResult -Skipped -Because "Installation failed"
                return
            }
            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $backupLocationSetting = (Get-DbaDefaultPath -SqlInstance $TestConfig.InstanceMulti2).Backup
            $jobStep.Command | Should -BeLike "*@Directory = *$backupLocationSetting*"
        }
    }

    # This case is special. We try to make the install fail.
    Context "Backup to Nul with Verify on" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Clean up any leftover test databases from previous runs
            $oldTestDbs = Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Name -like "dbatoolsci_maintenancesolution_*"
            if ($oldTestDbs) {
                $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $oldTestDbs.Name -Confirm:$false
            }

            # Clean up any leftover Hallengren jobs
            $oldJobs = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Description -match "hallengren"
            if ($oldJobs) {
                $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 -Job $oldJobs.Name -Confirm:$false
            }

            # Clean up any leftover Hallengren procedures in tempdb from the first Context
            $cleanupTempdb = "
                IF OBJECT_ID('dbo.CommandExecute', 'P') IS NOT NULL DROP PROCEDURE dbo.CommandExecute;
                IF OBJECT_ID('dbo.DatabaseBackup', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseBackup;
                IF OBJECT_ID('dbo.DatabaseIntegrityCheck', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseIntegrityCheck;
                IF OBJECT_ID('dbo.IndexOptimize', 'P') IS NOT NULL DROP PROCEDURE dbo.IndexOptimize;
                IF OBJECT_ID('dbo.CommandLog', 'U') IS NOT NULL DROP TABLE dbo.CommandLog;
                IF OBJECT_ID('dbo.Queue', 'U') IS NOT NULL DROP TABLE dbo.Queue;
                IF OBJECT_ID('dbo.QueueDatabase', 'U') IS NOT NULL DROP TABLE dbo.QueueDatabase;
            "
            $splatCleanupTempdb = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Database    = "tempdb"
                Query       = $cleanupTempdb
            }
            Invoke-DbaQuery @splatCleanupTempdb

            $testDbName = "dbatoolsci_maintenancesolution_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Name $testDbName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $testDbName -Confirm:$false
            $jobs = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Description -match "hallengren"
            if ($jobs) {
                $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 -Job $jobs.Name -Confirm:$false
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should error out and tell us our mistake" {
            $splatInstall = @{
                SqlInstance      = $TestConfig.InstanceMulti2
                Database         = $testDbName
                InstallJobs      = $true
                ReplaceExisting  = $true
                Verify           = $true
                BackupLocation   = "NUL"
                EnableException  = $true
            }
            $installResult = { Install-DbaMaintenanceSolution @splatInstall } | Should -Throw -ExpectedMessage "*NUL*"
        }
    }

    # Our documentation claims that we always turn CheckSum on unless
    # it is deliberately turned off, so we must test that.
    # However, Ola checks sys.configurations in dbo.DatabaseBackup.
    # This should not impact the Agent Jobs, but we should make sure that
    # there is no conflict.
    Context "Checksum tests when instance defaults to checksum on" {
        AfterEach {
            # Notice that we are uninstalling after each test.
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti2 -Query $jobStep.Command -NoExec -EnableException

            # Clean up any leftover Hallengren jobs
            $oldJobs = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Description -match "hallengren"
            if ($oldJobs) {
                $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 -Job $oldJobs.Name -Confirm:$false
            }

            # Clean up any leftover Hallengren procedures in tempdb from the first Context
            $cleanupTempdb = "
                IF OBJECT_ID('dbo.CommandExecute', 'P') IS NOT NULL DROP PROCEDURE dbo.CommandExecute;
                IF OBJECT_ID('dbo.DatabaseBackup', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseBackup;
                IF OBJECT_ID('dbo.DatabaseIntegrityCheck', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseIntegrityCheck;
                IF OBJECT_ID('dbo.IndexOptimize', 'P') IS NOT NULL DROP PROCEDURE dbo.IndexOptimize;
                IF OBJECT_ID('dbo.CommandLog', 'U') IS NOT NULL DROP TABLE dbo.CommandLog;
                IF OBJECT_ID('dbo.Queue', 'U') IS NOT NULL DROP TABLE dbo.Queue;
                IF OBJECT_ID('dbo.QueueDatabase', 'U') IS NOT NULL DROP TABLE dbo.QueueDatabase;
            "
            $splatCleanupTempdb = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Database    = "tempdb"
                Query       = $cleanupTempdb
            }
            Invoke-DbaQuery @splatCleanupTempdb

            $testDbName = "dbatoolsci_maintenancesolution_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Name $testDbName
        }

        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $checksumSettingInitial = (Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceMulti2 -ConfigName BackupChecksumDefault).ConfiguredValue
            # Throws if we already have the setting as we want it to be, so SilentlyContinue instead.
            $splatConfigure = @{
                SqlInstance     = $TestConfig.InstanceMulti2
                ConfigName      = "BackupChecksumDefault"
                Value           = 1
                WarningAction   = "SilentlyContinue"
                EnableException = $false
            }
            Set-DbaSpConfigure @splatConfigure

            # Clean up any leftover test databases from previous runs
            $oldTestDbs = Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Name -like "dbatoolsci_maintenancesolution_*"
            if ($oldTestDbs) {
                $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $oldTestDbs.Name -Confirm:$false
            }

            # Clean up any leftover Hallengren jobs
            $oldJobs = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Description -match "hallengren"
            if ($oldJobs) {
                $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 -Job $oldJobs.Name -Confirm:$false
            }

            # Clean up any leftover Hallengren procedures in tempdb from the first Context
            $cleanupTempdb = "
                IF OBJECT_ID('dbo.CommandExecute', 'P') IS NOT NULL DROP PROCEDURE dbo.CommandExecute;
                IF OBJECT_ID('dbo.DatabaseBackup', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseBackup;
                IF OBJECT_ID('dbo.DatabaseIntegrityCheck', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseIntegrityCheck;
                IF OBJECT_ID('dbo.IndexOptimize', 'P') IS NOT NULL DROP PROCEDURE dbo.IndexOptimize;
                IF OBJECT_ID('dbo.CommandLog', 'U') IS NOT NULL DROP TABLE dbo.CommandLog;
                IF OBJECT_ID('dbo.Queue', 'U') IS NOT NULL DROP TABLE dbo.Queue;
                IF OBJECT_ID('dbo.QueueDatabase', 'U') IS NOT NULL DROP TABLE dbo.QueueDatabase;
            "
            $splatCleanupTempdb = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Database    = "tempdb"
                Query       = $cleanupTempdb
            }
            Invoke-DbaQuery @splatCleanupTempdb

            $testDbName = "dbatoolsci_maintenancesolution_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Name $testDbName

            # We uninstall the scripts after each run,
            # so need it installed first.
            $splatInstall = @{
                SqlInstance      = $TestConfig.InstanceMulti2
                Database         = $testDbName
                InstallJobs      = $true
                ReplaceExisting  = $true
            }
            $installResult = Install-DbaMaintenanceSolution @splatInstall

            # Verify installation succeeded before running tests
            # Skip tests if installation failed (eg. due to event log limitations on AppVeyor or SQL Agent not running)
            $script:installationSucceeded = $false
            if ($installResult) {
                $splatJobCheck = @{
                    SqlInstance = $TestConfig.InstanceMulti2
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

            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $testDbName -Confirm:$false
            $jobs = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Description -match "hallengren"
            if ($jobs) {
                $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 -Job $jobs.Name -Confirm:$false
            }

            $splatConfigure = @{
                SqlInstance     = $TestConfig.InstanceMulti2
                ConfigName      = "BackupChecksumDefault"
                Value           = $checksumSettingInitial
                WarningAction   = "SilentlyContinue"
                EnableException = $false
            }
            Set-DbaSpConfigure @splatConfigure

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should have CheckSum parameter set to Y in backup jobs when we ask for it" {
            $splatInstall = @{
                SqlInstance      = $TestConfig.InstanceMulti2
                Database         = $testDbName
                InstallJobs      = $true
                ReplaceExisting  = $true
                CheckSum         = $true
            }
            Install-DbaMaintenanceSolution @splatInstall

            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@CheckSum = 'Y'"
        }

        It "Should have CheckSum parameter set to N in backup jobs when we refuse it" {
            $splatInstall = @{
                SqlInstance      = $TestConfig.InstanceMulti2
                Database         = $testDbName
                InstallJobs      = $true
                ReplaceExisting  = $true
                CheckSum         = $false
            }
            Install-DbaMaintenanceSolution @splatInstall

            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@CheckSum = 'N'"
        }

        # Our documentation says we always turn CheckSum on unless
        # we deliberately ask to not have it.
        It "Should have CheckSum parameter set to Y in backup jobs when we do not specify it" {
            $splatInstall = @{
                SqlInstance      = $TestConfig.InstanceMulti2
                Database         = $testDbName
                InstallJobs      = $true
                ReplaceExisting  = $true
            }
            Install-DbaMaintenanceSolution @splatInstall

            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@CheckSum = 'Y'"
        }
    }

    # See previous context.
    Context "Checksum tests when instance defaults to checksum off" {
        AfterEach {
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti2 -Query $jobStep.Command -NoExec -EnableException

            # Clean up any leftover Hallengren jobs
            $oldJobs = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Description -match "hallengren"
            if ($oldJobs) {
                $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 -Job $oldJobs.Name -Confirm:$false
            }

            # Clean up any leftover Hallengren procedures in tempdb from the first Context
            $cleanupTempdb = "
                IF OBJECT_ID('dbo.CommandExecute', 'P') IS NOT NULL DROP PROCEDURE dbo.CommandExecute;
                IF OBJECT_ID('dbo.DatabaseBackup', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseBackup;
                IF OBJECT_ID('dbo.DatabaseIntegrityCheck', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseIntegrityCheck;
                IF OBJECT_ID('dbo.IndexOptimize', 'P') IS NOT NULL DROP PROCEDURE dbo.IndexOptimize;
                IF OBJECT_ID('dbo.CommandLog', 'U') IS NOT NULL DROP TABLE dbo.CommandLog;
                IF OBJECT_ID('dbo.Queue', 'U') IS NOT NULL DROP TABLE dbo.Queue;
                IF OBJECT_ID('dbo.QueueDatabase', 'U') IS NOT NULL DROP TABLE dbo.QueueDatabase;
            "
            $splatCleanupTempdb = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Database    = "tempdb"
                Query       = $cleanupTempdb
            }
            Invoke-DbaQuery @splatCleanupTempdb

            $testDbName = "dbatoolsci_maintenancesolution_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Name $testDbName
        }

        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $checksumSettingInitial = (Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceMulti2 -ConfigName BackupChecksumDefault).ConfiguredValue
            # Throws if we already have the setting as we want it to be, so SilentlyContinue instead.
            $splatConfigure = @{
                SqlInstance     = $TestConfig.InstanceMulti2
                ConfigName      = "BackupChecksumDefault"
                Value           = 0
                WarningAction   = "SilentlyContinue"
                EnableException = $false
            }
            Set-DbaSpConfigure @splatConfigure

            # Clean up any leftover test databases from previous runs
            $oldTestDbs = Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Name -like "dbatoolsci_maintenancesolution_*"
            if ($oldTestDbs) {
                $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $oldTestDbs.Name -Confirm:$false
            }

            # Clean up any leftover Hallengren jobs
            $oldJobs = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Description -match "hallengren"
            if ($oldJobs) {
                $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 -Job $oldJobs.Name -Confirm:$false
            }

            # Clean up any leftover Hallengren procedures in tempdb from the first Context
            $cleanupTempdb = "
                IF OBJECT_ID('dbo.CommandExecute', 'P') IS NOT NULL DROP PROCEDURE dbo.CommandExecute;
                IF OBJECT_ID('dbo.DatabaseBackup', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseBackup;
                IF OBJECT_ID('dbo.DatabaseIntegrityCheck', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseIntegrityCheck;
                IF OBJECT_ID('dbo.IndexOptimize', 'P') IS NOT NULL DROP PROCEDURE dbo.IndexOptimize;
                IF OBJECT_ID('dbo.CommandLog', 'U') IS NOT NULL DROP TABLE dbo.CommandLog;
                IF OBJECT_ID('dbo.Queue', 'U') IS NOT NULL DROP TABLE dbo.Queue;
                IF OBJECT_ID('dbo.QueueDatabase', 'U') IS NOT NULL DROP TABLE dbo.QueueDatabase;
            "
            $splatCleanupTempdb = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Database    = "tempdb"
                Query       = $cleanupTempdb
            }
            Invoke-DbaQuery @splatCleanupTempdb

            $testDbName = "dbatoolsci_maintenancesolution_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Name $testDbName

            # We uninstall the scripts after each run,
            # so need it installed first.
            $splatInstall = @{
                SqlInstance      = $TestConfig.InstanceMulti2
                Database         = $testDbName
                InstallJobs      = $true
                ReplaceExisting  = $true
            }
            $installResult = Install-DbaMaintenanceSolution @splatInstall

            # Verify installation succeeded before running tests
            # Skip tests if installation failed (eg. due to event log limitations on AppVeyor or SQL Agent not running)
            $script:installationSucceeded = $false
            if ($installResult) {
                $splatJobCheck = @{
                    SqlInstance = $TestConfig.InstanceMulti2
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

            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $testDbName -Confirm:$false
            $jobs = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Description -match "hallengren"
            if ($jobs) {
                $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 -Job $jobs.Name -Confirm:$false
            }

            $splatConfigure = @{
                SqlInstance     = $TestConfig.InstanceMulti2
                ConfigName      = "BackupChecksumDefault"
                Value           = $checksumSettingInitial
                WarningAction   = "SilentlyContinue"
                EnableException = $false
            }
            Set-DbaSpConfigure @splatConfigure

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should have CheckSum parameter set to Y in backup jobs when we ask for it" {
            $splatInstall = @{
                SqlInstance      = $TestConfig.InstanceMulti2
                Database         = $testDbName
                InstallJobs      = $true
                ReplaceExisting  = $true
                CheckSum         = $true
            }
            Install-DbaMaintenanceSolution @splatInstall

            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@CheckSum = 'Y'"
        }

        It "Should have CheckSum parameter set to N in backup jobs when we refuse it" {
            $splatInstall = @{
                SqlInstance      = $TestConfig.InstanceMulti2
                Database         = $testDbName
                InstallJobs      = $true
                ReplaceExisting  = $true
                CheckSum         = $false
            }
            Install-DbaMaintenanceSolution @splatInstall

            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@CheckSum = 'N'"
        }

        # Our documentation says we always turn CheckSum on unless
        # we deliberately ask to not have it.
        It "Should have CheckSum parameter set to Y in backup jobs when we do not specify it" {
            $splatInstall = @{
                SqlInstance      = $TestConfig.InstanceMulti2
                Database         = $testDbName
                InstallJobs      = $true
                ReplaceExisting  = $true
            }
            Install-DbaMaintenanceSolution @splatInstall

            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@CheckSum = 'Y'"
        }
    }

    # Same idea as the previous two contexts.
    # However, this time we copy from sys.configurations.
    Context "Compression tests when instance defaults to compression on" {
        AfterEach {
            # Notice that we are uninstalling after each test.
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti2 -Query $jobStep.Command -NoExec -EnableException

            # Clean up any leftover Hallengren jobs
            $oldJobs = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Description -match "hallengren"
            if ($oldJobs) {
                $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 -Job $oldJobs.Name -Confirm:$false
            }

            # Clean up any leftover Hallengren procedures in tempdb from the first Context
            $cleanupTempdb = "
                IF OBJECT_ID('dbo.CommandExecute', 'P') IS NOT NULL DROP PROCEDURE dbo.CommandExecute;
                IF OBJECT_ID('dbo.DatabaseBackup', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseBackup;
                IF OBJECT_ID('dbo.DatabaseIntegrityCheck', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseIntegrityCheck;
                IF OBJECT_ID('dbo.IndexOptimize', 'P') IS NOT NULL DROP PROCEDURE dbo.IndexOptimize;
                IF OBJECT_ID('dbo.CommandLog', 'U') IS NOT NULL DROP TABLE dbo.CommandLog;
                IF OBJECT_ID('dbo.Queue', 'U') IS NOT NULL DROP TABLE dbo.Queue;
                IF OBJECT_ID('dbo.QueueDatabase', 'U') IS NOT NULL DROP TABLE dbo.QueueDatabase;
            "
            $splatCleanupTempdb = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Database    = "tempdb"
                Query       = $cleanupTempdb
            }
            Invoke-DbaQuery @splatCleanupTempdb

            $testDbName = "dbatoolsci_maintenancesolution_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Name $testDbName
        }

        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $compressionSettingInitial = (Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceMulti2 -ConfigName BackupChecksumDefault).ConfiguredValue
            $splatConfigure = @{
                SqlInstance     = $TestConfig.InstanceMulti2
                ConfigName      = "DefaultBackupCompression"
                Value           = 1
                WarningAction   = "SilentlyContinue"
                EnableException = $false
            }
            Set-DbaSpConfigure @splatConfigure

            # Clean up any leftover test databases from previous runs
            $oldTestDbs = Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Name -like "dbatoolsci_maintenancesolution_*"
            if ($oldTestDbs) {
                $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $oldTestDbs.Name -Confirm:$false
            }

            # Clean up any leftover Hallengren jobs
            $oldJobs = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Description -match "hallengren"
            if ($oldJobs) {
                $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 -Job $oldJobs.Name -Confirm:$false
            }

            # Clean up any leftover Hallengren procedures in tempdb from the first Context
            $cleanupTempdb = "
                IF OBJECT_ID('dbo.CommandExecute', 'P') IS NOT NULL DROP PROCEDURE dbo.CommandExecute;
                IF OBJECT_ID('dbo.DatabaseBackup', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseBackup;
                IF OBJECT_ID('dbo.DatabaseIntegrityCheck', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseIntegrityCheck;
                IF OBJECT_ID('dbo.IndexOptimize', 'P') IS NOT NULL DROP PROCEDURE dbo.IndexOptimize;
                IF OBJECT_ID('dbo.CommandLog', 'U') IS NOT NULL DROP TABLE dbo.CommandLog;
                IF OBJECT_ID('dbo.Queue', 'U') IS NOT NULL DROP TABLE dbo.Queue;
                IF OBJECT_ID('dbo.QueueDatabase', 'U') IS NOT NULL DROP TABLE dbo.QueueDatabase;
            "
            $splatCleanupTempdb = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Database    = "tempdb"
                Query       = $cleanupTempdb
            }
            Invoke-DbaQuery @splatCleanupTempdb

            $testDbName = "dbatoolsci_maintenancesolution_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Name $testDbName

            # We uninstall the scripts after each run,
            # so need it installed first.
            $splatInstall = @{
                SqlInstance      = $TestConfig.InstanceMulti2
                Database         = $testDbName
                InstallJobs      = $true
                ReplaceExisting  = $true
            }
            $installResult = Install-DbaMaintenanceSolution @splatInstall

            # Verify installation succeeded before running tests
            # Skip tests if installation failed (eg. due to event log limitations on AppVeyor or SQL Agent not running)
            $script:installationSucceeded = $false
            if ($installResult) {
                $splatJobCheck = @{
                    SqlInstance = $TestConfig.InstanceMulti2
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

            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $testDbName -Confirm:$false
            $jobs = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Description -match "hallengren"
            if ($jobs) {
                $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 -Job $jobs.Name -Confirm:$false
            }

            # Throws if we already have the setting as we want it to be, so SilentlyContinue instead.
            $splatConfigure = @{
                SqlInstance     = $TestConfig.InstanceMulti2
                ConfigName      = "DefaultBackupCompression"
                Value           = $compressionSettingInitial
                WarningAction   = "SilentlyContinue"
                EnableException = $false
            }
            Set-DbaSpConfigure @splatConfigure

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should have Compress parameter set to Y in backup jobs when we ask for it" {
            $splatInstall = @{
                SqlInstance      = $TestConfig.InstanceMulti2
                Database         = $testDbName
                InstallJobs      = $true
                ReplaceExisting  = $true
                Compress         = $true
            }
            Install-DbaMaintenanceSolution @splatInstall

            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@Compress = 'Y'"
        }

        It "Should have Compress parameter set to N in backup jobs when we refuse it" {
            $splatInstall = @{
                SqlInstance      = $TestConfig.InstanceMulti2
                Database         = $testDbName
                InstallJobs      = $true
                ReplaceExisting  = $true
                Compress         = $false
            }
            Install-DbaMaintenanceSolution @splatInstall

            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@Compress = 'N'"
        }

        # Our documentation says we copy from the configuration
        # of the instance when Compress is not specified.
        It "Should have Compress parameter set to Y in backup jobs when we do not specify it" {
            $splatInstall = @{
                SqlInstance      = $TestConfig.InstanceMulti2
                Database         = $testDbName
                InstallJobs      = $true
                ReplaceExisting  = $true
            }
            Install-DbaMaintenanceSolution @splatInstall

            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@Compress = 'Y'"
        }
    }

    # See previous context.
    Context "Compression tests when instance defaults to compression off" {
        AfterEach {
            # Notice that we are uninstalling after each test.
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti2 -Query $jobStep.Command -NoExec -EnableException

            # Clean up any leftover Hallengren jobs
            $oldJobs = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Description -match "hallengren"
            if ($oldJobs) {
                $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 -Job $oldJobs.Name -Confirm:$false
            }

            # Clean up any leftover Hallengren procedures in tempdb from the first Context
            $cleanupTempdb = "
                IF OBJECT_ID('dbo.CommandExecute', 'P') IS NOT NULL DROP PROCEDURE dbo.CommandExecute;
                IF OBJECT_ID('dbo.DatabaseBackup', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseBackup;
                IF OBJECT_ID('dbo.DatabaseIntegrityCheck', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseIntegrityCheck;
                IF OBJECT_ID('dbo.IndexOptimize', 'P') IS NOT NULL DROP PROCEDURE dbo.IndexOptimize;
                IF OBJECT_ID('dbo.CommandLog', 'U') IS NOT NULL DROP TABLE dbo.CommandLog;
                IF OBJECT_ID('dbo.Queue', 'U') IS NOT NULL DROP TABLE dbo.Queue;
                IF OBJECT_ID('dbo.QueueDatabase', 'U') IS NOT NULL DROP TABLE dbo.QueueDatabase;
            "
            $splatCleanupTempdb = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Database    = "tempdb"
                Query       = $cleanupTempdb
            }
            Invoke-DbaQuery @splatCleanupTempdb

            $testDbName = "dbatoolsci_maintenancesolution_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Name $testDbName
        }

        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $compressionSettingInitial = (Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceMulti2 -ConfigName BackupChecksumDefault).ConfiguredValue
            $splatConfigure = @{
                SqlInstance     = $TestConfig.InstanceMulti2
                ConfigName      = "DefaultBackupCompression"
                Value           = 0
                WarningAction   = "SilentlyContinue"
                EnableException = $false
            }
            Set-DbaSpConfigure @splatConfigure

            # Clean up any leftover test databases from previous runs
            $oldTestDbs = Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Name -like "dbatoolsci_maintenancesolution_*"
            if ($oldTestDbs) {
                $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $oldTestDbs.Name -Confirm:$false
            }

            # Clean up any leftover Hallengren jobs
            $oldJobs = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Description -match "hallengren"
            if ($oldJobs) {
                $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 -Job $oldJobs.Name -Confirm:$false
            }

            # Clean up any leftover Hallengren procedures in tempdb from the first Context
            $cleanupTempdb = "
                IF OBJECT_ID('dbo.CommandExecute', 'P') IS NOT NULL DROP PROCEDURE dbo.CommandExecute;
                IF OBJECT_ID('dbo.DatabaseBackup', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseBackup;
                IF OBJECT_ID('dbo.DatabaseIntegrityCheck', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseIntegrityCheck;
                IF OBJECT_ID('dbo.IndexOptimize', 'P') IS NOT NULL DROP PROCEDURE dbo.IndexOptimize;
                IF OBJECT_ID('dbo.CommandLog', 'U') IS NOT NULL DROP TABLE dbo.CommandLog;
                IF OBJECT_ID('dbo.Queue', 'U') IS NOT NULL DROP TABLE dbo.Queue;
                IF OBJECT_ID('dbo.QueueDatabase', 'U') IS NOT NULL DROP TABLE dbo.QueueDatabase;
            "
            $splatCleanupTempdb = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Database    = "tempdb"
                Query       = $cleanupTempdb
            }
            Invoke-DbaQuery @splatCleanupTempdb

            $testDbName = "dbatoolsci_maintenancesolution_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Name $testDbName

            # We uninstall the scripts after each run,
            # so need it installed first.
            $splatInstall = @{
                SqlInstance      = $TestConfig.InstanceMulti2
                Database         = $testDbName
                InstallJobs      = $true
                ReplaceExisting  = $true
            }
            $installResult = Install-DbaMaintenanceSolution @splatInstall

            # Verify installation succeeded before running tests
            # Skip tests if installation failed (eg. due to event log limitations on AppVeyor or SQL Agent not running)
            $script:installationSucceeded = $false
            if ($installResult) {
                $splatJobCheck = @{
                    SqlInstance = $TestConfig.InstanceMulti2
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

            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $testDbName -Confirm:$false
            $jobs = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 | Where-Object Description -match "hallengren"
            if ($jobs) {
                $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 -Job $jobs.Name -Confirm:$false
            }

            # Throws if we already have the setting as we want it to be, so SilentlyContinue instead.
            $splatConfigure = @{
                SqlInstance     = $TestConfig.InstanceMulti2
                ConfigName      = "DefaultBackupCompression"
                Value           = $compressionSettingInitial
                WarningAction   = "SilentlyContinue"
                EnableException = $false
            }
            Set-DbaSpConfigure @splatConfigure

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should have Compress parameter set to Y in backup jobs when we ask for it" {
            $splatInstall = @{
                SqlInstance      = $TestConfig.InstanceMulti2
                Database         = $testDbName
                InstallJobs      = $true
                ReplaceExisting  = $true
                Compress         = $true
            }
            Install-DbaMaintenanceSolution @splatInstall

            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@Compress = 'Y'"
        }

        It "Should have Compress parameter set to N in backup jobs when we refuse it" {
            $splatInstall = @{
                SqlInstance      = $TestConfig.InstanceMulti2
                Database         = $testDbName
                InstallJobs      = $true
                ReplaceExisting  = $true
                Compress         = $false
            }
            Install-DbaMaintenanceSolution @splatInstall

            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@Compress = 'N'"
        }

        # Our documentation says we copy from the configuration
        # of the instance when Compress is not specified.
        It "Should have Compress parameter set to N in backup jobs when we do not specify it" {
            $splatInstall = @{
                SqlInstance      = $TestConfig.InstanceMulti2
                Database         = $testDbName
                InstallJobs      = $true
                ReplaceExisting  = $true
            }
            Install-DbaMaintenanceSolution @splatInstall

            $splatJobStep = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@Compress = 'N'"
        }
    }
}
