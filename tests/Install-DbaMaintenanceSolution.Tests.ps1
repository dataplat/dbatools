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

            # As this is the last block we do not need to reset the $PSDefaultParameterValues.
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
}