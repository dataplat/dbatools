$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'IncludeSystemDBs', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $dbname = "dbatoolsci_test_$(get-random)"
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $null = $server.Query("Create Database [$dbname]")
    }
    AfterAll {
        Remove-DbaDatabase -SqlInstance $script:instance2 -Database $dbname -Confirm:$false
    }
    #Skipping these tests as internals of Get-DbaDbSpace seems to be unreliable in CI
    Context "Gets DbSpace" {
        $results = Get-DbaDbSpace -SqlInstance $script:instance2 | Where-Object {$_.Database -eq "$dbname"}
        It -skip "Gets results" {
            $results | Should Not Be $null
        }
        foreach ($row in $results) {
            It -skip "Should retreive space for $dbname" {
                $row.Database | Should Be $dbname
            }
            It -skip "Should have a physical path for $dbname" {
                $row.physicalname | Should Not Be $null
            }
        }
    }
    #Skipping these tests as internals of Get-DbaDbSpace seems to be unreliable in CI
    Context "Gets DbSpace when using -Database" {
        $results = Get-DbaDbSpace -SqlInstance $script:instance2 -Database $dbname
        It -skip "Gets results" {
            $results | Should Not Be $null
        }
        Foreach ($row in $results) {
            It -skip "Should retreive space for $dbname" {
                $row.Database | Should Be $dbname
            }
            It -skip "Should have a physical path for $dbname" {
                $row.physicalname | Should Not Be $null
            }
        }
    }
    Context "Gets no DbSpace for specific database when using -ExcludeDatabase" {
        $results = Get-DbaDbSpace -SqlInstance $script:instance2 -ExcludeDatabase $dbname
        It "Gets no results" {
            $results.database | Should Not Contain $dbname
        }
    }
}