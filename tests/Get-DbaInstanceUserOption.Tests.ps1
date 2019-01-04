$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-ChildItem function:\Get-DbaInstanceUserOption).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $knownParameters.Count
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

    Context "Gets UserOptions for the Instance" {
        $results = Get-DbaInstanceUserOption -SqlInstance $script:instance2 | Where-Object {$_.name -eq 'AnsiNullDefaultOff'}
        It "Gets results" {
            $results | Should Not Be $null
        }
        It "Should return AnsiNullDefaultOff UserOption" {
            $results.Name | Should Be 'AnsiNullDefaultOff'
        }
        It "Should be set to false" {
            $results.Value | Should Be $false
        }
    }
}