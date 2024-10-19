param($ModuleName = 'dbatools')

Describe "Test-DbaMigrationConstraint" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $db1 = "dbatoolsci_testMigrationConstraint"
        $db2 = "dbatoolsci_testMigrationConstraint_2"
        Invoke-DbaQuery -SqlInstance $global:instance1 -Query "CREATE DATABASE $db1"
        Invoke-DbaQuery -SqlInstance $global:instance1 -Query "CREATE DATABASE $db2"
        $needed = Get-DbaDatabase -SqlInstance $global:instance1 -Database $db1, $db2
        $setupright = $true
        if ($needed.Count -ne 2) {
            $setupright = $false
        }
    }

    AfterAll {
        if (-not $appveyor) {
            Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance1 -Database $db1, $db2 -ErrorAction SilentlyContinue
        }
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaMigrationConstraint
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Database",
                "ExcludeDatabase",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Validate multiple databases" {
        BeforeAll {
            $results = Test-DbaMigrationConstraint -Source $global:instance1 -Destination $global:instance2
        }
        It 'Both databases are migratable' {
            foreach ($result in $results) {
                $result.IsMigratable | Should -Be $true
            }
        }
    }

    Context "Validate single database" {
        It 'Database is migratable' {
            $result = Test-DbaMigrationConstraint -Source $global:instance1 -Destination $global:instance2 -Database $db1
            $result.IsMigratable | Should -Be $true
        }
    }
}
