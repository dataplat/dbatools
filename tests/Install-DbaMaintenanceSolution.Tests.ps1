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

            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $server.Databases['tempdb'].Query("CREATE TABLE CommandLog (id int)")

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $server.Databases['tempdb'].Query("DROP TABLE CommandLog")
            Invoke-DbaQuery -SqlInstance $TestConfig.instance3 -Database tempdb -Query "drop procedure CommandExecute; drop procedure DatabaseBackup; drop procedure DatabaseIntegrityCheck; drop procedure IndexOptimize;"

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "does not overwrite existing" {
            $results = Install-DbaMaintenanceSolution -SqlInstance $TestConfig.instance2 -Database tempdb -WarningAction SilentlyContinue
            $WarnVar | Should -Match "already exists"
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

            $testDbName = "dbatoolsci_maintenancesolution_$(Get-Random)"

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
            $null = Install-DbaMaintenanceSolution @splatInstall

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

        It "Should add ChangeBackupType parameter to DIFF backup job" {
            $splatJobStep = @{
                SqlInstance = $TestConfig.instance3
                Job         = "DatabaseBackup - USER_DATABASES - DIFF"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@ChangeBackupType = 'Y'"
        }

        It "Should add ChangeBackupType parameter to LOG backup job" {
            $splatJobStep = @{
                SqlInstance = $TestConfig.instance3
                Job         = "DatabaseBackup - USER_DATABASES - LOG"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@ChangeBackupType = 'Y'"
        }

        It "Should NOT add ChangeBackupType parameter to FULL backup job" {
            $splatJobStep = @{
                SqlInstance = $TestConfig.instance3
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Not -Match "@ChangeBackupType = 'Y'"
        }

        It "Should add Compress parameter to all backup jobs" {
            $splatJobStep = @{
                SqlInstance = $TestConfig.instance3
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@Compress = 'Y'"
        }

        It "Should have Verify parameter set to Y in backup jobs" {
            $splatJobStep = @{
                SqlInstance = $TestConfig.instance3
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@Verify = 'Y'"
        }

        It "Should have CheckSum parameter set to Y in backup jobs" {
            $splatJobStep = @{
                SqlInstance = $TestConfig.instance3
                Job         = "DatabaseBackup - USER_DATABASES - FULL"
            }
            $jobStep = Get-DbaAgentJobStep @splatJobStep
            $jobStep.Command | Should -Match "@CheckSum = 'Y'"
        }
    }
}