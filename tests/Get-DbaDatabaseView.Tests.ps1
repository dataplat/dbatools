$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        $paramCount = 6
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaDatabaseView).Parameters.Keys
        $knownParameters = 'SqlInstance','SqlCredential','Database','ExcludeDatabase','ExcludeSystemView','EnableException'
        it "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        it "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $viewName = ("dbatoolsci_{0}" -f $(Get-Random))
        $server.Query("CREATE VIEW $viewName AS (SELECT 1 as col1)", 'tempdb')
    }
    AfterAll {
        $null = $server.Query("DROP VIEW $viewName", 'tempdb')
    }

    Context "Command actually works" {
        $results = Get-DbaDatabaseView -SqlInstance $script:instance2 -Database tempdb | Select-Object Name, IsSystemObject
        It "Should get test view: $viewName" {
            ($results | Where-Object Name -eq $viewName).Name | Should Be $true
        }
        It "Should include system views" {
            $results.IsSystemObject | Should Contain $true
        }
    }

    Context "Exclusions work correctly" {
        It "Should contain no views from master database" {
            $results = Get-DbaDatabaseView -SqlInstance $script:instance2 -ExcludeDatabase master
            $results.Database | Should Not Contain 'master'
        }
        It "Should exclude system views" {
            $results = Get-DbaDatabaseView -SqlInstance $script:instance2 -ExcludeSystemView | Select-Object Name, IsSystemObject
             $results.IsSystemObject | Should Not Contain $true
        }
    }
}
