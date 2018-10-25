$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $null = Remove-DbaDbMirrorMonitor -SqlInstance $script:instance2 -WarningAction SilentlyContinue
    }
    
    It "adds the mirror monitor" {
        $results = Add-DbaDbMirrorMonitor -SqlInstance $script:instance2 -WarningAction SilentlyContinue
        $results.MonitorStatus | Should -Be 'Added'
    }
}
