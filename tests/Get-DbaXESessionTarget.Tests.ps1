$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Verifying command output" {

        It "returns only the system_health session" {
            $results = Get-DbaXESessionTarget -SqlInstance $script:instance2 -Target package0.event_file
            foreach ($result in $results) {
                $result.Name -eq 'package0.event_file' | Should Be $true
            }
        }

        It "supports the pipeline" {
            $results = Get-DbaXESession -SqlInstance $script:instance2 -Session system_health | Get-DbaXESessionTarget -Target package0.event_file
            $results.Count -gt 0 | Should Be $true
        }
    }
}