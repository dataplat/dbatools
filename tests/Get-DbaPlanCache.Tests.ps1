$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    Context "returns proper information" {
        xIt "returns correct datatypes" {
            $results = Get-DbaPlanCache -SqlInstance $script:instance1 | Clear-DbaPlanCache -Threshold 1024
            $results.UseCount -is [int] | Should -Be $true
            $results.UseCount -is [dbasize] | Should -Be $true
        }
    }
}