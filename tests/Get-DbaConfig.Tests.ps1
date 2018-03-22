$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    Context "returns proper information" {
        $results = Get-DbaConfig -FullName sql.connection.timeout
        It "returns a value that is an int" {
            $results.Value -is [int]
        }
    }
}