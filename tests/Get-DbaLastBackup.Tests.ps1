$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $random = Get-Random
        $dbname = "dbatoolsci_getlastbackup$random"
        $server.Query("CREATE DATABASE $dbname")
        $server.Query("ALTER DATABASE $dbname SET RECOVERY FULL WITH NO_WAIT")
    }

    AfterAll {
        $null = Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname | Remove-DbaDatabase -Confirm:$false
    }

    Context "Get null history for database" {
        $results = Get-DbaLastBackup -SqlInstance $script:instance2 -Database $dbname
        It "doesn't have any values for last backups because none exist yet" {
            $results.LastFullBackup | Should Be $null
            $results.LastDiffBackup | Should Be $null
            $results.LastLogBackup | Should Be $null
        }
    }

    $yesterday = (Get-Date).AddDays(-1)
    Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname | Backup-DbaDatabase
    Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname | Backup-DbaDatabase -Type Differential
    Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname | Backup-DbaDatabase -Type Log

    Context "Get last history for single database" {
        $results = Get-DbaLastBackup -SqlInstance $script:instance2 -Database $dbname
        It "returns a date within the proper range" {
            [datetime]$results.LastFullBackup -gt $yesterday | Should Be $true
            [datetime]$results.LastDiffBackup -gt $yesterday | Should Be $true
            [datetime]$results.LastLogBackup -gt $yesterday | Should Be $true
        }
    }

    Context "Get last history for all databases" {
        $results = Get-DbaLastBackup -SqlInstance $script:instance2
        It "returns more than 3 databases" {
            $results.count -gt 3 | Should Be $true
        }
    }
}