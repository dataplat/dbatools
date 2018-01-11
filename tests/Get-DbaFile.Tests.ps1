$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Returns some files" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $random = Get-Random
            $db = "dbatoolsci_getfile$random"
            $server.Query("CREATE DATABASE $db")
        }
        AfterAll {
            $null = Get-DbaDatabase -SqlInstance $script:instance2 -Database $db | Remove-DbaDatabase -Confirm:$false
        }

        $results = Get-DbaFile -SqlInstance $script:instance2
        It "Should find the new database file" {
            ($results.Filename -match 'dbatoolsci').Count -gt 0 | Should Be $true
        }

        $results = Get-DbaFile -SqlInstance $script:instance2 -Path (Get-DbaDefaultPath -SqlInstance $script:instance2).Log
        It "Should find the new database log file" {
            ($results.Filename -like '*dbatoolsci*ldf').Count -gt 0 | Should Be $true
        }

        $masterpath = $server.MasterDBPath
        $results = Get-DbaFile -SqlInstance $script:instance2 -Path $masterpath
        It "Should find the master database file" {
            $results.Filename -match 'master.mdf' | Should Be $true
        }
    }
}
