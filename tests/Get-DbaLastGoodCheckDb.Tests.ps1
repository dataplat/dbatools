$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance','SqlCredential','Database','ExcludeDatabase','EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance1 -Database master
        $server.Query("DBCC CHECKDB")
    }

    $results = Get-DbaLastGoodCheckDb -SqlInstance $script:instance1 -Database master
    It "LastGoodCheckDb is a valid date" {
        $results.LastGoodCheckDb -ne $null
        $results.LastGoodCheckDb -is [datetime]
    }

    $results = Get-DbaLastGoodCheckDb -SqlInstance $script:instance1 -WarningAction SilentlyContinue
    It "returns more than 3 results" {
        ($results).Count -gt 3
    }
}