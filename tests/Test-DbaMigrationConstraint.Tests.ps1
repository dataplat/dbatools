$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance1
        $db1 = "dbatoolsci_testMigrationConstraint"
        $db2 = "dbatoolsci_testMigrationConstraint_2"
        $server.Query("CREATE DATABASE $db1")
        $server.Query("CREATE DATABASE $db2")
        $needed = Get-DbaDatabase -SqlInstance $script:instance1 -Database $db1, $db2
        $setupright = $true
        if ($needed.Count -ne 2) {
            $setupright = $false
            it "has failed setup" {
                Set-TestInconclusive -message "Setup failed"
            }
        }
    }
    AfterAll {
        if (-not $appveyor) {
            Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance1 -Database $db1
            Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance1 -Database $db2
        }
    }
    Context "Validate multiple databases" {
        It 'Both databases are migratable' {
            $results = Test-DbaMigrationConstraint -Source $script:instance1 -Destination $script:instance2
            foreach ($result in $results) {
                $result.IsMigratable | Should Be $true
            }
        }
    }
    Context "Validate single database" {
        It 'Databases are migratable' {
            (Test-DbaMigrationConstraint -Source $script:instance1 -Destination $script:instance2 -Database $db1).IsMigratable | Should Be $true
        }
    }
}
