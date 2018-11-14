$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 1
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaMsdtc).Parameters.Keys
        $knownParameters = 'ComputerName'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==" | Measure-Object ).Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/sqlcollaborative/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>
Describe "Get-DbaMsdtc Integration Test" -Tag "IntegrationTests" {
    Context "Command actually works" {
        $results = Get-DbaMsdtc -ComputerName $env:COMPUTERNAME

        It "returns results" {
            $results.DTCServiceName | Should Not Be $null
        }
    }
}