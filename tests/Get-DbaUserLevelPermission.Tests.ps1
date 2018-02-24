$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

$instance1 = '.'
$instance2 = '.'

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Command returns proper info" {
        $results = Get-DbaUserLevelPermission -SqlInstance $script:instance1 -Database tempdb

        It "returns results" {
            $results.Count -gt 0 | Should Be $true
        }

        foreach ($result in $results) {
            It "returns only tempdb or server results" {
                $result.Object -in 'tempdb', 'SERVER' | Should Be $true
            }
        }

        It "Excludes databases" {
            $results = Get-DbaUserLevelPermission -SqlInstance $script:instance1 -ExcludeDatabase 'master'
    
            ($results | Where-Object { $_.Type -like 'DB*' }).Object.Contains('master') | Should Be $false
        }

        It "Excludes system databases" {
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $random = Get-Random
            $db = "dbatoolsci_userlevelperm$random"
            $server.Query("CREATE DATABASE $db")        
    
            $results = Get-DbaUserLevelPermission -SqlInstance $script:instance1 -ExcludeSystemDatabase
    
            ($results | Where-Object { $_.Type -like 'DB*' }).Object.Contains('master') | Should Be $false
    
            $null = Get-DbaDatabase -SqlInstance $server -Database $db | Remove-DbaDatabase -Confirm:$false
        }            

        It "Errors if a database is inaccessible" {
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $random = Get-Random
            $db = "dbatoolsci_userlevelperm$random"
            $server.Query("CREATE DATABASE $db")
    
            $null = Set-DbaDatabaseState -SqlInstance $script:instance2 -Database $db -Offline
    
            { Get-DbaUserLevelPermission -SqlInstance $script:instance2 -Database $db -EnableException } | Should Throw "The database [$db] is not accessible"
    
            $null = Get-DbaDatabase -SqlInstance $server -Database $db | Remove-DbaDatabase -Confirm:$false        
        }

        It "Includes public when using IncludePublicGuest parameter" {
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $random = Get-Random
            $db = "dbatoolsci_userlevelperm$random"
            $server.Query("CREATE DATABASE $db")
            $server.Databases[$db].ExecuteNonQuery("GRANT CONNECT TO public")
    
            $null = Set-DbaDatabaseState -SqlInstance $script:instance2 -Database $db -Offline -EnableException
    
            $results = Get-DbaUserLevelPermission -SqlInstance $script:instance2 -Database $db -IncludePublicGuest
            $results | Where-Object { $_.Grantee -eq 'public' -and $_.Permission -eq 'Connect' } | Should -Not -BeNullOrEmpty
    
            $null = Get-DbaDatabase -SqlInstance $server -Database $db | Remove-DbaDatabase -Confirm:$false                
        }

        It "Includes system objects when using IncludeSystemObjects parameter" {

        }
    }
}