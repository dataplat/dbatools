$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    $results = Test-DbaCmConnection -Type Wmi
    It "returns some valid info" {
        $results.ComputerName -eq $env:COMPUTERNAME
        $results.Available -is [bool]
    }
}