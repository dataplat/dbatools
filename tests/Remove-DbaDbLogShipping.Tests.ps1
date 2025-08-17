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

        $primaryServer = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $secondaryServer = Connect-DbaInstance -SqlInstance $TestConfig.instance2

        # Create the database
        if ($primaryServer.Databases.Name -notcontains $dbName) {
            $query = "CREATE DATABASE [$dbName]"
            Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database master -Query $query
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
        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbName -ErrorAction SilentlyContinue
        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database "$($dbName)_LS" -ErrorAction SilentlyContinue
    }

    Context "Remove database from log shipping without removing secondary database" {
        BeforeAll {
            $splatLogShipping = @{
                SourceSqlInstance       = $TestConfig.instance2
                DestinationSqlInstance  = $TestConfig.instance2
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

            $results = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database master -Query $query

            $results.PrimaryDatabase | Should -Be $dbName
        }

        It "Should remove log shipping but keep secondary database" {
            # Remove the log shipping
            $splatRemove = @{
                PrimarySqlInstance   = $TestConfig.instance2
                SecondarySqlInstance = $TestConfig.instance2
                Database             = $dbName
            }

            Remove-DbaDbLogShipping @splatRemove

            $primaryServer.Databases.Refresh()
            $secondaryServerRefreshed = Connect-DbaInstance -SqlInstance $TestConfig.instance2

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

            $results = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database master -Query $query

            $results.PrimaryDatabase | Should -Be $null
        }
    }

    Context "Remove database from log shipping with secondary database removal" {
        BeforeAll {
            $splatLogShipping = @{
                SourceSqlInstance       = $TestConfig.instance2
                DestinationSqlInstance  = $TestConfig.instance2
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

            $results = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database master -Query $query

            $results.PrimaryDatabase | Should -Be $dbName
        }

        It "Should remove log shipping and secondary database" {
            # Remove the log shipping
            $splatRemove = @{
                PrimarySqlInstance      = $TestConfig.instance2
                SecondarySqlInstance    = $TestConfig.instance2
                Database                = $dbName
                RemoveSecondaryDatabase = $true
            }

            Remove-DbaDbLogShipping @splatRemove

            $primaryServer.Databases.Refresh()
            $secondaryServerRefreshed = Connect-DbaInstance -SqlInstance $TestConfig.instance2

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

            $results = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database master -Query $query

            $results.PrimaryDatabase | Should -Be $null
        }
    }
} #>