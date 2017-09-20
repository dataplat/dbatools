$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1","")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Test Check Default Trace" {

        $results = Get-DbaTraceFile -SqlInstance $script:instance1 
        It "Should find at least one trace file" {
            ($results).Count -gt 0 | Should Be $true
        }
    }
}