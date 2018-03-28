$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $results = Restore-DbaDatabase -SqlInstance $script:instance1 -path $script:appveyorlabrepo\sql2008-backups\dbOrphanUsers\FULL\SQL2008_dbOrphanUsers_FULL_20170518_041740.bak
    }
    AfterAll {
        Get-DbaDatabase -SqlInstance $script:instance1 -Database dbOrphanUsers | Remove-DbaDatabase -Confirm:$false
    }
    Context "finds orphaned users in newly restored database" {
        $results = Get-DbaOrphanUser -SqlInstance $script:instance1
        It "finds the orphan user" {
            $results.DatabaseName -contains 'dbOrphanUsers' | Should -Be $true
            $results.User -eq 'UserOrphan' | Should -Be $true
        }
    }
}