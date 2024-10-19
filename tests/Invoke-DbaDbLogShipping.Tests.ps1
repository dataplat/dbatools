param($ModuleName = 'dbatools')

Describe "Invoke-DbaDbLogShipping" {
    BeforeAll {
        $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
        $dbname = "dbatoolsci_logshipping"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Invoke-DbaDbLogShipping
        }
        It "Should have SourceSqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SourceSqlInstance
        }
        It "Should have DestinationSqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlInstance
        }
        It "Should have SourceSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SourceSqlCredential
        }
        It "Should have SourceCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SourceCredential
        }
        It "Should have DestinationSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential
        }
        It "Should have DestinationCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have SharedPath as a parameter" {
            $CommandUnderTest | Should -HaveParameter SharedPath
        }
        It "Should have LocalPath as a parameter" {
            $CommandUnderTest | Should -HaveParameter LocalPath
        }
        It "Should have BackupJob as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupJob
        }
        It "Should have BackupRetention as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupRetention
        }
        It "Should have BackupSchedule as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupSchedule
        }
        It "Should have BackupScheduleDisabled as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupScheduleDisabled
        }
        It "Should have BackupScheduleFrequencyType as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupScheduleFrequencyType
        }
        It "Should have BackupScheduleFrequencyInterval as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupScheduleFrequencyInterval
        }
        It "Should have BackupScheduleFrequencySubdayType as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupScheduleFrequencySubdayType
        }
        It "Should have BackupScheduleFrequencySubdayInterval as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupScheduleFrequencySubdayInterval
        }
        It "Should have BackupScheduleFrequencyRelativeInterval as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupScheduleFrequencyRelativeInterval
        }
        It "Should have BackupScheduleFrequencyRecurrenceFactor as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupScheduleFrequencyRecurrenceFactor
        }
        It "Should have BackupScheduleStartDate as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupScheduleStartDate
        }
        It "Should have BackupScheduleEndDate as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupScheduleEndDate
        }
        It "Should have BackupScheduleStartTime as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupScheduleStartTime
        }
        It "Should have BackupScheduleEndTime as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupScheduleEndTime
        }
        It "Should have BackupThreshold as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupThreshold
        }
        It "Should have CompressBackup as a parameter" {
            $CommandUnderTest | Should -HaveParameter CompressBackup
        }
        It "Should have CopyDestinationFolder as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyDestinationFolder
        }
        It "Should have CopyJob as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyJob
        }
        It "Should have CopyRetention as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyRetention
        }
        It "Should have CopySchedule as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopySchedule
        }
        It "Should have CopyScheduleDisabled as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyScheduleDisabled
        }
        It "Should have CopyScheduleFrequencyType as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyScheduleFrequencyType
        }
        It "Should have CopyScheduleFrequencyInterval as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyScheduleFrequencyInterval
        }
        It "Should have CopyScheduleFrequencySubdayType as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyScheduleFrequencySubdayType
        }
        It "Should have CopyScheduleFrequencySubdayInterval as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyScheduleFrequencySubdayInterval
        }
        It "Should have CopyScheduleFrequencyRelativeInterval as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyScheduleFrequencyRelativeInterval
        }
        It "Should have CopyScheduleFrequencyRecurrenceFactor as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyScheduleFrequencyRecurrenceFactor
        }
        It "Should have CopyScheduleStartDate as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyScheduleStartDate
        }
        It "Should have CopyScheduleEndDate as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyScheduleEndDate
        }
        It "Should have CopyScheduleStartTime as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyScheduleStartTime
        }
        It "Should have CopyScheduleEndTime as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyScheduleEndTime
        }
        It "Should have DisconnectUsers as a parameter" {
            $CommandUnderTest | Should -HaveParameter DisconnectUsers
        }
        It "Should have FullBackupPath as a parameter" {
            $CommandUnderTest | Should -HaveParameter FullBackupPath
        }
        It "Should have GenerateFullBackup as a parameter" {
            $CommandUnderTest | Should -HaveParameter GenerateFullBackup
        }
        It "Should have HistoryRetention as a parameter" {
            $CommandUnderTest | Should -HaveParameter HistoryRetention
        }
        It "Should have NoRecovery as a parameter" {
            $CommandUnderTest | Should -HaveParameter NoRecovery
        }
        It "Should have NoInitialization as a parameter" {
            $CommandUnderTest | Should -HaveParameter NoInitialization
        }
        It "Should have PrimaryMonitorServer as a parameter" {
            $CommandUnderTest | Should -HaveParameter PrimaryMonitorServer
        }
        It "Should have PrimaryMonitorCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter PrimaryMonitorCredential
        }
        It "Should have PrimaryMonitorServerSecurityMode as a parameter" {
            $CommandUnderTest | Should -HaveParameter PrimaryMonitorServerSecurityMode
        }
        It "Should have PrimaryThresholdAlertEnabled as a parameter" {
            $CommandUnderTest | Should -HaveParameter PrimaryThresholdAlertEnabled
        }
        It "Should have RestoreDataFolder as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreDataFolder
        }
        It "Should have RestoreLogFolder as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreLogFolder
        }
        It "Should have RestoreDelay as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreDelay
        }
        It "Should have RestoreAlertThreshold as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreAlertThreshold
        }
        It "Should have RestoreJob as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreJob
        }
        It "Should have RestoreRetention as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreRetention
        }
        It "Should have RestoreSchedule as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreSchedule
        }
        It "Should have RestoreScheduleDisabled as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreScheduleDisabled
        }
        It "Should have RestoreScheduleFrequencyType as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreScheduleFrequencyType
        }
        It "Should have RestoreScheduleFrequencyInterval as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreScheduleFrequencyInterval
        }
        It "Should have RestoreScheduleFrequencySubdayType as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreScheduleFrequencySubdayType
        }
        It "Should have RestoreScheduleFrequencySubdayInterval as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreScheduleFrequencySubdayInterval
        }
        It "Should have RestoreScheduleFrequencyRelativeInterval as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreScheduleFrequencyRelativeInterval
        }
        It "Should have RestoreScheduleFrequencyRecurrenceFactor as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreScheduleFrequencyRecurrenceFactor
        }
        It "Should have RestoreScheduleStartDate as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreScheduleStartDate
        }
        It "Should have RestoreScheduleEndDate as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreScheduleEndDate
        }
        It "Should have RestoreScheduleStartTime as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreScheduleStartTime
        }
        It "Should have RestoreScheduleEndTime as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreScheduleEndTime
        }
        It "Should have RestoreThreshold as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreThreshold
        }
        It "Should have SecondaryDatabasePrefix as a parameter" {
            $CommandUnderTest | Should -HaveParameter SecondaryDatabasePrefix
        }
        It "Should have SecondaryDatabaseSuffix as a parameter" {
            $CommandUnderTest | Should -HaveParameter SecondaryDatabaseSuffix
        }
        It "Should have SecondaryMonitorServer as a parameter" {
            $CommandUnderTest | Should -HaveParameter SecondaryMonitorServer
        }
        It "Should have SecondaryMonitorCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SecondaryMonitorCredential
        }
        It "Should have SecondaryMonitorServerSecurityMode as a parameter" {
            $CommandUnderTest | Should -HaveParameter SecondaryMonitorServerSecurityMode
        }
        It "Should have SecondaryThresholdAlertEnabled as a parameter" {
            $CommandUnderTest | Should -HaveParameter SecondaryThresholdAlertEnabled
        }
        It "Should have Standby as a parameter" {
            $CommandUnderTest | Should -HaveParameter Standby
        }
        It "Should have StandbyDirectory as a parameter" {
            $CommandUnderTest | Should -HaveParameter StandbyDirectory
        }
        It "Should have UseExistingFullBackup as a parameter" {
            $CommandUnderTest | Should -HaveParameter UseExistingFullBackup
        }
        It "Should have UseBackupFolder as a parameter" {
            $CommandUnderTest | Should -HaveParameter UseBackupFolder
        }
        It "Should have Force as a parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            $env:skipIntegrationTests = [Environment]::GetEnvironmentVariable('appveyor') -ne $true
        }

        It "returns success" -Skip:$skipIntegrationTests {
            $results = Invoke-DbaDbLogShipping -SourceSqlInstance $global:instance2 -DestinationSqlInstance $global:instance -Database $dbname -BackupNetworkPath C:\temp -BackupLocalPath "C:\temp\logshipping\backup" -GenerateFullBackup -CompressBackup -SecondaryDatabaseSuffix "_LS" -Force
            $results.Status | Should -Be 'Success'
        }
    }
}
