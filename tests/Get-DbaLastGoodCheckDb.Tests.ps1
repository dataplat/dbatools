$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance1 -Database master
        $server.Query("DBCC CHECKDB")
    }
    
    $results = Get-DbaLastGoodCheckDb -SqlInstance $script:instance1 -Database master
    It "LastGoodCheckDb is a valid date" {
        $results.LastGoodCheckDb -ne $null
        $results.LastGoodCheckDb -is [datetime]
    }
    
    $results = Get-DbaLastGoodCheckDb -SqlInstance $script:instance1
    It "returns more than 3 results" {
        ($results).Count -gt 3
    }
}