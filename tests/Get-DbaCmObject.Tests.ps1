$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-ChildItem function:\Get-DbaCmObject).Parameters.Keys
        $knownParameters = 'ClassName', 'Query', 'ComputerName', 'Credential', 'Namespace', 'DoNotUse', 'Force', 'SilentlyContinue', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $knownParameters.Count
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "returns proper information" {
        It "returns a bias that's an int" {
            (Get-DbaCmObject -ClassName Win32_TimeZone).Bias -is [int]
        }
    }
}