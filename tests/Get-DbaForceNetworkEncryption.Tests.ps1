$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 3
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaForceNetworkEncryption).Parameters.Keys
        $knownParameters = 'SqlInstance', 'Credential', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

if (-not $env:appveyor) {
    Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
        $results = Get-DbaForceNetworkEncryption $script:instance1 -EnableException

        It "returns true or false" {
            $results.ForceEncryption -ne $null
        }
    }
}