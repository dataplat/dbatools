$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 3
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaPowerPlan).Parameters.Keys
        $knownParameters = 'ComputerName', 'Credential', 'EnableException'
        It "Should contain our specific parameters" {
            ((Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "Command actually works" {
        It "Should return result for the server" {
            $results = Get-DbaPowerPlan -ComputerName $script:instance2
            $results | Should Not Be Null
        }
    }
}