$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    Context "Command actually works" {
        It "should have info for model" {
           $results = Test-DbaDiskSpeed -SqlInstance $script:instance1
           $results.FileName -contains 'modellog'
        }
        It "returns only for master" {
            $results = Test-DbaDiskSpeed -SqlInstance $script:instance1 -Database master
            $results.Count -eq 2
            foreach ($result in $results) {
                $result.Reads -gt 0
            }
        }
    }
}