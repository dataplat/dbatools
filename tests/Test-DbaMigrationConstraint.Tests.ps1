param($ModuleName = 'dbatools')

Describe "Test-DbaMigrationConstraint" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $db1 = "dbatoolsci_testMigrationConstraint"
        $db2 = "dbatoolsci_testMigrationConstraint_2"
        Invoke-DbaQuery -SqlInstance $env:instance1 -Query "CREATE DATABASE $db1"
        Invoke-DbaQuery -SqlInstance $env:instance1 -Query "CREATE DATABASE $db2"
        $needed = Get-DbaDatabase -SqlInstance $env:instance1 -Database $db1, $db2
        $setupright = $true
        if ($needed.Count -ne 2) {
            $setupright = $false
        }
    }

    AfterAll {
        if (-not $appveyor) {
            Remove-DbaDatabase -Confirm:$false -SqlInstance $env:instance1 -Database $db1, $db2 -ErrorAction SilentlyContinue
        }
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaMigrationConstraint
        }
        It "Should have Source parameter" {
            $CommandUnderTest | Should -HaveParameter Source -Type DbaInstanceParameter
        }
        It "Should have SourceSqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SourceSqlCredential -Type PSCredential
        }
        It "Should have Destination parameter" {
            $CommandUnderTest | Should -HaveParameter Destination -Type DbaInstanceParameter
        }
        It "Should have DestinationSqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential -Type PSCredential
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[]
        }
        It "Should have ExcludeDatabase parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[]
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Validate multiple databases" {
        BeforeAll {
            $results = Test-DbaMigrationConstraint -Source $env:instance1 -Destination $env:instance2
        }
        It 'Both databases are migratable' {
            foreach ($result in $results) {
                $result.IsMigratable | Should -Be $true
            }
        }
    }

    Context "Validate single database" {
        It 'Database is migratable' {
            $result = Test-DbaMigrationConstraint -Source $env:instance1 -Destination $env:instance2 -Database $db1
            $result.IsMigratable | Should -Be $true
        }
    }
}
