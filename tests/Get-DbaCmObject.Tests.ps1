$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    Context "returns proper information" {
        It "returns a bias that's an int" {
            (Get-DbaCmObject -ClassName Win32_TimeZone).Bias -is [int]
        }
    }
}