param($ModuleName = 'dbatools')

Describe "Get-DbaUserPermission Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaUserPermission
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[]
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[]
        }
        It "Should have ExcludeSystemDatabase as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSystemDatabase -Type Switch
        }
        It "Should have IncludePublicGuest as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludePublicGuest -Type Switch
        }
        It "Should have IncludeSystemObjects as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeSystemObjects -Type Switch
        }
        It "Should have ExcludeSecurables as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSecurables -Type Switch
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }
}

Describe "Get-DbaUserPermission Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $dbName = "dbatoolsci_UserPermission"
        $sql = @'
create user alice without login;
create user bob without login;
create role userrole AUTHORIZATION dbo;
exec sp_addrolemember 'userrole','alice';
exec sp_addrolemember 'userrole','bob';
'@

        $db = New-DbaDatabase -SqlInstance $env:instance1 -Name $dbName
        $db.ExecuteNonQuery($sql)
    }

    AfterAll {
        Remove-DbaDatabase -SqlInstance $env:instance1 -Database $dbName -Confirm:$false
    }

    Context "Command returns proper info" {
        BeforeAll {
            $results = Get-DbaUserPermission -SqlInstance $env:instance1 -Database $dbName
        }

        It "returns results" {
            $results.Count | Should -BeGreaterThan 0
        }

        It "returns only $dbName or server results" {
            $results | ForEach-Object {
                $_.Object | Should -BeIn $dbName, 'SERVER'
            }
        }

        It "returns correct securable for database objects" {
            $results | Where-Object { $_.Object -eq $dbName -and $_.RoleSecurableClass -eq 'DATABASE' } | ForEach-Object {
                $_.Securable | Should -Be $dbName
            }
        }
    }

    Context "Command does not return error when database has different collation" {
        BeforeAll {
            $dbNameDiffCollation = "dbatoolsci_UserPermissionDiffCollation"
            $dbCollation = "Latin1_General_CI_AI"

            New-DbaDatabase -SqlInstance $env:instance1 -Name $dbNameDiffCollation -Collation $dbCollation
        }

        AfterAll {
            Remove-DbaDatabase -SqlInstance $env:instance1 -Database $dbNameDiffCollation -Confirm:$false
        }

        It "Should not warn about collation conflict" {
            $warnVar = $null
            $results = Get-DbaUserPermission -SqlInstance $env:instance1 -Database $dbNameDiffCollation -WarningVariable warnVar 3> $null
            $warnVar | Should -BeNullOrEmpty
        }

        It "returns results" {
            $results = Get-DbaUserPermission -SqlInstance $env:instance1 -Database $dbNameDiffCollation
            $results.Count | Should -BeGreaterThan 0
        }
    }
}
