#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaUserPermission",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
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
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip:$env:appveyor {
    # Skip IntegrationTests on AppVeyor because they fail for unknown reasons.

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

            $db = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbName
            $db.ExecuteNonQuery($sql)

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
            $results = Get-DbaUserPermission -SqlInstance $TestConfig.InstanceSingle -Database $dbName
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "returns results" {
            $results.Status.Count -gt 0 | Should -Be $true
        }

        It "returns only $dbName or server results" {
            foreach ($result in $results) {
                $result.Object | Should -BeIn $dbName, "SERVER"
            }
        }

        It "returns correct securable" {
            foreach ($result in $results) {
                if ($result.Object -eq $dbName -and $result.RoleSecurableClass -eq "DATABASE") {
                    $result.Securable | Should -Be $dbName
                }
            }
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $dbName = "dbatoolsci_OutputValidation"
            $db = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
            $result = Get-DbaUserPermission -SqlInstance $TestConfig.InstanceSingle -Database $dbName -EnableException
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbName
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns PSCustomObject" {
            $result[0].PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Object",
                "Type",
                "Member",
                "RoleSecurableClass",
                "SchemaOwner",
                "Securable",
                "GranteeType",
                "Grantee",
                "Permission",
                "State",
                "Grantor",
                "GrantorType",
                "SourceView"
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in output"
            }
        }
    }

    Context "Command do not return error when database as different collation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $dbName = "dbatoolsci_UserPermissionDiffCollation"
            $dbCollation = "Latin1_General_CI_AI"

            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbName -Collation $dbCollation

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
            $results = Get-DbaUserPermission -SqlInstance $TestConfig.InstanceSingle -Database $dbName -WarningVariable warnvar 3> $null
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should not warn about collation conflict" {
            $warnvar | Should -Be $null
        }

        It "returns results" {
            $results.Status.Count -gt 0 | Should -Be $true
        }
    }
}