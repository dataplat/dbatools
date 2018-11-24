$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 6
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaDbSpace).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'IncludeSystemDBs', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $dbname = "dbatoolsci_test_$(get-random)"
        $server = Connect-DbaInstance -SqlInstance $script:instance3
        $server.Query("Create Database [$dbname]")
    }
    AfterAll {
        $server.Query("DROP Database [$dbname]")
    }

    Context "Gets DbSpace" {
        $results = Get-DbaDbSpace -SqlInstance $script:instance3 | Where-Object {$_.Database -eq "$dbname"}
        It "Gets results" {
            $results | Should Not Be $null
        }
        foreach ($row in $results) {
            It "Should retreive space for $dbname" {
                $row.Database | Should Be $dbname
            }
            It "Should have a physical path for $dbname" {
                $row.physicalname | Should Not Be $null
            }
        }
    }
    Context "Gets DbSpace when using -database" {
        $results = Get-DbaDbSpace -SqlInstance $script:instance3 -Database $dbname
        It "Gets results" {
            $results | Should Not Be $null
        }
        Foreach ($row in $results) {
            It "Should retreive space for $dbname" {
                $row.Database | Should Be $dbname
            }
            It "Should have a physical path for $dbname" {
                $row.physicalname | Should Not Be $null
            }
        }
    }
    Context "Gets no DbSpace for specific database when using -ExcludeDatabase" {
        $results = Get-DbaDbSpace -SqlInstance $script:instance3 -ExcludeDatabase $dbname
        It "Gets no results" {
            $results.database | Should Not Contain $dbname
        }
    }
    Context "Gets DbSpace for system databases when using -IncludeSystemDBs" {
        $results = Get-DbaDbSpace -SqlInstance $script:instance3 -IncludeSystemDBs
        It "Gets results" {
            $results.database | Should Contain 'Master'
        }
    }
}