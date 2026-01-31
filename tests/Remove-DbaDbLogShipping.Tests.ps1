#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbLogShipping",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "PrimarySqlInstance",
                "SecondarySqlInstance",
                "PrimarySqlCredential",
                "SecondarySqlCredential",
                "Database",
                "RemoveSecondaryDatabase",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

<# Describe $CommandName -Tag IntegrationTests {
    # This is a placeholder until we decide on sql2016/sql2017
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $dbName = "dbatoolsci_logshipping"
        $localPath = "C:\temp\logshipping"
        $networkPath = "\\localhost\c$\temp\logshipping"

        $primaryServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $secondaryServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        # Create the database
        if ($primaryServer.Databases.Name -notcontains $dbName) {
            $query = "CREATE DATABASE [$dbName]"
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database master -Query $query
        }

        if (-not (Test-Path -Path $localPath)) {
            $null = New-Item -Path $localPath -ItemType Directory
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup
        Remove-Item -Path $localPath -Recurse -ErrorAction SilentlyContinue
        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbName -ErrorAction SilentlyContinue
        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database "$($dbName)_LS" -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Remove database from log shipping without removing secondary database" {
        BeforeAll {
            $splatLogShipping = @{
                SourceSqlInstance       = $TestConfig.InstanceSingle
                DestinationSqlInstance  = $TestConfig.InstanceSingle
                Database                = $dbName
                BackupNetworkPath       = $networkPath
                BackupLocalPath         = $localPath
                GenerateFullBackup      = $true
                CompressBackup          = $true
                SecondaryDatabaseSuffix = "_LS"
                Force                   = $true
            }

            # Run the log shipping
            Invoke-DbaDbLogShipping @splatLogShipping
        }

        It "Should have the database information" {
            $query = "SELECT pd.primary_database AS PrimaryDatabase,
                    ps.secondary_server AS SecondaryServer,
                    ps.secondary_database AS SecondaryDatabase
                FROM msdb.dbo.log_shipping_primary_secondaries AS ps
                    INNER JOIN msdb.dbo.log_shipping_primary_databases AS pd
                        ON [pd].[primary_id] = [ps].[primary_id]
                WHERE pd.[primary_database] = '$dbName';"

            $results = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database master -Query $query

            $results.PrimaryDatabase | Should -Be $dbName
        }

        It "Should remove log shipping but keep secondary database" {
            # Remove the log shipping
            $splatRemove = @{
                PrimarySqlInstance   = $TestConfig.InstanceSingle
                SecondarySqlInstance = $TestConfig.InstanceSingle
                Database             = $dbName
            }

            Remove-DbaDbLogShipping @splatRemove

            $primaryServer.Databases.Refresh()
            $secondaryServerRefreshed = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

            "$($dbName)_LS" | Should -BeIn $secondaryServerRefreshed.Databases.Name
        }

        It "Should no longer have log shipping information" {
            $query = "SELECT pd.primary_database AS PrimaryDatabase,
                    ps.secondary_server AS SecondaryServer,
                    ps.secondary_database AS SecondaryDatabase
                FROM msdb.dbo.log_shipping_primary_secondaries AS ps
                    INNER JOIN msdb.dbo.log_shipping_primary_databases AS pd
                        ON [pd].[primary_id] = [ps].[primary_id]
                WHERE pd.[primary_database] = '$dbName';"

            $results = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database master -Query $query

            $results.PrimaryDatabase | Should -Be $null
        }
    }

    Context "Remove database from log shipping with secondary database removal" {
        BeforeAll {
            $splatLogShipping = @{
                SourceSqlInstance       = $TestConfig.InstanceSingle
                DestinationSqlInstance  = $TestConfig.InstanceSingle
                Database                = $dbName
                BackupNetworkPath       = $networkPath
                BackupLocalPath         = $localPath
                GenerateFullBackup      = $true
                CompressBackup          = $true
                SecondaryDatabaseSuffix = "_LS"
                Force                   = $true
            }

            $results = Invoke-DbaDbLogShipping @splatLogShipping
        }

        It "Should have the database information" {
            $query = "SELECT pd.primary_database AS PrimaryDatabase,
                    ps.secondary_server AS SecondaryServer,
                    ps.secondary_database AS SecondaryDatabase
                FROM msdb.dbo.log_shipping_primary_secondaries AS ps
                    INNER JOIN msdb.dbo.log_shipping_primary_databases AS pd
                        ON [pd].[primary_id] = [ps].[primary_id]
                WHERE pd.[primary_database] = '$dbName';"

            $results = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database master -Query $query

            $results.PrimaryDatabase | Should -Be $dbName
        }

        It "Should remove log shipping and secondary database" {
            # Remove the log shipping
            $splatRemove = @{
                PrimarySqlInstance      = $TestConfig.InstanceSingle
                SecondarySqlInstance    = $TestConfig.InstanceSingle
                Database                = $dbName
                RemoveSecondaryDatabase = $true
            }

            Remove-DbaDbLogShipping @splatRemove

            $primaryServer.Databases.Refresh()
            $secondaryServerRefreshed = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

            "$($dbName)_LS" | Should -Not -BeIn $secondaryServerRefreshed.Databases.Name
        }

        It "Should no longer have log shipping information" {
            $query = "SELECT pd.primary_database AS PrimaryDatabase,
                    ps.secondary_server AS SecondaryServer,
                    ps.secondary_database AS SecondaryDatabase
                FROM msdb.dbo.log_shipping_primary_secondaries AS ps
                    INNER JOIN msdb.dbo.log_shipping_primary_databases AS pd
                        ON [pd].[primary_id] = [ps].[primary_id]
                WHERE pd.[primary_database] = '$dbName';"

            $results = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database master -Query $query

            $results.PrimaryDatabase | Should -Be $null
        }
    }

    Context "Remove incomplete log shipping configuration (primary only, no secondary)" {
        BeforeAll {
            # Simulate an incomplete log shipping setup by inserting only into primary tables
            # This mimics the Azure Managed Instance scenario where secondary setup fails
            $primaryId = [guid]::NewGuid()

            $splatInsertPrimary = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = "msdb"
                Query           = "INSERT INTO dbo.log_shipping_primary_databases
                    (primary_id, primary_database, backup_directory, backup_share, backup_retention_period,
                     backup_job_id, monitor_server, monitor_server_security_mode, backup_threshold, threshold_alert,
                     threshold_alert_enabled, last_backup_file, last_backup_date, last_backup_date_utc, history_retention_period)
                    VALUES ('$primaryId', '$dbName', 'C:\Backup', '\\localhost\Backup', 4320,
                     '00000000-0000-0000-0000-000000000000', '', 1, 60, 14420, 0, NULL, NULL, NULL, 5760)"
                EnableException = $true
            }
            Invoke-DbaQuery @splatInsertPrimary
        }

        AfterAll {
            # Clean up the manually inserted primary record
            $splatCleanup = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = "msdb"
                Query           = "DELETE FROM dbo.log_shipping_primary_databases WHERE primary_database = '$dbName'"
                EnableException = $true
            }
            Invoke-DbaQuery @splatCleanup
        }

        It "Should detect incomplete log shipping configuration" {
            # Verify that we have primary but no secondary
            $queryPrimary = "SELECT primary_database FROM msdb.dbo.log_shipping_primary_databases WHERE primary_database = '$dbName'"
            $querySecondary = "SELECT ps.secondary_database
                FROM msdb.dbo.log_shipping_primary_secondaries AS ps
                    INNER JOIN msdb.dbo.log_shipping_primary_databases AS pd
                        ON pd.primary_id = ps.primary_id
                WHERE pd.primary_database = '$dbName'"

            $primaryResult = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database msdb -Query $queryPrimary
            $secondaryResult = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database msdb -Query $querySecondary

            $primaryResult.primary_database | Should -Be $dbName
            $secondaryResult | Should -BeNullOrEmpty
        }

        It "Should remove incomplete log shipping configuration without error" {
            $splatRemove = @{
                PrimarySqlInstance = $TestConfig.InstanceSingle
                Database           = $dbName
            }

            # This should not throw and should successfully remove the primary-only configuration
            { Remove-DbaDbLogShipping @splatRemove -EnableException } | Should -Not -Throw
        }

        It "Should have removed the primary database configuration" {
            $queryPrimary = "SELECT primary_database FROM msdb.dbo.log_shipping_primary_databases WHERE primary_database = '$dbName'"
            $result = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database msdb -Query $queryPrimary

            $result | Should -BeNullOrEmpty
        }
    }
} #>