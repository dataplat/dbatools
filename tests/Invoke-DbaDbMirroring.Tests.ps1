$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $null = Get-DbaProcess -SqlInstance $script:instance2 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $db1 = "dbatoolsci_mirroring"
        
        Remove-DbaDbMirror -SqlInstance $script:instance2 -Database $db1 -Confirm:$false
        Remove-DbaDatabase -SqlInstance $script:instance2 -Database $db1 -Confirm:$false
        $null = Get-DbaDatabase -SqlInstance $script:instance2 -Database $db1 | Remove-DbaDatabase -Confirm:$false
        $null = $server.Query("CREATE DATABASE $db1")
        #$null = Backup-DbaDatabase -SqlInstance $script:instance2 -Database $db1 -BackupDirectory C:\temp -Type Full | Restore-DbaDatabase -SqlInstance $script:instance3 -NoRecovery -WithReplace | Out-Null
        #$null = Backup-DbaDatabase -SqlInstance $script:instance2 -Database $db1 -BackupDirectory C:\temp -Type Log | Restore-DbaDatabase -SqlInstance $script:instance3 -NoRecovery -WithReplace -Continue | Out-Null
    }
    AfterAll {
        $null = Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2, $script:instance3 -Database $db1 -ErrorAction SilentlyContinue
    }
    
    It "returns success" {
        $results = Invoke-DbaDbMirroring -Primary $script:instance2 -Mirror $script:instance3 -Database $db1 -Confirm:$false -Force -NetworkShare C:\temp
        $results.Status | Should -Be 'Success'
    }
}