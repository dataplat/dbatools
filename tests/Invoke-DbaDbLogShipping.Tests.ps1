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

Describe $CommandName -Tag IntegrationTests {
    # LogShipping needs additional setup beyond most suites: a running SQL Agent on both
    # instances and a shared backup path in UNC form that both can reach (the command
    # rejects non-UNC paths by validation). Those preconditions are PROBED here so the
    # suite executes wherever the lab provides them and reports an explicit skip reason
    # where it does not, instead of a blanket Describe skip that executes zero tests.
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $primaryDb = "dbatoolsci_logshipping"
        $secondaryDb = "dbatoolsci_logshipping_LS"

        $logShippingReady = $false
        $preconditionError = "not probed"
        try {
            # The backup, copy and restore jobs run under SQL Agent - probe both services
            # over plain SQL auth so the probe works from any seat that can reach the pair.
            $agentQuery = "SELECT status_desc FROM sys.dm_server_services WHERE servicename LIKE 'SQL Server Agent%'"
            $primaryServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
            $secondaryServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2
            if (@($primaryServer.Query($agentQuery)).status_desc -notcontains "Running") {
                $preconditionError = "SQL Agent is not running on the primary instance"
            } elseif (@($secondaryServer.Query($agentQuery)).status_desc -notcontains "Running") {
                $preconditionError = "SQL Agent is not running on the secondary instance"
            } elseif ($TestConfig.Temp -notmatch "^\\\\") {
                $preconditionError = "TestConfig.Temp is not a UNC path and the command requires the shared path in UNC form"
            } else {
                # Log shipping requires the full recovery model; the model database default
                # is not guaranteed on a lab instance.
                $null = $primaryServer.Query("CREATE DATABASE $primaryDb")
                $null = $primaryServer.Query("ALTER DATABASE $primaryDb SET RECOVERY FULL")
                $logShippingReady = $true
            }
        } catch {
            $preconditionError = $_.Exception.Message
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the cleanup fails loudly.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        if ($logShippingReady) {
            $splatRemoveLogShipping = @{
                PrimarySqlInstance      = $TestConfig.InstanceMulti1
                SecondarySqlInstance    = $TestConfig.InstanceMulti2
                Database                = $primaryDb
                RemoveSecondaryDatabase = $true
                Confirm                 = $false
                ErrorAction             = "SilentlyContinue"
            }
            $null = Remove-DbaDbLogShipping @splatRemoveLogShipping
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database $primaryDb -ErrorAction SilentlyContinue
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $secondaryDb -ErrorAction SilentlyContinue
            # The backup share accumulates one folder per shipped database; remove the
            # folder from this run so repeated gate runs do not pile up backup files on the share.
            Remove-Item -Path (Join-Path $TestConfig.Temp $primaryDb) -Recurse -Force -ErrorAction SilentlyContinue
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Setting up log shipping end to end" {
        It "Returns a Success result and the expected database pair" {
            if (-not $logShippingReady) {
                Set-ItResult -Skipped -Because "log shipping preconditions not met on this pair: $preconditionError"
                return
            }
            $splatLogShipping = @{
                SourceSqlInstance       = $TestConfig.InstanceMulti1
                DestinationSqlInstance  = $TestConfig.InstanceMulti2
                Database                = $primaryDb
                SharedPath              = $TestConfig.Temp
                GenerateFullBackup      = $true
                SecondaryDatabaseSuffix = "_LS"
                Force                   = $true
            }
            $results = Invoke-DbaDbLogShipping @splatLogShipping
            $results.Result | Should -Be "Success"
            $results.PrimaryDatabase | Should -Be $primaryDb
            $results.SecondaryDatabase | Should -Be $secondaryDb
        }
    }
}