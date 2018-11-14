$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 5
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaLastGoodCheckDb).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
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