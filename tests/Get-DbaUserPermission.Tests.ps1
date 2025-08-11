#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaUserPermission",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
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
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command returns proper info" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $dbName = "dbatoolsci_UserPermission"
            $sql = @"
create user alice without login;
create user bob without login;
create role userrole AUTHORIZATION dbo;
exec sp_addrolemember 'userrole','alice';
exec sp_addrolemember 'userrole','bob';
"@

            $db = New-DbaDatabase -SqlInstance $TestConfig.instance1 -Name $dbName
            $db.ExecuteNonQuery($sql)

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
            $results = Get-DbaUserPermission -SqlInstance $TestConfig.instance1 -Database $dbName
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbName -Confirm:$false
        }

        It "returns results" {
            $results.Status.Count -gt 0 | Should -Be $true
        }

        foreach ($result in $results) {
            It "returns only $dbName or server results" {
                $result.Object | Should -BeIn $dbName, "SERVER"
            }
            if ($result.Object -eq $dbName -and $result.RoleSecurableClass -eq "DATABASE") {
                It "returns correct securable" {
                    $result.Securable | Should -Be $dbName
                }
            }
        }
    }

    Context "Command do not return error when database as different collation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $dbName = "dbatoolsci_UserPermissionDiffCollation"
            $dbCollation = "Latin1_General_CI_AI"

            $null = New-DbaDatabase -SqlInstance $TestConfig.instance1 -Name $dbName -Collation $dbCollation

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
            $results = Get-DbaUserPermission -SqlInstance $TestConfig.instance1 -Database $dbName -WarningVariable warnvar 3> $null
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbName -Confirm:$false
        }

        It "Should not warn about collation conflict" {
            $warnvar | Should -Be $null
        }

        It "returns results" {
            $results.Status.Count -gt 0 | Should -Be $true
        }
    }
}
