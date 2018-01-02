$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Connects to multiple instances" {
        $results = Set-DbaMaxMemory -SqlInstance $script:instance1, $script:instance2 -MaxMB 1024
        foreach ($result in $results) {
            It 'Returns 1024 MB for each instance' {
                $result.CurrentMaxValue | Should Be 1024
            }
        }
    }
}