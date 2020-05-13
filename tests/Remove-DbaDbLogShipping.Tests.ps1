$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'PrimarySqlInstance', 'SecondarySqlInstance', 'PrimarySqlCredential', 'SecondarySqlCredential', 'Database', 'RemoveSecondaryDatabase', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    # This is a placeholder until we decide on sql2016/sql2017
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

    Context "Remove database from log shipping with remove secondary database" {
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

        # Remove the log shipping
        $params = @{
            PrimarySqlInstance   = $script:instance2
            SecondarySqlInstance = $script:instance2
            Database             = $dbname
        }

        Remove-DbaDbLogShipping @params

        $primaryServer.Databases.Refresh()
        $secondaryserver = Connect-DbaInstance -SqlInstance $script:instance2

        It "Should still have the secondary database" {
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

            $results = Invoke-DbaQuery -SqlInstance $script:instance2 -Database master -Query $query

            $results.PrimaryDatabase | Should -Be $null
        }
    }

    Context "Remove database from log shipping with remove secondary database" {
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

        $results = Invoke-DbaDbLogShipping @params

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

        # Remove the log shipping
        $params = @{
            PrimarySqlInstance      = $script:instance2
            SecondarySqlInstance    = $script:instance2
            Database                = $dbname
            RemoveSecondaryDatabase = $true
        }

        Remove-DbaDbLogShipping @params

        $primaryServer.Databases.Refresh()
        $secondaryserver = Connect-DbaInstance -SqlInstance $script:instance2

        It "Should no longer have the secondary database" {
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

            $results = Invoke-DbaQuery -SqlInstance $script:instance2 -Database master -Query $query

            $results.PrimaryDatabase | Should -Be $null
        }
    }

}