$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Verifying command works" {
        It "returns a result with the right computername and name is not null" {
            $results = Get-DbaPfDataCollectorCounter | Select-Object -First 1
            $results.ComputerName | Should Be $env:COMPUTERNAME
            $results.Name | Should Not Be $null
        }
    }
}