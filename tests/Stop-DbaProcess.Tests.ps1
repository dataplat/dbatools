$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    Context "command works as expected" {
        $fakeapp = Connect-DbaInstance -SqlInstance $script:instance1 -ClientName 'dbatoolsci test app'
        $results = Stop-DbaProcess -SqlInstance $script:instance1 -Program 'dbatoolsci test app'
        It "kills only this specific process" {
            $results.Program.Count | Should -Be 1
            $results.Program | Should -Be 'dbatoolsci test app'
            $results.Status | Should -Be 'Killed'
        }
        $fakeapp = Connect-DbaInstance -SqlInstance $script:instance1 -ClientName 'dbatoolsci test app'
        $results = Get-DbaProcess -SqlInstance $script:instance1 -Program 'dbatoolsci test app' | Stop-DbaProcess
        It "supports piping" {
            $results.Program.Count | Should -Be 1
            $results.Program | Should -Be 'dbatoolsci test app'
            $results.Status | Should -Be 'Killed'
        }
    }
}