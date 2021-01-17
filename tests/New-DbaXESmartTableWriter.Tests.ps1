$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Table', 'AutoCreateTargetTable', 'UploadIntervalSeconds', 'Event', 'OutputColumn', 'Filter', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}
Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Creates a smart object" {
        It "returns the object with all of the correct properties" {
            $results = New-DbaXESmartReplay -SqlInstance $script:instance2 -Database planning
            $results.ServerName | Should -Be $script:instance2
            $results.DatabaseName | Should -be 'planning'
            $results.Password | Should -Be $null
            $results.DelaySeconds | Should -Be 0
        }
    }
}