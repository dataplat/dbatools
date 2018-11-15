$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        $knownParameters = 'SourceSqlInstance', 'DestinationSqlInstance', 'SourceSqlCredential', 'SourceCredential', 'DestinationSqlCredential', 'DestinationCredential', 'Database', 'BackupNetworkPath', 'BackupLocalPath', 'BackupJob', 'BackupRetention', 'BackupSchedule', 'BackupScheduleDisabled', 'BackupScheduleFrequencyType', 'BackupScheduleFrequencyInterval', 'BackupScheduleFrequencySubdayType', 'BackupScheduleFrequencySubdayInterval', 'BackupScheduleFrequencyRelativeInterval', 'BackupScheduleFrequencyRecurrenceFactor', 'BackupScheduleStartDate', 'BackupScheduleEndDate', 'BackupScheduleStartTime', 'BackupScheduleEndTime', 'BackupThreshold', 'CompressBackup', 'CopyDestinationFolder', 'CopyJob', 'CopyRetention', 'CopySchedule', 'CopyScheduleDisabled', 'CopyScheduleFrequencyType', 'CopyScheduleFrequencyInterval', 'CopyScheduleFrequencySubdayType', 'CopyScheduleFrequencySubdayInterval', 'CopyScheduleFrequencyRelativeInterval', 'CopyScheduleFrequencyRecurrenceFactor', 'CopyScheduleStartDate', 'CopyScheduleEndDate', 'CopyScheduleStartTime', 'CopyScheduleEndTime', 'DisconnectUsers', 'FullBackupPath', 'GenerateFullBackup', 'HistoryRetention', 'NoRecovery', 'NoInitialization', 'PrimaryMonitorServer', 'PrimaryMonitorCredential', 'PrimaryMonitorServerSecurityMode', 'PrimaryThresholdAlertEnabled', 'RestoreDataFolder', 'RestoreLogFolder', 'RestoreDelay', 'RestoreAlertThreshold', 'RestoreJob', 'RestoreRetention', 'RestoreSchedule', 'RestoreScheduleDisabled', 'RestoreScheduleFrequencyType', 'RestoreScheduleFrequencyInterval', 'RestoreScheduleFrequencySubdayType', 'RestoreScheduleFrequencySubdayInterval', 'RestoreScheduleFrequencyRelativeInterval', 'RestoreScheduleFrequencyRecurrenceFactor', 'RestoreScheduleStartDate', 'RestoreScheduleEndDate', 'RestoreScheduleStartTime', 'RestoreScheduleEndTime', 'RestoreThreshold', 'SecondaryDatabasePrefix', 'SecondaryDatabaseSuffix', 'SecondaryMonitorServer', 'SecondaryMonitorCredential', 'SecondaryMonitorServerSecurityMode', 'SecondaryThresholdAlertEnabled', 'Standby', 'StandbyDirectory', 'UseExistingFullBackup', 'UseBackupFolder', 'Force', 'EnableException'
        $SupportShouldProcess = $true
        $paramCount = $knownParameters.Count
        if ($SupportShouldProcess) {
            $defaultParamCount = 13
        } else {
            $defaultParamCount = 11
        }
        $command = Get-Command -Name $CommandName
        [object[]]$params = $command.Parameters.Keys

        It "Should contain our specific parameters" {
            ((Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count) | Should Be $paramCount
        }

        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    # This is a placeholder until we decide on sql2016/sql2017
    BeforeAll {
        $dbname = "dbatoolsci_logshipping"
    }

    It -Skip "returns success" {
        $results = Invoke-DbaDbLogShipping -SourceSqlInstance $script:instance2 -DestinationSqlInstance $script:instance -Database $dbname -BackupNetworkPath C:\temp -BackupLocalPath "C:\temp\logshipping\backup" -GenerateFullBackup -CompressBackup -SecondaryDatabaseSuffix "_LS" -Force
        $results.Status -eq 'Success' | Should Be $true
    }
}