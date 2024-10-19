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
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "ExcludeSystemDatabase",
                "IncludePublicGuest",
                "IncludeSystemObjects",
                "ExcludeSecurables",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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

        $db = New-DbaDatabase -SqlInstance $global:instance1 -Name $dbName
        $db.ExecuteNonQuery($sql)
    }

    AfterAll {
        Remove-DbaDatabase -SqlInstance $global:instance1 -Database $dbName -Confirm:$false
    }

    Context "Command returns proper info" {
        BeforeAll {
            $results = Get-DbaUserPermission -SqlInstance $global:instance1 -Database $dbName
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

            New-DbaDatabase -SqlInstance $global:instance1 -Name $dbNameDiffCollation -Collation $dbCollation
        }

        AfterAll {
            Remove-DbaDatabase -SqlInstance $global:instance1 -Database $dbNameDiffCollation -Confirm:$false
        }

        It "Should not warn about collation conflict" {
            $warnVar = $null
            $results = Get-DbaUserPermission -SqlInstance $global:instance1 -Database $dbNameDiffCollation -WarningVariable warnVar 3> $null
            $warnVar | Should -BeNullOrEmpty
        }

        It "returns results" {
            $results = Get-DbaUserPermission -SqlInstance $global:instance1 -Database $dbNameDiffCollation
            $results.Count | Should -BeGreaterThan 0
        }
    }
}
