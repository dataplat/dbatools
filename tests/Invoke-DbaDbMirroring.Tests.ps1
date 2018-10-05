$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        Get-DbaProcess -SqlInstance $script:instance2 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $db1 = "dbatoolsci_mirroring"
        
        Remove-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db1 -Confirm:$false
        Get-DbaDatabase -SqlInstance $script:instance2 -Database $db1 | Remove-DbaDatabase -Confirm:$false
        $server.Query("CREATE DATABASE $db1")
        Backup-DbaDatabase -SqlInstance $script:instance2 -Database $db1 -BackupDirectory C:\temp -Type Full | Restore-DbaDatabase -SqlInstance $script:instance3 -NoRecovery
        Backup-DbaDatabase -SqlInstance $script:instance2 -Database $db1 -BackupDirectory C:\temp -Type Log | Restore-DbaDatabase -SqlInstance $script:instance3 -NoRecovery -Continue
    }
    AfterAll {
        Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2, $script:instance3 -Database $db1 -ErrorAction SilentlyContinue
    }
    
    It "returns success" {
        $results = Invoke-DbaDbMirroring -Primary $script:instance2 -Mirror $script:instance3 -Database $db1 -Confirm:$false
        $results.Status | Should -Be 'Success'
    }
}