#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaPermission",
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
                "IncludeServerLevel",
                "ExcludeSystemObjects",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = $TestConfig.instance1
        $random = Get-Random
        $password = "MyV3ry$ecur3P@ssw0rd"
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force

        # setup for implicit 'control' permission at the db level (dbo user and db_owner role assignment)
        $loginNameDBO = "dbo_$random"
        $loginNameDBOwner = "db_owner_$random"
        $loginDBO = New-DbaLogin -SqlInstance $server -Login $loginNameDBO -Password $securePassword -Confirm:$false
        $loginDBOwner = New-DbaLogin -SqlInstance $server -Login $loginNameDBOwner -Password $securePassword -Confirm:$false
        $dbName = "dbatoolsci_DB_$random"
        $testDb = New-DbaDatabase -SqlInstance $server -Owner $loginNameDBO -Name $dbName -Confirm:$false
        $newUserDBOwner = New-DbaDbUser -SqlInstance $server -Database $dbName -Login $loginNameDBOwner -Confirm:$false
        $roleMember = Add-DbaDbRoleMember -SqlInstance $server -Database $dbName -Role db_owner -User $loginNameDBOwner -Confirm:$false

        # setup for basic table-level explicit permissions
        $loginNameUser1 = "dbatoolsci_user1_$random"
        $loginUser1 = New-DbaLogin -SqlInstance $server -Login $loginNameUser1 -Password $securePassword -Confirm:$false
        $newUser1 = New-DbaDbUser -SqlInstance $server -Database $dbName -Login $loginNameUser1 -Confirm:$false

        $tableName1 = "dbatoolsci_table1_$random"
        $tableSpec1 = @{
            Name     = "Table1ID"
            Type     = "INT"
            Nullable = $true
        }

        $table1 = New-DbaDbTable -SqlInstance $server -Database $dbName -Name $tableName1 -ColumnMap $tableSpec1
        $null = Invoke-DbaQuery -SqlInstance $server -Database $dbName -Query "
                                    GRANT SELECT ON OBJECT::$tableName1 TO $loginNameUser1;
                                    DENY UPDATE, INSERT, DELETE ON OBJECT::$tableName1 TO $loginNameUser1;
                                   "
        # setup for the schema 'control' implicit permission check
        $loginNameUser2 = "dbatoolsci_user2_$random"
        $loginUser2 = New-DbaLogin -SqlInstance $server -Login $loginNameUser2 -Password $securePassword -Confirm:$false
        $newUser2 = New-DbaDbUser -SqlInstance $server -Database $dbName -Login $loginNameUser2 -Confirm:$false

        $schemaNameForTable2 = "dbatoolsci_schema_$random"
        $tableName2 = "dbatoolsci_table2_$random"
        $tableSpec2 = @{
            Name     = "Table2ID"
            Type     = "INT"
            Nullable = $true
        }

        $null = Invoke-DbaQuery -SqlInstance $server -Database $dbName -Query "CREATE SCHEMA $schemaNameForTable2 AUTHORIZATION $loginNameUser1"
        $null = Invoke-DbaQuery -SqlInstance $server -Database $dbName -Query "GRANT CONTROL ON Schema::$schemaNameForTable2 TO $loginNameUser2"

        $table2 = New-DbaDbTable -SqlInstance $server -Database $dbName -Name $tableName2 -Schema $schemaNameForTable2 -ColumnMap $tableSpec2

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $removedDb = Remove-DbaDatabase -SqlInstance $server -Database $dbName -Confirm:$false -ErrorAction SilentlyContinue
        $removedDBO = Remove-DbaLogin -SqlInstance $server -Login $loginNameDBO -Confirm:$false -ErrorAction SilentlyContinue
        $removedDBOwner = Remove-DbaLogin -SqlInstance $server -Login $loginNameDBOwner -Confirm:$false -ErrorAction SilentlyContinue
        $removedUser1 = Remove-DbaLogin -SqlInstance $server -Login $loginNameUser1 -Confirm:$false -ErrorAction SilentlyContinue
        $removedUser2 = Remove-DbaLogin -SqlInstance $server -Login $loginNameUser2 -Confirm:$false -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "parameters work" {
        It "returns server level permissions with -IncludeServerLevel" {
            $results = Get-DbaPermission -SqlInstance $server -IncludeServerLevel
            $results | Where-Object Database -eq "" | Should -Not -BeNullOrEmpty
        }
        It "returns no server level permissions without -IncludeServerLevel" {
            $results = Get-DbaPermission -SqlInstance $server
            $results | Where-Object Database -eq "" | Should -HaveCount 0
        }
        It "returns no system object permissions with -ExcludeSystemObjects" {
            $results = Get-DbaPermission -SqlInstance $server -ExcludeSystemObjects
            $results | Where-Object securable -like "sys.*" | Should -HaveCount 0
        }
        It "returns system object permissions without -ExcludeSystemObjects" {
            $results = Get-DbaPermission -SqlInstance $server
            $results | Where-Object securable -like "sys.*" | Should -Not -BeNullOrEmpty
        }
        It "db object level permissions for a user are returned correctly" {
            $results = Get-DbaPermission -SqlInstance $server -Database $dbName -ExcludeSystemObjects | Where-Object { $PSItem.Grantee -eq $loginNameUser1 -and $PSItem.SecurableType -ne "SCHEMA" }
            $results | Should -HaveCount 4
            $results | Where-Object { $PSItem.Securable -eq "dbo.$tableName1" -and $PSItem.PermState -eq "DENY" -and $PSItem.PermissionName -in ("DELETE", "INSERT", "UPDATE") } | Should -HaveCount 3
            $results | Where-Object { $PSItem.Securable -eq "dbo.$tableName1" -and $PSItem.PermState -eq "GRANT" -and $PSItem.PermissionName -eq "SELECT" } | Should -HaveCount 1
        }
    }

    # See https://github.com/dataplat/dbatools/issues/6744
    Context "Ensure implicit permissions are included in the result set" {
        It "the dbo user and db_owner users are returned in the result set with the CONTROL permission" {
            $results = Get-DbaPermission -SqlInstance $server -Database $dbName -ExcludeSystemObjects | Where-Object Grantee -in ($loginNameDBO, $loginNameDBOwner)
            $results | Should -HaveCount 2

            $results | Where-Object { ($PSItem.Grantee -eq $loginNameDBO -and $PSItem.GranteeType -eq "DATABASE OWNER (dbo user)" -and $PSItem.PermissionName -eq "CONTROL") -or ($PSItem.Grantee -eq $loginNameDBOwner -and $PSItem.GranteeType -eq "DATABASE OWNER (db_owner role)" -and $PSItem.PermissionName -eq "CONTROL") } | Should -HaveCount 2
        }

        It "db schema level permissions are returned correctly" {
            $results = Get-DbaPermission -SqlInstance $server -Database $dbName -ExcludeSystemObjects | Where-Object { $PSItem.Grantee -in ($loginNameUser1, $loginNameUser2) -and $PSItem.SecurableType -eq "SCHEMA" }
            $results | Where-Object { $PSItem.Securable -eq "$schemaNameForTable2" -and $PSItem.PermissionName -eq "CONTROL" } | Should -HaveCount 2
            $results | Where-Object { $PSItem.Securable -eq "$schemaNameForTable2" -and $PSItem.PermissionName -eq "CONTROL" -and $PSItem.Grantee -eq $loginNameUser1 -and $PSItem.GranteeType -eq "SCHEMA OWNER" } | Should -HaveCount 1
            $results | Where-Object { $PSItem.Securable -eq "$schemaNameForTable2" -and $PSItem.PermissionName -eq "CONTROL" -and $PSItem.Grantee -eq $loginNameUser2 -and $PSItem.GranteeType -eq "SQL_USER" } | Should -HaveCount 1

        }
    }
}