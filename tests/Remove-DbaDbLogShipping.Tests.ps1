param($ModuleName = 'dbatools')
Describe "Remove-DbaDbLogShipping Unit Tests" -Tag "UnitTests" {
    BeforeAll {
        # Import module or set up environment if needed
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDbLogShipping
        }
        It "Should have PrimarySqlInstance as a non-mandatory DbaInstanceParameter" {
            $CommandUnderTest | Should -HaveParameter PrimarySqlInstance -Type DbaInstanceParameter -Not -Mandatory
        }
        It "Should have SecondarySqlInstance as a non-mandatory DbaInstanceParameter" {
            $CommandUnderTest | Should -HaveParameter SecondarySqlInstance -Type DbaInstanceParameter -Not -Mandatory
        }
        It "Should have PrimarySqlCredential as a non-mandatory PSCredential" {
            $CommandUnderTest | Should -HaveParameter PrimarySqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have SecondarySqlCredential as a non-mandatory PSCredential" {
            $CommandUnderTest | Should -HaveParameter SecondarySqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database as a non-mandatory Object[]" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[] -Not -Mandatory
        }
        It "Should have RemoveSecondaryDatabase as a non-mandatory SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter RemoveSecondaryDatabase -Type SwitchParameter -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
        }
    }
}

Describe "Remove-DbaDbLogShipping Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        # Run setup code to get script variables within scope of the discovery phase
        . (Join-Path $PSScriptRoot 'constants.ps1')
    }

    BeforeAll {
        $dbname = "dbatoolsci_logshipping"
        $localPath = 'C:\temp\logshipping'
        $networkPath = '\\localhost\c$\temp\logshipping'

        $primaryServer = Connect-DbaInstance -SqlInstance $script:instance2
        $secondaryserver = Connect-DbaInstance -SqlInstance $script:instance2

        # Create the database
        if ($primaryServer.Databases.Name -notcontains $dbname) {
            $query = "CREATE DATABASE [$dbname]"
            Invoke-DbaQuery -SqlInstance $script:instance2 -Database master -Query $query
        }

        if (-not (Test-Path -Path $localPath)) {
            $null = New-Item -Path $localPath -ItemType Directory
        }
    }

    Context "Remove database from log shipping without removing secondary database" {
        BeforeAll {
            $params = @{
                SourceSqlInstance       = $script:instance2
                DestinationSqlInstance  = $script:instance2
                Database                = $dbname
                BackupNetworkPath       = $networkPath
                BackupLocalPath         = $localPath
                GenerateFullBackup      = $true
                CompressBackup          = $true
                SecondaryDatabaseSuffix = "_LS"
                Force                   = $true
            }

            # Run the log shipping
            Invoke-DbaDbLogShipping @params
        }

        It "Should have the database information" {
            $query = "SELECT pd.primary_database AS PrimaryDatabase,
                    ps.secondary_server AS SecondaryServer,
                    ps.secondary_database AS SecondaryDatabase
                FROM msdb.dbo.log_shipping_primary_secondaries AS ps
                    INNER JOIN msdb.dbo.log_shipping_primary_databases AS pd
                        ON [pd].[primary_id] = [ps].[primary_id]
                WHERE pd.[primary_database] = '$dbname';"

            $results = Invoke-DbaQuery -SqlInstance $script:instance2 -Database master -Query $query
            $results.PrimaryDatabase | Should -Be $dbname
        }

        It "Should remove log shipping without removing secondary database" {
            $params = @{
                PrimarySqlInstance   = $script:instance2
                SecondarySqlInstance = $script:instance2
                Database             = $dbname
            }

            Remove-DbaDbLogShipping @params

            $primaryServer.Databases.Refresh()
            $secondaryserver = Connect-DbaInstance -SqlInstance $script:instance2

            "$($dbname)_LS" | Should -BeIn $secondaryserver.Databases.Name

            $query = "SELECT pd.primary_database AS PrimaryDatabase,
                    ps.secondary_server AS SecondaryServer,
                    ps.secondary_database AS SecondaryDatabase
                FROM msdb.dbo.log_shipping_primary_secondaries AS ps
                    INNER JOIN msdb.dbo.log_shipping_primary_databases AS pd
                        ON [pd].[primary_id] = [ps].[primary_id]
                WHERE pd.[primary_database] = '$dbname';"

            $results = Invoke-DbaQuery -SqlInstance $script:instance2 -Database master -Query $query
            $results.PrimaryDatabase | Should -BeNullOrEmpty
        }
    }

    Context "Remove database from log shipping with removing secondary database" {
        BeforeAll {
            $params = @{
                SourceSqlInstance       = $script:instance2
                DestinationSqlInstance  = $script:instance2
                Database                = $dbname
                BackupNetworkPath       = $networkPath
                BackupLocalPath         = $localPath
                GenerateFullBackup      = $true
                CompressBackup          = $true
                SecondaryDatabaseSuffix = "_LS"
                Force                   = $true
            }

            Invoke-DbaDbLogShipping @params
        }

        It "Should have the database information" {
            $query = "SELECT pd.primary_database AS PrimaryDatabase,
                    ps.secondary_server AS SecondaryServer,
                    ps.secondary_database AS SecondaryDatabase
                FROM msdb.dbo.log_shipping_primary_secondaries AS ps
                    INNER JOIN msdb.dbo.log_shipping_primary_databases AS pd
                        ON [pd].[primary_id] = [ps].[primary_id]
                WHERE pd.[primary_database] = '$dbname';"

            $results = Invoke-DbaQuery -SqlInstance $script:instance2 -Database master -Query $query
            $results.PrimaryDatabase | Should -Be $dbname
        }

        It "Should remove log shipping and secondary database" {
            $params = @{
                PrimarySqlInstance      = $script:instance2
                SecondarySqlInstance    = $script:instance2
                Database                = $dbname
                RemoveSecondaryDatabase = $true
            }

            Remove-DbaDbLogShipping @params

            $primaryServer.Databases.Refresh()
            $secondaryserver = Connect-DbaInstance -SqlInstance $script:instance2

            "$($dbname)_LS" | Should -Not -BeIn $secondaryserver.Databases.Name

            $query = "SELECT pd.primary_database AS PrimaryDatabase,
                    ps.secondary_server AS SecondaryServer,
                    ps.secondary_database AS SecondaryDatabase
                FROM msdb.dbo.log_shipping_primary_secondaries AS ps
                    INNER JOIN msdb.dbo.log_shipping_primary_databases AS pd
                        ON [pd].[primary_id] = [ps].[primary_id]
                WHERE pd.[primary_database] = '$dbname';"

            $results = Invoke-DbaQuery -SqlInstance $script:instance2 -Database master -Query $query
            $results.PrimaryDatabase | Should -BeNullOrEmpty
        }
    }

    AfterAll {
        # Cleanup
        if ($primaryServer.Databases[$dbname]) {
            $primaryServer.Databases[$dbname].Drop()
        }
        if ($secondaryserver.Databases["$($dbname)_LS"]) {
            $secondaryserver.Databases["$($dbname)_LS"].Drop()
        }
        if (Test-Path -Path $localPath) {
            Remove-Item -Path $localPath -Recurse -Force
        }
    }
}
