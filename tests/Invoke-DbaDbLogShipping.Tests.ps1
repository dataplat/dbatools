#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Invoke-DbaDbLogShipping",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SourceSqlInstance",
                "DestinationSqlInstance",
                "SourceSqlCredential",
                "SourceCredential",
                "DestinationSqlCredential",
                "DestinationCredential",
                "Database",
                "SharedPath",
                "LocalPath",
                "BackupJob",
                "BackupRetention",
                "BackupSchedule",
                "BackupScheduleDisabled",
                "BackupScheduleFrequencyType",
                "BackupScheduleFrequencyInterval",
                "BackupScheduleFrequencySubdayType",
                "BackupScheduleFrequencySubdayInterval",
                "BackupScheduleFrequencyRelativeInterval",
                "BackupScheduleFrequencyRecurrenceFactor",
                "BackupScheduleStartDate",
                "BackupScheduleEndDate",
                "BackupScheduleStartTime",
                "BackupScheduleEndTime",
                "BackupThreshold",
                "CompressBackup",
                "CopyDestinationFolder",
                "CopyJob",
                "CopyRetention",
                "CopySchedule",
                "CopyScheduleDisabled",
                "CopyScheduleFrequencyType",
                "CopyScheduleFrequencyInterval",
                "CopyScheduleFrequencySubdayType",
                "CopyScheduleFrequencySubdayInterval",
                "CopyScheduleFrequencyRelativeInterval",
                "CopyScheduleFrequencyRecurrenceFactor",
                "CopyScheduleStartDate",
                "CopyScheduleEndDate",
                "CopyScheduleStartTime",
                "CopyScheduleEndTime",
                "DisconnectUsers",
                "FullBackupPath",
                "GenerateFullBackup",
                "HistoryRetention",
                "NoRecovery",
                "NoInitialization",
                "PrimaryMonitorServer",
                "PrimaryMonitorCredential",
                "PrimaryMonitorServerSecurityMode",
                "PrimaryThresholdAlertEnabled",
                "RestoreDataFolder",
                "RestoreLogFolder",
                "RestoreDelay",
                "RestoreAlertThreshold",
                "RestoreJob",
                "RestoreRetention",
                "RestoreSchedule",
                "RestoreScheduleDisabled",
                "RestoreScheduleFrequencyType",
                "RestoreScheduleFrequencyInterval",
                "RestoreScheduleFrequencySubdayType",
                "RestoreScheduleFrequencySubdayInterval",
                "RestoreScheduleFrequencyRelativeInterval",
                "RestoreScheduleFrequencyRecurrenceFactor",
                "RestoreScheduleStartDate",
                "RestoreScheduleEndDate",
                "RestoreScheduleStartTime",
                "RestoreScheduleEndTime",
                "RestoreThreshold",
                "SecondaryDatabasePrefix",
                "SecondaryDatabaseSuffix",
                "SecondaryMonitorServer",
                "SecondaryMonitorCredential",
                "SecondaryMonitorServerSecurityMode",
                "SecondaryThresholdAlertEnabled",
                "Standby",
                "StandbyDirectory",
                "UseExistingFullBackup",
                "UseBackupFolder",
                "IgnoreFileChecks",
                "AzureBaseUrl",
                "AzureCredential",
                "AddSecondary",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When no database name is supplied" {
        It "Warns without eating an iteration of the caller's loop" {
            # The empty-database guard used to run Stop-Function -Continue without an enclosing loop -
            # the continue escaped the command and consumed an iteration of this very loop, so the
            # counter fell short. The log shipping helper functions carried the same defect and their
            # escapes bypassed this command's own catch blocks (#10638).
            $loopCount = 0
            foreach ($i in 1..3) {
                # The share is never touched: it only has to look like a UNC path so that the guards
                # before the database check pass, and IgnoreFileChecks skips the reachability test.
                # On CI $TestConfig.Temp is a local path and would trip the UNC form check instead.
                $splatEmptyDatabase = @{
                    SourceSqlInstance      = $TestConfig.InstanceHadr
                    DestinationSqlInstance = $TestConfig.InstanceHadr
                    Database               = ""
                    SharedPath             = "\\dbatoolsci\notashare"
                    IgnoreFileChecks       = $true
                    WarningAction          = "SilentlyContinue"
                }
                $null = Invoke-DbaDbLogShipping @splatEmptyDatabase
                $loopCount++
            }
            $loopCount | Should -Be 3
            $WarnVar | Should -BeLike "*Please supply a database*"
        }
    }
}
