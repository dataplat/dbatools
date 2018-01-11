$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    $dbname = "dbatoolsci_clonetest"
    $clonedb = "dbatoolsci_clonetest_CLONE"
    $clonedb2 = "dbatoolsci_clonetest_CLONE2"
    Context "Command functions as expected" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $server.Query("CREATE DATABASE $dbname")
        }

        AfterAll {
            Get-DbaDatabase -SqlInstance $server -Database $dbname, $clonedb, $clonedb2 | Remove-DbaDatabase -Confirm:$false
        }

        It "warns if SQL instance version is not supported" {
            $results = Invoke-DbaDatabaseClone -SqlInstance $script:instance1 -Database $dbname -CloneDatabase $clonedb -WarningAction SilentlyContinue -WarningVariable versionwarn
            $versionwarn = $versionwarn | Out-String
            $versionwarn -match "required"
        }

        It "warns if destination database already exists" {
            $results = Invoke-DbaDatabaseClone -SqlInstance $script:instance2 -Database $dbname -CloneDatabase tempdb -WarningAction SilentlyContinue -WarningVariable dbwarn
            $dbwarn = $dbwarn | Out-String
            $dbwarn -match "exists"
        }

        It "warns if a system db is specified to clone" {
            $results = Invoke-DbaDatabaseClone -SqlInstance $script:instance2 -Database master -CloneDatabase $clonedb -WarningAction SilentlyContinue -WarningVariable systemwarn
            $systemwarn = $systemwarn | Out-String
            $systemwarn -match "user database"
        }

        $results = Invoke-DbaDatabaseClone -SqlInstance $script:instance2 -Database $dbname -CloneDatabase $clonedb -WarningAction SilentlyContinue

        It "returns 1 result" {
            ($results).Count -eq 1
        }

        foreach ($result in $results) {
            It "returns a rich database object with the correct name" {
                $result.Name -in $clonedb, $clonedb2
            }
        }
    }
}