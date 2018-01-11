$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Recovery model is correctly identified" {
        $results = Get-DbaDbRecoveryModel -SqlInstance $script:instance2 -Database master

        It "returns a single database" {
            $results.Count | Should Be 1
        }

        It "returns the correct recovery model" {
            $results.RecoveryModel -eq 'Simple' | Should Be $true
        }

        $results = Get-DbaDbRecoveryModel -SqlInstance $script:instance2

        It "returns accurate number of results" {
            $results.Count -ge 4 | Should Be $true
        }
    }
    Context "RecoveryModel parameter works" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $dbname = "dbatoolsci_getrecoverymodel"
            Get-DbaDatabase -SqlInstance $server -Database $dbname | Remove-DbaDatabase -Confirm:$false
            $server.Query("CREATE DATABASE $dbname; ALTER DATABASE $dbname SET RECOVERY BULK_LOGGED WITH NO_WAIT;")
        }
        AfterAll {
            Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname | Remove-DbaDatabase -Confirm:$false
        }

        It "gets the newly created database with the correct recovery model" {
            $results = Get-DbaDbRecoveryModel -SqlInstance $script:instance2 -Database $dbname
            $results.RecoveryModel -eq 'BulkLogged' | Should Be $true
        }
        It "honors the RecoveryModel parameter filter" {
            $results = Get-DbaDbRecoveryModel -SqlInstance $script:instance2 -RecoveryModel BulkLogged
            $results.Name -contains $dbname | Should Be $true
        }
    }
}