$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'Endpoint', 'Type', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    It "gets some endpoints" {
        $results = Get-DbaEndpoint -SqlInstance $script:instance2
        $results.Count | Should -BeGreaterThan 1
        $results.Name | Should -Contain 'TSQL Default TCP'
    }
    It "gets one endpoint" {
        $results = Get-DbaEndpoint -SqlInstance $script:instance2 -Endpoint 'TSQL Default TCP'
        $results.Name | Should -Be 'TSQL Default TCP'
        $results.Count | Should -Be 1
    }
}