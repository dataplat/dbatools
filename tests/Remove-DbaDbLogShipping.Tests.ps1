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

        $primaryServer = Connect-DbaInstance -SqlInstance $script:instance2
        $secondaryerver = Connect-DbaInstance -SqlInstance $script:instance
    }

    Context "Remove database from log shipping with remove secondary database"{
        $params = @{
            SourceSqlInstance = $script:instance2
            DestinationSqlInstance = $script:instance
            Database = $dbname
            BackupNetworkPath = 'C:\temp'
            BackupLocalPath = "C:\temp\logshipping\backup"
            GenerateFullBackup = $true
            CompressBackup = $true
            SecondaryDatabaseSuffix = "_LS"
            Force = $true
        }

        $results = Invoke-DbaDbLogShipping @params

        It "Database should be set up for log shipping" {
            $results.Status -eq 'Success' | Should Be $true
        }

        $params = @{
            PrimarySqlInstance = $script:instance2
            SecondarySqlInstance = $script:instance
            Database = $dbname
        }

        Remove-DbaDbLogShipping @params

        $primaryServer.Databases.refresh()
        $secondaryerver.Databases.refresh()

        It "Should still have the primary database"{
            $dbname | Should -BeIn $primaryServer.Databases.Name
        }

        It "Should still longer have the secondary database" {
            $dbname | Should -BeIn $secondaryerver.Databases.Name
        }
    }

    Context "Remove database from log shipping with remove secondary database"{
        $params = @{
            SourceSqlInstance = $script:instance2
            DestinationSqlInstance = $script:instance
            Database = $dbname
            BackupNetworkPath = 'C:\temp'
            BackupLocalPath = "C:\temp\logshipping\backup"
            GenerateFullBackup = $true
            CompressBackup = $true
            SecondaryDatabaseSuffix = "_LS"
            Force = $true
        }

        $results = Invoke-DbaDbLogShipping @params

        It "Database should be set up for log shipping" {
            $results.Status -eq 'Success' | Should Be $true
        }

        $params = @{
            PrimarySqlInstance = $script:instance2
            SecondarySqlInstance = $script:instance
            Database = $dbname
        }

        Remove-DbaDbLogShipping @params

        $primaryServer.Databases.refresh()
        $secondaryerver.Databases.refresh()

        It "Should still have the primary database"{
            $dbname | Should -BeIn $primaryServer.Databases.Name
        }

        It "Should no longer have the secondary database" {
            $dbname | Should -Not -BeIn $secondaryerver.Databases.Name
        }
    }

}