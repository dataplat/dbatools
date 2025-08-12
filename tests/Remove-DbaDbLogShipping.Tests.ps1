#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbLogShipping",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
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
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # This is a placeholder until we decide on sql2016/sql2017
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $dbname = "dbatoolsci_logshipping"

        $localPath = "C:\temp\logshipping"
        $networkPath = "\\localhost\c$\temp\logshipping"

        $primaryServer = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $secondaryserver = Connect-DbaInstance -SqlInstance $TestConfig.instance2

        # Create the database
        if ($primaryServer.Databases.Name -notcontains $dbname) {
            $query = "CREATE DATABASE [$dbname]"
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

        # Clean up the database and files
        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname -ErrorAction SilentlyContinue
        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database "$($dbname)_LS" -ErrorAction SilentlyContinue
        Remove-Item -Path $localPath -Recurse -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Remove database from log shipping without removing secondary database" {
        BeforeAll {
            $splatLogShipping = @{
                SourceSqlInstance       = $TestConfig.instance2
                DestinationSqlInstance  = $TestConfig.instance2
                Database                = $dbname
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
                WHERE pd.[primary_database] = '$dbname';"

            $results = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database master -Query $query

            $results.PrimaryDatabase | Should -Be $dbname
        }

        It "Should remove log shipping but keep the secondary database" {
            # Remove the log shipping
            $splatRemoveLogShipping = @{
                PrimarySqlInstance   = $TestConfig.instance2
                SecondarySqlInstance = $TestConfig.instance2
                Database             = $dbname
            }

            Remove-DbaDbLogShipping @splatRemoveLogShipping

            $primaryServer.Databases.Refresh()
            $secondaryserver = Connect-DbaInstance -SqlInstance $TestConfig.instance2

            "$($dbname)_LS" | Should -BeIn $secondaryserver.Databases.Name
        }

        It "Should no longer have log shipping information" {
            $query = "SELECT pd.primary_database AS PrimaryDatabase,
                    ps.secondary_server AS SecondaryServer,
                    ps.secondary_database AS SecondaryDatabase
                FROM msdb.dbo.log_shipping_primary_secondaries AS ps
                    INNER JOIN msdb.dbo.log_shipping_primary_databases AS pd
                        ON [pd].[primary_id] = [ps].[primary_id]
                WHERE pd.[primary_database] = '$dbname';"

            $results = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database master -Query $query

            $results.PrimaryDatabase | Should -Be $null
        }
    }

    Context "Remove database from log shipping with removing secondary database" {
        BeforeAll {
            $splatLogShipping = @{
                SourceSqlInstance       = $TestConfig.instance2
                DestinationSqlInstance  = $TestConfig.instance2
                Database                = $dbname
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
                WHERE pd.[primary_database] = '$dbname';"

            $results = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database master -Query $query

            $results.PrimaryDatabase | Should -Be $dbname
        }

        It "Should remove log shipping and the secondary database" {
            # Remove the log shipping
            $splatRemoveLogShippingSecondary = @{
                PrimarySqlInstance      = $TestConfig.instance2
                SecondarySqlInstance    = $TestConfig.instance2
                Database                = $dbname
                RemoveSecondaryDatabase = $true
            }

            Remove-DbaDbLogShipping @splatRemoveLogShippingSecondary

            $primaryServer.Databases.Refresh()
            $secondaryserver = Connect-DbaInstance -SqlInstance $TestConfig.instance2

            "$($dbname)_LS" | Should -Not -BeIn $secondaryserver.Databases.Name
        }

        It "Should no longer have log shipping information" {
            $query = "SELECT pd.primary_database AS PrimaryDatabase,
                    ps.secondary_server AS SecondaryServer,
                    ps.secondary_database AS SecondaryDatabase
                FROM msdb.dbo.log_shipping_primary_secondaries AS ps
                    INNER JOIN msdb.dbo.log_shipping_primary_databases AS pd
                        ON [pd].[primary_id] = [ps].[primary_id]
                WHERE pd.[primary_database] = '$dbname';"

            $results = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database master -Query $query

            $results.PrimaryDatabase | Should -Be $null
        }
    }
}