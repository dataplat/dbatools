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

    InModuleScope dbatools {
        Context "Adding a secondary to an existing log shipping primary" {
            BeforeEach {
                $script:primaryExists = $true
                $script:primaryBackupDirectory = "C:\ls\db1"
                $script:primaryBackupShare = "\\source\ls\db1"
                $script:primaryBackupJob = "LSBackup_db1"
                $script:associationExists = $false
                $script:associationServerName = $null
                $script:associationDatabaseName = $null
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
                    DomainInstanceName = "dest.contoso"
                    InstanceName       = "MSSQLSERVER"
                    IsAzure            = $false
                    Name               = "dest"
                }

                Mock Connect-DbaInstance -ModuleName dbatools {
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
                Mock Invoke-DbaQuery -ModuleName dbatools -RemoveParameterType "SqlInstance" {
                    if ($Query -match "backup_directory") {
                        if ($script:primaryExists) {
                            return [PSCustomObject]@{
                                BackupDirectory = $script:primaryBackupDirectory
                                BackupShare     = $script:primaryBackupShare
                                BackupJob       = $script:primaryBackupJob
                            }
                        }
                        return $null
                    }
                    if ($Query -match "log_shipping_primary_secondaries") {
                        if ($script:associationExists -and
                            ($null -eq $script:associationServerName -or $Query.Contains("N'$($script:associationServerName)'")) -and
                            ($null -eq $script:associationDatabaseName -or $Query.Contains("pd.primary_database = N'$($script:associationDatabaseName)'"))) {
                            return [PSCustomObject]@{
                                AssociationExists = 1
                            }
                        }
                        return $null
                    }
                    throw "Unexpected query: $Query"
                }
                Mock Test-DbaPath -ModuleName dbatools { $true }
                Mock Test-FunctionInterrupt -ModuleName dbatools { $false }
                Mock Stop-Function -ModuleName dbatools {
                    param($Message)
                    throw $Message
                }
                Mock New-DbaLogShippingPrimaryDatabase -ModuleName dbatools
                Mock New-DbaLogShippingPrimarySecondary -ModuleName dbatools
                Mock New-DbaLogShippingSecondaryPrimary -ModuleName dbatools
                Mock New-DbaLogShippingSecondaryDatabase -ModuleName dbatools
                Mock Remove-DbaAgentJob -ModuleName dbatools
                Mock New-DbaAgentSchedule -ModuleName dbatools
                Mock Set-DbaAgentJob -ModuleName dbatools
            }

            It "reuses the primary configuration and creates only the new secondary relationship" {
                $splatLogShipping = @{
                    SourceSqlInstance      = "source"
                    DestinationSqlInstance = "dest"
                    Database               = "db1"
                    CopyDestinationFolder  = "C:\copy"
                    NoInitialization       = $true
                    IgnoreFileChecks       = $true
                    AddSecondary           = $true
                    Force                  = $true
                }

                $result = Invoke-DbaDbLogShipping @splatLogShipping

                $result.Result | Should -Be "Success"
                Should -Invoke New-DbaLogShippingPrimaryDatabase -ModuleName dbatools -Times 0 -Exactly
                Should -Invoke Set-DbaAgentJob -ModuleName dbatools -Times 0 -Exactly -ParameterFilter {
                    $Job -eq "LSBackup_db1"
                }
                Should -Invoke New-DbaAgentSchedule -ModuleName dbatools -Times 0 -Exactly -ParameterFilter {
                    $Job -eq "LSBackup_db1"
                }
                Should -Invoke New-DbaLogShippingPrimarySecondary -ModuleName dbatools -Times 1 -Exactly
                Should -Invoke New-DbaLogShippingSecondaryPrimary -ModuleName dbatools -Times 1 -Exactly -ParameterFilter {
                    $BackupSourceDirectory -eq "\\source\ls\db1"
                }
                Should -Invoke New-DbaLogShippingSecondaryDatabase -ModuleName dbatools -Times 1 -Exactly
            }

            It "stops when the database is not an existing log shipping primary" {
                $script:primaryExists = $false

                $splatLogShipping = @{
                    SourceSqlInstance      = "source"
                    DestinationSqlInstance = "dest"
                    Database               = "db1"
                    CopyDestinationFolder  = "C:\copy"
                    NoInitialization       = $true
                    AddSecondary           = $true
                    Force                  = $true
                }

                $addMissingPrimaryAction = { Invoke-DbaDbLogShipping @splatLogShipping }
                $addMissingPrimaryAction | Should -Throw "*not configured as a log shipping primary*"
                Should -Invoke New-DbaLogShippingPrimarySecondary -ModuleName dbatools -Times 0 -Exactly
                Should -Invoke New-DbaLogShippingSecondaryPrimary -ModuleName dbatools -Times 0 -Exactly
                Should -Invoke New-DbaLogShippingSecondaryDatabase -ModuleName dbatools -Times 0 -Exactly
            }

            It "stops when the selected secondary is already associated with the primary" {
                $script:associationExists = $true
                $script:associationServerName = "dest.contoso"

                $splatLogShipping = @{
                    SourceSqlInstance      = "source"
                    DestinationSqlInstance = "dest"
                    Database               = "db1"
                    CopyDestinationFolder  = "C:\copy"
                    NoInitialization       = $true
                    IgnoreFileChecks       = $true
                    AddSecondary           = $true
                    Force                  = $true
                }

                $addDuplicateSecondaryAction = { Invoke-DbaDbLogShipping @splatLogShipping }
                $addDuplicateSecondaryAction | Should -Throw "*already associated*"
                Should -Invoke New-DbaLogShippingPrimarySecondary -ModuleName dbatools -Times 0 -Exactly
                Should -Invoke New-DbaLogShippingSecondaryPrimary -ModuleName dbatools -Times 0 -Exactly
                Should -Invoke New-DbaLogShippingSecondaryDatabase -ModuleName dbatools -Times 0 -Exactly
            }

            It "stops when the existing primary metadata is incomplete" {
                $script:primaryBackupJob = ""

                $splatLogShipping = @{
                    SourceSqlInstance      = "source"
                    DestinationSqlInstance = "dest"
                    Database               = "db1"
                    CopyDestinationFolder  = "C:\copy"
                    NoInitialization       = $true
                    AddSecondary           = $true
                    Force                  = $true
                }

                $addIncompletePrimaryAction = { Invoke-DbaDbLogShipping @splatLogShipping }
                $addIncompletePrimaryAction | Should -Throw "*missing its backup directory, share, or backup job*"
                Should -Invoke New-DbaLogShippingPrimarySecondary -ModuleName dbatools -Times 0 -Exactly
                Should -Invoke New-DbaLogShippingSecondaryPrimary -ModuleName dbatools -Times 0 -Exactly
                Should -Invoke New-DbaLogShippingSecondaryDatabase -ModuleName dbatools -Times 0 -Exactly
            }

            It "reuses the existing Azure URL without appending the database twice" {
                $script:primaryBackupDirectory = "https://storage.blob.core.windows.net/logshipping/db1"
                $script:primaryBackupShare = "https://storage.blob.core.windows.net/logshipping/db1"

                $splatLogShipping = @{
                    SourceSqlInstance      = "source"
                    DestinationSqlInstance = "dest"
                    Database               = "db1"
                    NoInitialization       = $true
                    AddSecondary           = $true
                    Force                  = $true
                }

                $result = Invoke-DbaDbLogShipping @splatLogShipping

                $result.Result | Should -Be "Success"
                Should -Invoke New-DbaLogShippingSecondaryPrimary -ModuleName dbatools -Times 1 -Exactly -ParameterFilter {
                    $BackupSourceDirectory -eq "https://storage.blob.core.windows.net/logshipping/db1" -and
                    $BackupDestinationDirectory -eq "https://storage.blob.core.windows.net/logshipping/db1"
                }
                Should -Invoke New-DbaLogShippingPrimaryDatabase -ModuleName dbatools -Times 0 -Exactly
            }

            It "continues with later databases when one association already exists" {
                $script:mockSourceServer.Databases += [PSCustomObject]@{
                    Name          = "db2"
                    RecoveryModel = "Full"
                }
                $script:mockDestinationServer.Databases += [PSCustomObject]@{
                    Name   = "db2"
                    Status = "Restoring"
                }
                $script:associationExists = $true
                $script:associationServerName = "dest.contoso"
                $script:associationDatabaseName = "db1"
                $script:stopMessages = @()
                # A Pester mock cannot propagate Stop-Function's dynamic continue into the caller's foreach loop.
                # Returning here keeps the loop running so this test can verify that db2 receives fresh result state.
                Mock Stop-Function -ModuleName dbatools {
                    param($Message)
                    $script:stopMessages += $Message
                }

                $splatLogShipping = @{
                    SourceSqlInstance      = "source"
                    DestinationSqlInstance = "dest"
                    Database               = "db1", "db2"
                    CopyDestinationFolder  = "C:\copy"
                    NoInitialization       = $true
                    IgnoreFileChecks       = $true
                    AddSecondary           = $true
                    Force                  = $true
                }

                $result = Invoke-DbaDbLogShipping @splatLogShipping

                ($result | Where-Object PrimaryDatabase -eq "db2").Result | Should -Be "Success"
                $script:stopMessages | Should -Contain "Secondary database db1 on dest is already associated with primary database db1"
                Should -Invoke New-DbaLogShippingPrimarySecondary -ModuleName dbatools -Times 1 -Exactly -ParameterFilter {
                    $PrimaryDatabase -eq "db2"
                }
            }
        }

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
