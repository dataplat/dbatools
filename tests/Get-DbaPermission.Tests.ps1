$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'IncludeServerLevel', 'ExcludeSystemObjects', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $server = $script:instance1
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

        # debugging errors seen only in AppVeyor
        Write-Message -Level Verbose -Message "Get-DbaPermission: Server=$server, dbName=$dbName, loginDBO=$($loginDBO.Name), loginDBOwner=$($loginDBOwner.Name), loginUser1=$($loginUser1.Name), newUserDBOwner=$($newUserDBOwner.Name), newUser1=$($newUser1.Name), table1=$($table1.Name), loginUser2=$($loginUser2.Name), newUser2=$($newUser2.Name), table2=$($table2.Name), table2Schema=$($table2.Schema)"
    }

    AfterAll {
        $removedDb = Remove-DbaDatabase -SqlInstance $server -Database $dbName -Confirm:$false
        $removedDBO = Remove-DbaLogin -SqlInstance $server -Login $loginNameDBO -Confirm:$false
        $removedDBOwner = Remove-DbaLogin -SqlInstance $server -Login $loginNameDBOwner -Confirm:$false
        $removedUser1 = Remove-DbaLogin -SqlInstance $server -Login $loginNameUser1 -Confirm:$false
        $removedUser2 = Remove-DbaLogin -SqlInstance $server -Login $loginNameUser2 -Confirm:$false
    }

    Context "Validate test setup" {

        It "Ensure that the BeforeAll completed successfully" {
            $loginDBO.Name | Should -Be $loginNameDBO
            $loginDBOwner.Name | Should -Be $loginNameDBOwner
            $loginUser1.Name | Should -Be $loginNameUser1
            $loginUser2.Name | Should -Be $loginNameUser2
            $newUserDBOwner.Name | Should -Be $loginNameDBOwner
            $newUser1.Name | Should -Be $loginNameUser1
            $newUser2.Name | Should -Be $loginNameUser2
            $table1.Name | Should -Be $tableName1
            $table2.Name | Should -Be $tableName2
            $table2.Schema | Should -Be $schemaNameForTable2
            $testDb.Name | Should -Be $dbName
        }
    }

    Context "parameters work" {
        It "returns server level permissions with -IncludeServerLevel" {
            $results = Get-DbaPermission -SqlInstance $server -IncludeServerLevel
            $results.where( { $_.Database -eq '' }).count | Should BeGreaterThan 0
        }
        It "returns no server level permissions without -IncludeServerLevel" {
            $results = Get-DbaPermission -SqlInstance $server
            $results.where( { $_.Database -eq '' }).count | Should Be 0
        }
        It "returns no system object permissions with -ExcludeSystemObjects" {
            $results = Get-DbaPermission -SqlInstance $server -ExcludeSystemObjects
            $results.where( { $_.securable -like 'sys.*' }).count | Should Be 0
        }
        It "returns system object permissions without -ExcludeSystemObjects" {
            $results = Get-DbaPermission -SqlInstance $server
            $results.where( { $_.securable -like 'sys.*' }).count | Should BeGreaterThan 0
        }
        It "db object level permissions for a user are returned correctly" {
            $results = Get-DbaPermission -SqlInstance $server -Database $dbName -ExcludeSystemObjects | Where-Object { $_.Grantee -eq $loginNameUser1 -and $_.SecurableType -ne "SCHEMA" }
            $results.count | Should -Be 4
            $results.where( { $_.Securable -eq "dbo.$tableName1" -and $_.PermState -eq 'DENY' -and $_.PermissionName -in ('DELETE', 'INSERT', 'UPDATE') }).count | Should -Be 3
            $results.where( { $_.Securable -eq "dbo.$tableName1" -and $_.PermState -eq 'GRANT' -and $_.PermissionName -eq 'SELECT' }).count | Should -Be 1
        }
    }
    Context "Validate input" {
        It "Cannot resolve hostname of computer" {
            Mock Resolve-DbaNetworkName { $null }
            { Get-DbaComputerSystem -ComputerName 'DoesNotExist142' -WarningAction Stop 3> $null } | Should Throw
        }
    }

    Context "Bug 6744" {
        It "the dbo user and db_owner users are returned in the result set with the CONTROL permission" {
            $results = Get-DbaPermission -SqlInstance $server -Database $dbName -ExcludeSystemObjects

            Write-Message -Level Verbose -Message "Get-DbaPermission: $($results | Out-String)"

            $results = $results | Where-Object { $_.Grantee -in ($loginNameDBO, $loginNameDBOwner) }
            $results.count | Should -Be 2

            $results.where( { ($_.Grantee -eq $loginNameDBO -and $_.GranteeType -eq "DATABASE OWNER (dbo user)" -and $_.PermissionName -eq "CONTROL") -or ($_.Grantee -eq $loginNameDBOwner -and $_.GranteeType -eq "DATABASE OWNER (db_owner role)" -and $_.PermissionName -eq "CONTROL") }).count | Should -Be 2
        }

        It "db schema level permissions are returned correctly" {
            $results = Get-DbaPermission -SqlInstance $server -Database $dbName -ExcludeSystemObjects | Where-Object { $_.Grantee -in ($loginNameUser1, $loginNameUser2) -and $_.SecurableType -eq "SCHEMA" }
            $results.where( { $_.Securable -eq "$schemaNameForTable2" -and $_.PermissionName -eq "CONTROL" }).count | Should -Be 2
            $results.where( { $_.Securable -eq "$schemaNameForTable2" -and $_.PermissionName -eq "CONTROL" -and $_.Grantee -eq $loginNameUser1 -and $_.GranteeType -eq "SCHEMA OWNER" }).count | Should -Be 1
            $results.where( { $_.Securable -eq "$schemaNameForTable2" -and $_.PermissionName -eq "CONTROL" -and $_.Grantee -eq $loginNameUser2 -and $_.GranteeType -eq "SQL_USER" }).count | Should -Be 1

        }
    }
}