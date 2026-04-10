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
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        Context "IgnoreFileChecks" {
            BeforeAll {
                $script:mockSourceServer = [PSCustomObject]@{
                    ConnectionContext  = [PSCustomObject]@{
                        StatementTimeout = 30
                    }
                    Databases          = @(
                        [PSCustomObject]@{
                            Name          = "db1"
                            RecoveryModel = "Full"
                        }
                    )
                    DomainInstanceName = "source"
                    InstanceName       = "MSSQLSERVER"
                    Name               = "source"
                    Version            = [PSCustomObject]@{
                        Major = 15
                    }
                }
                $script:mockDestinationServer = [PSCustomObject]@{
                    ConnectionContext  = [PSCustomObject]@{
                        StatementTimeout = 30
                    }
                    Databases          = @(
                        [PSCustomObject]@{
                            Name   = "db1"
                            Status = "Restoring"
                        }
                    )
                    DomainInstanceName = "dest"
                    InstanceName       = "MSSQLSERVER"
                    IsAzure            = $false
                    Name               = "dest"
                }

                Mock Connect-DbaInstance -ModuleName dbatools -MockWith {
                    param($SqlInstance)

                    switch ($SqlInstance.FullName) {
                        "source" { return $script:mockSourceServer }
                        "dest" { return $script:mockDestinationServer }
                        default { throw "Unexpected instance $($SqlInstance.FullName)" }
                    }
                }
                Mock Get-DbaSpConfigure -ModuleName dbatools {
                    [PSCustomObject]@{
                        ConfiguredValue = 0
                    }
                }
                Mock Stop-Function -ModuleName dbatools {
                    param($Message)
                    throw $Message
                }
                Mock Test-DbaPath -ModuleName dbatools {
                    param($Path)

                    if ($Path -eq "C:\copy") {
                        return $true
                    }

                    if ($Path -eq "\\source\ls\db1") {
                        return $true
                    }

                    if ($Path -eq "C:\copy\db1") {
                        return $true
                    }

                    return $false
                }
                Mock Test-FunctionInterrupt -ModuleName dbatools { $false }
            }

            It "Should skip the root backup share validation when IgnoreFileChecks is used" {
                $splatLogShipping = @{
                    SourceSqlInstance      = "source"
                    DestinationSqlInstance = "dest"
                    Database               = "db1"
                    SharedPath             = "\\source\ls"
                    CopyDestinationFolder  = "C:\copy"
                    NoInitialization       = $true
                    IgnoreFileChecks       = $true
                    Force                  = $true
                    WhatIf                 = $true
                }

                $results = Invoke-DbaDbLogShipping @splatLogShipping

                $results.Result | Should -Be "Success"
                Should -Invoke Test-DbaPath -ModuleName dbatools -Times 0 -Exactly -ParameterFilter {
                    $Path -eq "\\source\ls"
                }
                Should -Invoke Test-DbaPath -ModuleName dbatools -Times 1 -Exactly -ParameterFilter {
                    $Path -eq "\\source\ls\db1"
                }
            }
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
            SourceSqlInstance       = $TestConfig.InstanceSingle
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