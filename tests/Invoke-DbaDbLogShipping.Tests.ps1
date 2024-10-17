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
            $CommandUnderTest | Should -HaveParameter SourceSqlInstance -Type DbaInstanceParameter
        }
        It "Should have DestinationSqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SourceSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SourceSqlCredential -Type PSCredential
        }
        It "Should have SourceCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SourceCredential -Type PSCredential
        }
        It "Should have DestinationSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential -Type PSCredential
        }
        It "Should have DestinationCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[]
        }
        It "Should have SharedPath as a parameter" {
            $CommandUnderTest | Should -HaveParameter SharedPath -Type String
        }
        It "Should have LocalPath as a parameter" {
            $CommandUnderTest | Should -HaveParameter LocalPath -Type String
        }
        It "Should have BackupJob as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupJob -Type String
        }
        It "Should have BackupRetention as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupRetention -Type Int32
        }
        It "Should have BackupSchedule as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupSchedule -Type String
        }
        It "Should have BackupScheduleDisabled as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupScheduleDisabled -Type Switch
        }
        It "Should have BackupScheduleFrequencyType as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupScheduleFrequencyType -Type Object
        }
        It "Should have BackupScheduleFrequencyInterval as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupScheduleFrequencyInterval -Type Object[]
        }
        It "Should have BackupScheduleFrequencySubdayType as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupScheduleFrequencySubdayType -Type Object
        }
        It "Should have BackupScheduleFrequencySubdayInterval as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupScheduleFrequencySubdayInterval -Type Int32
        }
        It "Should have BackupScheduleFrequencyRelativeInterval as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupScheduleFrequencyRelativeInterval -Type Object
        }
        It "Should have BackupScheduleFrequencyRecurrenceFactor as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupScheduleFrequencyRecurrenceFactor -Type Int32
        }
        It "Should have BackupScheduleStartDate as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupScheduleStartDate -Type String
        }
        It "Should have BackupScheduleEndDate as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupScheduleEndDate -Type String
        }
        It "Should have BackupScheduleStartTime as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupScheduleStartTime -Type String
        }
        It "Should have BackupScheduleEndTime as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupScheduleEndTime -Type String
        }
        It "Should have BackupThreshold as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupThreshold -Type Int32
        }
        It "Should have CompressBackup as a parameter" {
            $CommandUnderTest | Should -HaveParameter CompressBackup -Type Switch
        }
        It "Should have CopyDestinationFolder as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyDestinationFolder -Type String
        }
        It "Should have CopyJob as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyJob -Type String
        }
        It "Should have CopyRetention as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyRetention -Type Int32
        }
        It "Should have CopySchedule as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopySchedule -Type String
        }
        It "Should have CopyScheduleDisabled as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyScheduleDisabled -Type Switch
        }
        It "Should have CopyScheduleFrequencyType as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyScheduleFrequencyType -Type Object
        }
        It "Should have CopyScheduleFrequencyInterval as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyScheduleFrequencyInterval -Type Object[]
        }
        It "Should have CopyScheduleFrequencySubdayType as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyScheduleFrequencySubdayType -Type Object
        }
        It "Should have CopyScheduleFrequencySubdayInterval as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyScheduleFrequencySubdayInterval -Type Int32
        }
        It "Should have CopyScheduleFrequencyRelativeInterval as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyScheduleFrequencyRelativeInterval -Type Object
        }
        It "Should have CopyScheduleFrequencyRecurrenceFactor as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyScheduleFrequencyRecurrenceFactor -Type Int32
        }
        It "Should have CopyScheduleStartDate as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyScheduleStartDate -Type String
        }
        It "Should have CopyScheduleEndDate as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyScheduleEndDate -Type String
        }
        It "Should have CopyScheduleStartTime as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyScheduleStartTime -Type String
        }
        It "Should have CopyScheduleEndTime as a parameter" {
            $CommandUnderTest | Should -HaveParameter CopyScheduleEndTime -Type String
        }
        It "Should have DisconnectUsers as a parameter" {
            $CommandUnderTest | Should -HaveParameter DisconnectUsers -Type Switch
        }
        It "Should have FullBackupPath as a parameter" {
            $CommandUnderTest | Should -HaveParameter FullBackupPath -Type String
        }
        It "Should have GenerateFullBackup as a parameter" {
            $CommandUnderTest | Should -HaveParameter GenerateFullBackup -Type Switch
        }
        It "Should have HistoryRetention as a parameter" {
            $CommandUnderTest | Should -HaveParameter HistoryRetention -Type Int32
        }
        It "Should have NoRecovery as a parameter" {
            $CommandUnderTest | Should -HaveParameter NoRecovery -Type Switch
        }
        It "Should have NoInitialization as a parameter" {
            $CommandUnderTest | Should -HaveParameter NoInitialization -Type Switch
        }
        It "Should have PrimaryMonitorServer as a parameter" {
            $CommandUnderTest | Should -HaveParameter PrimaryMonitorServer -Type String
        }
        It "Should have PrimaryMonitorCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter PrimaryMonitorCredential -Type PSCredential
        }
        It "Should have PrimaryMonitorServerSecurityMode as a parameter" {
            $CommandUnderTest | Should -HaveParameter PrimaryMonitorServerSecurityMode -Type Object
        }
        It "Should have PrimaryThresholdAlertEnabled as a parameter" {
            $CommandUnderTest | Should -HaveParameter PrimaryThresholdAlertEnabled -Type Switch
        }
        It "Should have RestoreDataFolder as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreDataFolder -Type String
        }
        It "Should have RestoreLogFolder as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreLogFolder -Type String
        }
        It "Should have RestoreDelay as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreDelay -Type Int32
        }
        It "Should have RestoreAlertThreshold as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreAlertThreshold -Type Int32
        }
        It "Should have RestoreJob as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreJob -Type String
        }
        It "Should have RestoreRetention as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreRetention -Type Int32
        }
        It "Should have RestoreSchedule as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreSchedule -Type String
        }
        It "Should have RestoreScheduleDisabled as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreScheduleDisabled -Type Switch
        }
        It "Should have RestoreScheduleFrequencyType as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreScheduleFrequencyType -Type Object
        }
        It "Should have RestoreScheduleFrequencyInterval as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreScheduleFrequencyInterval -Type Object[]
        }
        It "Should have RestoreScheduleFrequencySubdayType as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreScheduleFrequencySubdayType -Type Object
        }
        It "Should have RestoreScheduleFrequencySubdayInterval as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreScheduleFrequencySubdayInterval -Type Int32
        }
        It "Should have RestoreScheduleFrequencyRelativeInterval as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreScheduleFrequencyRelativeInterval -Type Object
        }
        It "Should have RestoreScheduleFrequencyRecurrenceFactor as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreScheduleFrequencyRecurrenceFactor -Type Int32
        }
        It "Should have RestoreScheduleStartDate as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreScheduleStartDate -Type String
        }
        It "Should have RestoreScheduleEndDate as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreScheduleEndDate -Type String
        }
        It "Should have RestoreScheduleStartTime as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreScheduleStartTime -Type String
        }
        It "Should have RestoreScheduleEndTime as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreScheduleEndTime -Type String
        }
        It "Should have RestoreThreshold as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreThreshold -Type Int32
        }
        It "Should have SecondaryDatabasePrefix as a parameter" {
            $CommandUnderTest | Should -HaveParameter SecondaryDatabasePrefix -Type String
        }
        It "Should have SecondaryDatabaseSuffix as a parameter" {
            $CommandUnderTest | Should -HaveParameter SecondaryDatabaseSuffix -Type String
        }
        It "Should have SecondaryMonitorServer as a parameter" {
            $CommandUnderTest | Should -HaveParameter SecondaryMonitorServer -Type String
        }
        It "Should have SecondaryMonitorCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SecondaryMonitorCredential -Type PSCredential
        }
        It "Should have SecondaryMonitorServerSecurityMode as a parameter" {
            $CommandUnderTest | Should -HaveParameter SecondaryMonitorServerSecurityMode -Type Object
        }
        It "Should have SecondaryThresholdAlertEnabled as a parameter" {
            $CommandUnderTest | Should -HaveParameter SecondaryThresholdAlertEnabled -Type Switch
        }
        It "Should have Standby as a parameter" {
            $CommandUnderTest | Should -HaveParameter Standby -Type Switch
        }
        It "Should have StandbyDirectory as a parameter" {
            $CommandUnderTest | Should -HaveParameter StandbyDirectory -Type String
        }
        It "Should have UseExistingFullBackup as a parameter" {
            $CommandUnderTest | Should -HaveParameter UseExistingFullBackup -Type Switch
        }
        It "Should have UseBackupFolder as a parameter" {
            $CommandUnderTest | Should -HaveParameter UseBackupFolder -Type String
        }
        It "Should have Force as a parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
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
