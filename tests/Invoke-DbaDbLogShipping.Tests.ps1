#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
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
                "AzureBaseUrl",
                "AzureCredential",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Azure parameter validation" {
        It "Should have FileShare and AzureBlob parameter sets" {
            $command = Get-Command $CommandName
            $parameterSets = $command.ParameterSets.Name
            $parameterSets | Should -Contain "FileShare"
            $parameterSets | Should -Contain "AzureBlob"
        }

        It "SharedPath should be in FileShare parameter set" {
            $command = Get-Command $CommandName
            $sharedPathParam = $command.Parameters["SharedPath"]
            $sharedPathParam.ParameterSets.Keys | Should -Contain "FileShare"
        }

        It "AzureBaseUrl should be in AzureBlob parameter set" {
            $command = Get-Command $CommandName
            $azureParam = $command.Parameters["AzureBaseUrl"]
            $azureParam.ParameterSets.Keys | Should -Contain "AzureBlob"
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip {
    # Skip IntegrationTests because LogShipping need additional setup.

    # This is a placeholder until we decide on sql2016/sql2017
    BeforeAll {
        $dbname = "dbatoolsci_logshipping"
    }

    It "returns success" {
        $splatLogShipping = @{
            SourceSqlInstance       = $TestConfig.instance2
            DestinationSqlInstance  = $TestConfig.instance
            Database                = $dbname
            BackupNetworkPath       = "C:\temp"
            BackupLocalPath         = "C:\temp\logshipping\backup"
            GenerateFullBackup      = $true
            CompressBackup          = $true
            SecondaryDatabaseSuffix = "_LS"
            Force                   = $true
        }
        $results = Invoke-DbaDbLogShipping @splatLogShipping
        $results.Status -eq "Success" | Should -Be $true
    }
}