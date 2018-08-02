$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $null = Get-DbaProcess -SqlInstance $script:instance1, $script:instance2 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
        $db1 = "dbatoolsci_safely"
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $server.Query("CREATE DATABASE $db1")
        $server = Connect-DbaInstance -SqlInstance $script:instance1
        $server.Query("CREATE DATABASE $db1")
    }
    AfterAll {
        $null = Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance1, $script:instance2 -Database $db1
        $null = Remove-DbaAgentJob -Confirm:$false -SqlInstance $script:instance2 -Job 'Rationalised Database Restore Script for dbatoolsci_safely'
    }
    Context "Command actually works" {
        $results = Remove-DbaDatabaseSafely -SqlInstance $script:instance2 -Database $db1 -BackupFolder C:\temp -NoDbccCheckDb
        It "Should have database name of $db1" {
            foreach ($result in $results) {
                $result.DatabaseName | Should -Be $db1
            }
        }
        $results = Remove-DbaDatabaseSafely -SqlInstance $script:instance1 -Database $db1 -BackupFolder C:\temp -NoDbccCheckDb -WarningAction SilentlyContinue -WarningVariable warn
        It "should warn and quit" {
            $results | Should -Be $null
            $warn -match 'Failure starting SQL Agent' | Should -Be $true
        }
        
        # Add back after rewrite, this should work
        It -Skip "Should restore to another server" {
            Remove-DbaAgentJob -Confirm:$false -SqlInstance $script:instance2 -Job 'Rationalised Database Restore Script for dbatoolsci_safely'
            $results = Remove-DbaDatabaseSafely -SqlInstance $script:instance1 -Database $db1 -BackupFolder C:\temp -NoDbccCheckDb -Destination $script:instance2
            foreach ($result in $results) {
                $result.SqlInstance | Should -Be $script:instance1
                $result.TestingInstance | Should -Be $script:instance2
            }
        }
    }
}