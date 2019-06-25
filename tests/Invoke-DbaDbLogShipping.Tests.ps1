$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SourceSqlInstance', 'DestinationSqlInstance', 'SourceSqlCredential', 'SourceCredential', 'DestinationSqlCredential', 'DestinationCredential', 'Database', 'SharedPath', 'LocalPath', 'BackupJob', 'BackupRetention', 'BackupSchedule', 'BackupScheduleDisabled', 'BackupScheduleFrequencyType', 'BackupScheduleFrequencyInterval', 'BackupScheduleFrequencySubdayType', 'BackupScheduleFrequencySubdayInterval', 'BackupScheduleFrequencyRelativeInterval', 'BackupScheduleFrequencyRecurrenceFactor', 'BackupScheduleStartDate', 'BackupScheduleEndDate', 'BackupScheduleStartTime', 'BackupScheduleEndTime', 'BackupThreshold', 'CompressBackup', 'CopyDestinationFolder', 'CopyJob', 'CopyRetention', 'CopySchedule', 'CopyScheduleDisabled', 'CopyScheduleFrequencyType', 'CopyScheduleFrequencyInterval', 'CopyScheduleFrequencySubdayType', 'CopyScheduleFrequencySubdayInterval', 'CopyScheduleFrequencyRelativeInterval', 'CopyScheduleFrequencyRecurrenceFactor', 'CopyScheduleStartDate', 'CopyScheduleEndDate', 'CopyScheduleStartTime', 'CopyScheduleEndTime', 'DisconnectUsers', 'FullBackupPath', 'GenerateFullBackup', 'HistoryRetention', 'NoRecovery', 'NoInitialization', 'PrimaryMonitorServer', 'PrimaryMonitorCredential', 'PrimaryMonitorServerSecurityMode', 'PrimaryThresholdAlertEnabled', 'RestoreDataFolder', 'RestoreLogFolder', 'RestoreDelay', 'RestoreAlertThreshold', 'RestoreJob', 'RestoreRetention', 'RestoreSchedule', 'RestoreScheduleDisabled', 'RestoreScheduleFrequencyType', 'RestoreScheduleFrequencyInterval', 'RestoreScheduleFrequencySubdayType', 'RestoreScheduleFrequencySubdayInterval', 'RestoreScheduleFrequencyRelativeInterval', 'RestoreScheduleFrequencyRecurrenceFactor', 'RestoreScheduleStartDate', 'RestoreScheduleEndDate', 'RestoreScheduleStartTime', 'RestoreScheduleEndTime', 'RestoreThreshold', 'SecondaryDatabasePrefix', 'SecondaryDatabaseSuffix', 'SecondaryMonitorServer', 'SecondaryMonitorCredential', 'SecondaryMonitorServerSecurityMode', 'SecondaryThresholdAlertEnabled', 'Standby', 'StandbyDirectory', 'UseExistingFullBackup', 'UseBackupFolder', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
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