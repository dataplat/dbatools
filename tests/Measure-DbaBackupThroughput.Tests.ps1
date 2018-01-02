$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Returns output for single database" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $random = Get-Random
            $db = "dbatoolsci_measurethruput$random"
            $server.Query("CREATE DATABASE $db")
            $null = Get-DbaDatabase -SqlInstance $server -Database $db | Backup-DbaDatabase
        }
        AfterAll {
            $null = Get-DbaDatabase -SqlInstance $server -Database $db | Remove-DbaDatabase -Confirm:$false
        }

        $results = Measure-DbaBackupThroughput -SqlInstance $server -Database $db
        It "Should return just one backup" {
            $results.Database.Count -eq 1 | Should Be $true
        }
    }
}
