$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "connection is properly made" {
        $server = Connect-DbaInstance -SqlInstance $script:instance1 -ApplicationIntent ReadOnly

        It "returns the proper name" {
            $server.Name -eq $script:instance1 | Should Be $true
        }

        It "returns more than one database" {
            $server.Databases.Name.Count -gt 0 | Should Be $true
        }

        It "returns the connection with ApplicationIntent of ReadOnly" {
            $server.ConnectionContext.ConnectionString -match "ApplicationIntent=ReadOnly" | Should Be $true
        }
    }
}