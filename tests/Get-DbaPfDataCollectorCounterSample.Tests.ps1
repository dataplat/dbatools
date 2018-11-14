$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 11
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaPfDataCollectorCounterSample).Parameters.Keys
        $knownParameters = 'ComputerName', 'Credential', 'CollectorSet', 'Collector', 'Counter', 'Continuous', 'ListSet', 'MaxSamples', 'SampleInterval', 'InputObject', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}
$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Verifying command works" {
        It "returns a result with the right computername and name is not null" {
            $results = Get-DbaPfDataCollectorCounterSample | Select-Object -First 1
            $results.ComputerName | Should Be $env:COMPUTERNAME
            $results.Name | Should Not Be $null
        }
    }
}