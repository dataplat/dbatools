$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Spid', 'ExcludeSpid', 'Database', 'Login', 'Hostname', 'Program', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
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