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

    Context "When a helper fails after the setup phases" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $primaryDatabase = "dbatoolsci_lsfail_$(Get-Random)"
            $secondaryDatabase = "$($primaryDatabase)_ls"
            $sharedPath = Join-Path -Path $TestConfig.Temp -ChildPath "dbatoolsci_lsfail_$(Get-Random)"
            $null = New-Item -Path $sharedPath -ItemType Directory
            # The copy destination has to exist and be passed explicitly: for a missing default
            # folder the command falls into a raw PromptForChoice, which a non-interactive session
            # cannot answer.
            $copyDestinationFolder = Join-Path -Path $sharedPath -ChildPath "copy"
            $null = New-Item -Path $copyDestinationFolder -ItemType Directory

            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceHadr -Name $primaryDatabase -RecoveryModel Full
            # The full backup is taken here and passed via UseExistingFullBackup: letting the
            # command generate its own backup fails on this lab, because SQL Server cannot verify
            # the freshly created per-database subfolder below the share.
            $null = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceHadr -Database $primaryDatabase -Path $sharedPath -Type Full

            # The helper is the first call inside the primary region try block, so failing it
            # exercises the catch without creating log shipping metadata or agent jobs. Everything
            # before the helper - backup generation, restore of the secondary - runs for real.
            Mock -CommandName New-DbaLogShippingPrimaryDatabase -ModuleName dbatools -MockWith {
                throw "Simulated helper failure"
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceHadr -Database $primaryDatabase, $secondaryDatabase
            Remove-Item -Path $sharedPath -Recurse -Force -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Emits the failed status object instead of skipping it" {
            # Before the fix the catch around the primary helpers ran Stop-Function -Continue,
            # which advanced the per-database loop past the status object at the end of the
            # iteration: a helper failure returned nothing at all.
            $splatLogShipping = @{
                SourceSqlInstance       = $TestConfig.InstanceHadr
                DestinationSqlInstance  = $TestConfig.InstanceHadr
                Database                = $primaryDatabase
                SharedPath              = $sharedPath
                CopyDestinationFolder   = $copyDestinationFolder
                UseExistingFullBackup   = $true
                SecondaryDatabaseSuffix = "_ls"
                WarningAction           = "SilentlyContinue"
            }
            $results = Invoke-DbaDbLogShipping @splatLogShipping

            $results | Should -Not -BeNullOrEmpty
            $results.Result | Should -Be "Failed"
            $results.Comment | Should -Be "Something went wrong setting up log shipping for primary instance"
            $results.PrimaryDatabase | Should -Be $primaryDatabase
            $WarnVar | Should -BeLike "*primary instance*"
            Should -Invoke -CommandName New-DbaLogShippingPrimaryDatabase -ModuleName dbatools -Times 1 -Exactly
        }
    }
}
