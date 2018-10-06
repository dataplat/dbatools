$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $db = Get-DbaDatabase -SqlInstance $script:instance2 -Database msdb
        if (($db.Tables['dbm_monitor_data'].Name)) {
            $putback = $true
        }
        else {
            $null = Add-DbaDbMirrorMonitor -SqlInstance $script:instance2 -WarningAction SilentlyContinue
        }
    }
    AfterAll {
        if ($putback) {
            # add it back
            $results = Add-DbaDbMirrorMonitor -SqlInstance $script:instance2 -WarningAction SilentlyContinue
        }
    }
    
    It "removes the mirror monitor" {
        $results = Remove-DbaDbMirrorMonitor -SqlInstance $script:instance2 -WarningAction SilentlyContinue
        $results.MonitorStatus | Should -Be 'Removed'
    }
}