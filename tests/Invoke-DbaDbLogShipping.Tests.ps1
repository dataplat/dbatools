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

Describe "$CommandName - Azure Integration" -Tag IntegrationTests {
    if ($env:azurepasswd) {
        Context "Azure blob storage log shipping using SAS token" {
            BeforeAll {
                $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

                $primaryInstance = $TestConfig.instance2
                $secondaryInstance = $TestConfig.instance3
                $dbName = "dbatoolsci_logship_azure_$(Get-Random)"
                $azureUrl = $TestConfig.azureblob

                # Setup: Create SQL Server credentials on both instances
                $primaryServer = Connect-DbaInstance -SqlInstance $primaryInstance
                $secondaryServer = Connect-DbaInstance -SqlInstance $secondaryInstance

                # Create SAS token credential on primary instance
                if (Get-DbaCredential -SqlInstance $primaryInstance -Name "[$azureUrl]") {
                    $sql = "DROP CREDENTIAL [$azureUrl]"
                    $primaryServer.Query($sql)
                }
                $splatCreateCred = @{
                    SqlInstance = $primaryInstance
                    Name        = $azureUrl
                    Identity    = "SHARED ACCESS SIGNATURE"
                    SecurePassword = (ConvertTo-SecureString $env:azurepasswd -AsPlainText -Force)
                }
                $null = New-DbaCredential @splatCreateCred

                # Create SAS token credential on secondary instance
                if (Get-DbaCredential -SqlInstance $secondaryInstance -Name "[$azureUrl]") {
                    $sql = "DROP CREDENTIAL [$azureUrl]"
                    $secondaryServer.Query($sql)
                }
                $splatCreateCred = @{
                    SqlInstance = $secondaryInstance
                    Name        = $azureUrl
                    Identity    = "SHARED ACCESS SIGNATURE"
                    SecurePassword = (ConvertTo-SecureString $env:azurepasswd -AsPlainText -Force)
                }
                $null = New-DbaCredential @splatCreateCred

                # Create test database on primary
                $null = New-DbaDatabase -SqlInstance $primaryInstance -Name $dbName

                $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
            }

            AfterAll {
                $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

                # Cleanup: Remove log shipping configuration
                $splatRemovePrimary = @{
                    SqlInstance = $primaryInstance
                    Database    = $dbName
                    Confirm     = $false
                }
                $null = Remove-DbaDbLogShipping @splatRemovePrimary -WarningAction SilentlyContinue

                $splatRemoveSecondary = @{
                    SqlInstance = $secondaryInstance
                    Database    = $dbName
                    Confirm     = $false
                }
                $null = Remove-DbaDbLogShipping @splatRemoveSecondary -WarningAction SilentlyContinue

                # Drop databases
                $null = Remove-DbaDatabase -SqlInstance $primaryInstance -Database $dbName -Confirm $false
                $null = Remove-DbaDatabase -SqlInstance $secondaryInstance -Database $dbName -Confirm $false

                # Drop credentials
                $null = Remove-DbaCredential -SqlInstance $primaryInstance -Name $azureUrl -Confirm $false
                $null = Remove-DbaCredential -SqlInstance $secondaryInstance -Name $azureUrl -Confirm $false

                $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
            }

            It "sets up log shipping to Azure blob storage using SAS token authentication" {
                $splatLogShipping = @{
                    SourceSqlInstance      = $primaryInstance
                    DestinationSqlInstance = $secondaryInstance
                    Database               = $dbName
                    AzureBaseUrl           = $azureUrl
                    GenerateFullBackup     = $true
                    Force                  = $true
                }
                $results = Invoke-DbaDbLogShipping @splatLogShipping
                $results | Should -Not -BeNullOrEmpty
                $results.Status | Should -Be "Success"
            }

            It "creates the primary database configuration" {
                $splatGetPrimary = @{
                    SqlInstance = $primaryInstance
                    Database    = $dbName
                }
                $primary = Get-DbaDbLogShipping @splatGetPrimary
                $primary | Should -Not -BeNullOrEmpty
                $primary.PrimaryDatabase | Should -Be $dbName
            }

            It "creates the secondary database configuration" {
                $splatGetSecondary = @{
                    SqlInstance = $secondaryInstance
                    Database    = $dbName
                }
                $secondary = Get-DbaDbLogShipping @splatGetSecondary
                $secondary | Should -Not -BeNullOrEmpty
                $secondary.SecondaryDatabase | Should -Be $dbName
            }

            It "creates backup job on primary instance" {
                $splatGetJob = @{
                    SqlInstance = $primaryInstance
                    Job         = "LSBackup_$dbName"
                }
                $job = Get-DbaAgentJob @splatGetJob
                $job | Should -Not -BeNullOrEmpty
                $job.Name | Should -BeLike "*LSBackup*$dbName*"
            }

            It "creates restore job on secondary instance" {
                $splatGetJob = @{
                    SqlInstance = $secondaryInstance
                    Job         = "LSRestore_*$dbName*"
                }
                $job = Get-DbaAgentJob @splatGetJob
                $job | Should -Not -BeNullOrEmpty
                $job.Name | Should -BeLike "*LSRestore*$dbName*"
            }

            It "does not create copy job when using Azure blob storage" {
                $splatGetJob = @{
                    SqlInstance = $secondaryInstance
                    Job         = "LSCopy_*$dbName*"
                }
                $job = Get-DbaAgentJob @splatGetJob
                $job | Should -BeNullOrEmpty
            }
        }

        Context "Azure blob storage log shipping using storage account key" {
            BeforeAll {
                $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

                $primaryInstance = $TestConfig.instance2
                $secondaryInstance = $TestConfig.instance3
                $dbName = "dbatoolsci_logship_azkey_$(Get-Random)"
                $azureUrl = $TestConfig.azureblob
                $credName = "dbatools_ci_logship"

                # Setup: Create SQL Server credentials on both instances using storage account key
                $primaryServer = Connect-DbaInstance -SqlInstance $primaryInstance
                $secondaryServer = Connect-DbaInstance -SqlInstance $secondaryInstance

                # Create storage account key credential on primary instance
                if (Get-DbaCredential -SqlInstance $primaryInstance -Name $credName) {
                    $sql = "DROP CREDENTIAL [$credName]"
                    $primaryServer.Query($sql)
                }
                $splatCreateCred = @{
                    SqlInstance    = $primaryInstance
                    Name           = $credName
                    Identity       = $TestConfig.azureblobaccount
                    SecurePassword = (ConvertTo-SecureString $env:azurelegacypasswd -AsPlainText -Force)
                }
                $null = New-DbaCredential @splatCreateCred

                # Create storage account key credential on secondary instance
                if (Get-DbaCredential -SqlInstance $secondaryInstance -Name $credName) {
                    $sql = "DROP CREDENTIAL [$credName]"
                    $secondaryServer.Query($sql)
                }
                $splatCreateCred = @{
                    SqlInstance    = $secondaryInstance
                    Name           = $credName
                    Identity       = $TestConfig.azureblobaccount
                    SecurePassword = (ConvertTo-SecureString $env:azurelegacypasswd -AsPlainText -Force)
                }
                $null = New-DbaCredential @splatCreateCred

                # Create test database on primary
                $null = New-DbaDatabase -SqlInstance $primaryInstance -Name $dbName

                $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
            }

            AfterAll {
                $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

                # Cleanup: Remove log shipping configuration
                $splatRemovePrimary = @{
                    SqlInstance = $primaryInstance
                    Database    = $dbName
                    Confirm     = $false
                }
                $null = Remove-DbaDbLogShipping @splatRemovePrimary -WarningAction SilentlyContinue

                $splatRemoveSecondary = @{
                    SqlInstance = $secondaryInstance
                    Database    = $dbName
                    Confirm     = $false
                }
                $null = Remove-DbaDbLogShipping @splatRemoveSecondary -WarningAction SilentlyContinue

                # Drop databases
                $null = Remove-DbaDatabase -SqlInstance $primaryInstance -Database $dbName -Confirm $false
                $null = Remove-DbaDatabase -SqlInstance $secondaryInstance -Database $dbName -Confirm $false

                # Drop credentials
                $null = Remove-DbaCredential -SqlInstance $primaryInstance -Name $credName -Confirm $false
                $null = Remove-DbaCredential -SqlInstance $secondaryInstance -Name $credName -Confirm $false

                $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
            }

            It "sets up log shipping to Azure blob storage using storage account key authentication" {
                $splatLogShipping = @{
                    SourceSqlInstance      = $primaryInstance
                    DestinationSqlInstance = $secondaryInstance
                    Database               = $dbName
                    AzureBaseUrl           = $azureUrl
                    AzureCredential        = $credName
                    GenerateFullBackup     = $true
                    Force                  = $true
                }
                $results = Invoke-DbaDbLogShipping @splatLogShipping
                $results | Should -Not -BeNullOrEmpty
                $results.Status | Should -Be "Success"
            }

            It "creates the primary database configuration with explicit credential" {
                $splatGetPrimary = @{
                    SqlInstance = $primaryInstance
                    Database    = $dbName
                }
                $primary = Get-DbaDbLogShipping @splatGetPrimary
                $primary | Should -Not -BeNullOrEmpty
                $primary.PrimaryDatabase | Should -Be $dbName
            }

            It "creates the secondary database configuration with explicit credential" {
                $splatGetSecondary = @{
                    SqlInstance = $secondaryInstance
                    Database    = $dbName
                }
                $secondary = Get-DbaDbLogShipping @splatGetSecondary
                $secondary | Should -Not -BeNullOrEmpty
                $secondary.SecondaryDatabase | Should -Be $dbName
            }
        }
    }
}