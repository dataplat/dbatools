$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Spid', 'ExcludeSpid', 'Database', 'Login', 'Hostname', 'Program', 'InputObject', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
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