$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-ChildItem function:\Get-DbaEndpoint).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Endpoint', 'EnableException', 'Type'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $knownParameters.Count
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