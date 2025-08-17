$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Parameter validation" {
        It "Should only contain our specific parameters" {
            [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
            [object[]]$knownParameters = 'LocalFile', 'EnableException'
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Unit Test" -Tags Unittest {
    Context "not much" {
        It "calls the internal function" {
            function Get-DbaBuildReferenceIndexOnline { }
            Mock Get-DbaBuildReferenceIndexOnline -MockWith { } -ModuleName dbatools
            { Update-DbaBuildReference -EnableException -ErrorAction Stop } | Should -Not -Throw
        }
        It "errors out when cannot download" {
            Mock Get-DbaBuildReferenceIndexOnline -MockWith { throw "cannot download" } -ModuleName dbatools
            { Update-DbaBuildReference -EnableException -ErrorAction Stop } | Should -Throw
        }
    }
}