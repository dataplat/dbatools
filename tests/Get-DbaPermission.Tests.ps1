param($ModuleName = 'dbatools')

Describe "Get-DbaPermission Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPermission
        }
        It "has the required parameter: <_>" -ForEach $params {
            $params = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "IncludeServerLevel",
                "ExcludeSystemObjects",
                "EnableException"
            )
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}

Describe "Get-DbaPermission Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $server = $global:instance1
        $random = Get-Random
        $password = 'MyV3ry$ecur3P@ssw0rd'
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
    }

    AfterAll {
        $removedDb = Remove-DbaDatabase -SqlInstance $server -Database $dbName -Confirm:$false
        $removedDBO = Remove-DbaLogin -SqlInstance $server -Login $loginNameDBO -Confirm:$false
        $removedDBOwner = Remove-DbaLogin -SqlInstance $server -Login $loginNameDBOwner -Confirm:$false
        $removedUser1 = Remove-DbaLogin -SqlInstance $server -Login $loginNameUser1 -Confirm:$false
        $removedUser2 = Remove-DbaLogin -SqlInstance $server -Login $loginNameUser2 -Confirm:$false
    }

    Context "Parameters work" {
        It "Returns server level permissions with -IncludeServerLevel" {
            $results = Get-DbaPermission -SqlInstance $server -IncludeServerLevel
            $results.Where({ $_.Database -eq '' }).Count | Should -BeGreaterThan 0
        }
        It "Returns no server level permissions without -IncludeServerLevel" {
            $results = Get-DbaPermission -SqlInstance $server
            $results.Where({ $_.Database -eq '' }).Count | Should -Be 0
        }
        It "Returns no system object permissions with -ExcludeSystemObjects" {
            $results = Get-DbaPermission -SqlInstance $server -ExcludeSystemObjects
            $results.Where({ $_.securable -like 'sys.*' }).Count | Should -Be 0
        }
        It "Returns system object permissions without -ExcludeSystemObjects" {
            $results = Get-DbaPermission -SqlInstance $server
            $results.Where({ $_.securable -like 'sys.*' }).Count | Should -BeGreaterThan 0
        }
        It "DB object level permissions for a user are returned correctly" {
            $results = Get-DbaPermission -SqlInstance $server -Database $dbName -ExcludeSystemObjects | Where-Object { $_.Grantee -eq $loginNameUser1 -and $_.SecurableType -ne "SCHEMA" }
            $results.Count | Should -Be 4
            $results.Where({ $_.Securable -eq "dbo.$tableName1" -and $_.PermState -eq 'DENY' -and $_.PermissionName -in ('DELETE', 'INSERT', 'UPDATE') }).Count | Should -Be 3
            $results.Where({ $_.Securable -eq "dbo.$tableName1" -and $_.PermState -eq 'GRANT' -and $_.PermissionName -eq 'SELECT' }).Count | Should -Be 1
        }
    }

    # See https://github.com/dataplat/dbatools/issues/6744
    Context "Ensure implicit permissions are included in the result set" {
        It "The dbo user and db_owner users are returned in the result set with the CONTROL permission" {
            $results = Get-DbaPermission -SqlInstance $server -Database $dbName -ExcludeSystemObjects | Where-Object { $_.Grantee -in ($loginNameDBO, $loginNameDBOwner) }
            $results.Count | Should -Be 2

            $results.Where({ ($_.Grantee -eq $loginNameDBO -and $_.GranteeType -eq "DATABASE OWNER (dbo user)" -and $_.PermissionName -eq "CONTROL") -or ($_.Grantee -eq $loginNameDBOwner -and $_.GranteeType -eq "DATABASE OWNER (db_owner role)" -and $_.PermissionName -eq "CONTROL") }).Count | Should -Be 2
        }

        It "DB schema level permissions are returned correctly" {
            $results = Get-DbaPermission -SqlInstance $server -Database $dbName -ExcludeSystemObjects | Where-Object { $_.Grantee -in ($loginNameUser1, $loginNameUser2) -and $_.SecurableType -eq "SCHEMA" }
            $results.Where({ $_.Securable -eq "$schemaNameForTable2" -and $_.PermissionName -eq "CONTROL" }).Count | Should -Be 2
            $results.Where({ $_.Securable -eq "$schemaNameForTable2" -and $_.PermissionName -eq "CONTROL" -and $_.Grantee -eq $loginNameUser1 -and $_.GranteeType -eq "SCHEMA OWNER" }).Count | Should -Be 1
            $results.Where({ $_.Securable -eq "$schemaNameForTable2" -and $_.PermissionName -eq "CONTROL" -and $_.Grantee -eq $loginNameUser2 -and $_.GranteeType -eq "SQL_USER" }).Count | Should -Be 1
        }
    }
}
