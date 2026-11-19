#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaPermission",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command is read-only and has no SupportsShouldProcess.

Describe "Get-DbaPermission native contract" -Tag IntegrationTests {
    BeforeAll {
        $permissionPrefix = "native_permission_" + [Guid]::NewGuid().ToString("N")
        $permissionDbName = "${permissionPrefix}_a"
        $permissionOtherName = "${permissionPrefix}_b"
        $permissionRoleName = "${permissionPrefix}_role]"
        $permissionQuotedRole = "[" + $permissionRoleName.Replace("]", "]]") + "]"
        $permissionServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        foreach ($permissionName in @($permissionDbName, $permissionOtherName)) {
            $permissionNewDb = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $permissionServer, $permissionName
            $permissionNewDb.Create()
        }
        $permissionDb = $permissionServer.Databases[$permissionDbName]
        $permissionSchema = "native_schema]"
        $permissionTable = "native_table]"
        $permissionUser = "native_user]"
        $permissionTarget = "native_target]"
        $permissionType = "native_type]"
        $permissionQuotedSchema = "[" + $permissionSchema.Replace("]", "]]") + "]"
        $permissionQuotedTable = "[" + $permissionTable.Replace("]", "]]") + "]"
        $permissionQuotedUser = "[" + $permissionUser.Replace("]", "]]") + "]"
        $permissionQuotedTarget = "[" + $permissionTarget.Replace("]", "]]") + "]"
        $permissionQuotedType = "[" + $permissionType.Replace("]", "]]") + "]"
        $permissionDb.ExecuteNonQuery("CREATE USER $permissionQuotedUser WITHOUT LOGIN; CREATE USER $permissionQuotedTarget WITHOUT LOGIN;")
        $permissionDb.ExecuteNonQuery("CREATE SCHEMA $permissionQuotedSchema")
        $permissionDb.ExecuteNonQuery("CREATE TABLE $permissionQuotedSchema.$permissionQuotedTable (id int)")
        $permissionDb.ExecuteNonQuery("CREATE TYPE $permissionQuotedSchema.$permissionQuotedType FROM int")
        $permissionDb.ExecuteNonQuery(@"
GRANT SELECT ON OBJECT::$permissionQuotedSchema.$permissionQuotedTable TO $permissionQuotedUser WITH GRANT OPTION;
DENY INSERT ON OBJECT::$permissionQuotedSchema.$permissionQuotedTable TO $permissionQuotedUser;
GRANT VIEW DEFINITION ON SCHEMA::$permissionQuotedSchema TO $permissionQuotedUser;
GRANT VIEW DEFINITION TO $permissionQuotedUser;
GRANT IMPERSONATE ON USER::$permissionQuotedTarget TO $permissionQuotedUser;
GRANT REFERENCES ON TYPE::$permissionQuotedSchema.$permissionQuotedType TO $permissionQuotedUser;
"@)
        $permissionServer.ConnectionContext.ExecuteNonQuery("USE [master]") | Out-Null
        $permissionServer.ConnectionContext.ExecuteNonQuery("CREATE SERVER ROLE $permissionQuotedRole; DENY VIEW SERVER STATE TO $permissionQuotedRole;") | Out-Null
        $splatPermissionRead = @{
            SqlInstance     = $permissionServer
            Database        = $permissionDbName
            EnableException = $true
        }
    }

    AfterAll {
        if ($permissionServer) {
            try {
                $permissionServer.ConnectionContext.ExecuteNonQuery("USE [master]") | Out-Null
                $permissionServer.Databases.Refresh()
                foreach ($permissionCleanupName in @($permissionDbName, $permissionOtherName)) {
                    if ($permissionServer.Databases[$permissionCleanupName]) { $permissionServer.KillDatabase($permissionCleanupName) }
                }
            } finally {
                $permissionServer.Roles.Refresh()
                if ($permissionServer.Roles[$permissionRoleName]) { $permissionServer.Roles[$permissionRoleName].Drop() }
            }
        }
    }

    It "returns DataRows with the pinned twelve columns and actual instance identity" {
        $permissionRows = @(Get-DbaPermission @splatPermissionRead)
        $permissionRows.Count | Should -BeGreaterThan 0
        $permissionRows[0] | Should -BeOfType System.Data.DataRow
        @($permissionRows[0].Table.Columns.ColumnName) | Should -BeExactly @("ComputerName", "InstanceName", "SqlInstance", "Database", "PermState", "PermissionName", "SecurableType", "Securable", "Grantee", "GranteeType", "RevokeStatement", "GrantStatement")
        $permissionIdentity = $permissionServer.ConnectionContext.ExecuteWithResults("SELECT SERVERPROPERTY('MachineName') AS ComputerName, ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName, SERVERPROPERTY('ServerName') AS SqlInstance").Tables[0].Rows[0]
        $permissionRows[0].ComputerName | Should -BeExactly $permissionIdentity.ComputerName
        $permissionRows[0].InstanceName | Should -BeExactly $permissionIdentity.InstanceName
        $permissionRows[0].SqlInstance | Should -BeExactly $permissionIdentity.SqlInstance
        @($permissionRows.Database | Sort-Object -Unique) | Should -BeExactly @($permissionDbName)
    }

    It "streams both pipeline instances and both array instances" -Tag NativeChecklist:pipeline-multiple {
        $permissionOnce = @(Get-DbaPermission @splatPermissionRead)
        $permissionPiped = @($permissionServer, $permissionServer | Get-DbaPermission -Database $permissionDbName -EnableException)
        $permissionArray = @(Get-DbaPermission -SqlInstance $permissionServer, $permissionServer -Database $permissionDbName -EnableException)
        $permissionPiped.Count | Should -Be ($permissionOnce.Count * 2)
        $permissionArray.Count | Should -Be ($permissionOnce.Count * 2)
        @($permissionPiped.Database | Sort-Object -Unique) | Should -BeExactly @($permissionDbName)
    }

    It "preserves explicit false switches and literal inclusion and exclusion" -Tag NativeChecklist:switch-false {
        $splatPermissionSwitches = @{
            SqlInstance          = $permissionServer
            Database             = @($permissionDbName, $permissionOtherName)
            ExcludeDatabase      = $permissionOtherName
            IncludeServerLevel   = $false
            ExcludeSystemObjects = $false
            EnableException      = $false
        }
        $permissionSwitchRows = @(Get-DbaPermission @splatPermissionSwitches)
        @($permissionSwitchRows.Database | Sort-Object -Unique) | Should -BeExactly @($permissionDbName)
        $permissionSwitchRows | Where-Object Securable -Like "sys.*" | Should -Not -BeNullOrEmpty
    }

    It "continues to the next instance after a connection warning and stops when requested" -Tag NativeChecklist:multi-instance-failure, NativeChecklist:enable-exception {
        $permissionWarnings = @()
        $splatPermissionFailure = @{
            SqlInstance     = @("TCP:127.0.0.1,1", $permissionServer)
            Database        = $permissionDbName
            WarningVariable = "permissionWarnings"
            WarningAction   = "SilentlyContinue"
        }
        $permissionContinued = @(Get-DbaPermission @splatPermissionFailure -EnableException:$false)
        $permissionContinued.Count | Should -BeGreaterThan 0
        ($permissionWarnings -join " ") | Should -BeLike "*Failure*Error connecting*"
        { Get-DbaPermission @splatPermissionFailure -EnableException } | Should -Throw
    }

    It "honours documented inclusion wildcard patterns" {
        $permissionPatternRows = @(Get-DbaPermission -SqlInstance $permissionServer -Database "${permissionPrefix}_?" -EnableException)
        @($permissionPatternRows.Database | Sort-Object -Unique) | Should -BeExactly @($permissionDbName, $permissionOtherName)
    }

    It "honours documented exclusion wildcard patterns" {
        $splatPermissionExclude = @{
            SqlInstance     = $permissionServer
            Database        = @($permissionDbName, $permissionOtherName)
            ExcludeDatabase = "${permissionPrefix}_b*"
            EnableException = $true
        }
        $permissionExcludedRows = @(Get-DbaPermission @splatPermissionExclude)
        @($permissionExcludedRows.Database | Sort-Object -Unique) | Should -BeExactly @($permissionDbName)
    }

    It "renders escaped object and schema permission statements with the real permission state" {
        $permissionScriptRows = @(Get-DbaPermission @splatPermissionRead | Where-Object { $PSItem.Grantee -eq $permissionUser -and $PSItem.SecurableType -in "USER_TABLE", "SCHEMA" })
        $permissionScriptRows.Count | Should -Be 3
        foreach ($permissionScriptRow in $permissionScriptRows) {
            $permissionScriptRow.GrantStatement | Should -Not -BeNullOrEmpty
            $permissionScriptRow.GrantStatement | Should -Not -Match "GRANT_WITH_GRANT_OPTION"
            $permissionScriptRow.GrantStatement | Should -Match ([regex]::Escape($permissionQuotedUser))
            $permissionScriptRow.RevokeStatement | Should -Match ([regex]::Escape($permissionQuotedUser))
            # Reset this disposable fixture's grant option explicitly; a generated REVOKE does not choose CASCADE for callers.
            $permissionRevoke = $permissionScriptRow.RevokeStatement
            if ($permissionScriptRow.PermState -eq "GRANT_WITH_GRANT_OPTION") { $permissionRevoke += " CASCADE" }
            $permissionDb.ExecuteNonQuery($permissionRevoke)
            $permissionDb.ExecuteNonQuery($permissionScriptRow.GrantStatement)
        }
        $permissionRestored = @(Get-DbaPermission @splatPermissionRead | Where-Object { $PSItem.Grantee -eq $permissionUser -and $PSItem.SecurableType -in "USER_TABLE", "SCHEMA" })
        @($permissionRestored | ForEach-Object { "$($PSItem.Securable)|$($PSItem.PermissionName)|$($PSItem.PermState)" } | Sort-Object) | Should -BeExactly @($permissionScriptRows | ForEach-Object { "$($PSItem.Securable)|$($PSItem.PermissionName)|$($PSItem.PermState)" } | Sort-Object)
    }

    It "renders database permission scripts without losing their securable" {
        $permissionDatabaseRow = @(Get-DbaPermission @splatPermissionRead | Where-Object { $PSItem.Grantee -eq $permissionUser -and $PSItem.SecurableType -eq "DATABASE" -and $PSItem.PermissionName -eq "VIEW DEFINITION" })
        $permissionDatabaseRow.Count | Should -Be 1
        $permissionDatabaseRow[0].GrantStatement | Should -Not -BeNullOrEmpty
        $permissionDatabaseRow[0].RevokeStatement | Should -Not -BeNullOrEmpty
        $permissionDb.ExecuteNonQuery($permissionDatabaseRow[0].RevokeStatement)
        $permissionDb.ExecuteNonQuery($permissionDatabaseRow[0].GrantStatement)
        $permissionRestoredDatabaseRow = @(Get-DbaPermission @splatPermissionRead | Where-Object { $PSItem.Grantee -eq $permissionUser -and $PSItem.SecurableType -eq "DATABASE" -and $PSItem.PermissionName -eq "VIEW DEFINITION" })
        $permissionRestoredDatabaseRow.Count | Should -Be 1
        $permissionRestoredDatabaseRow[0].PermState | Should -BeExactly "GRANT"
    }

    It "keeps a server role denial when replaying its escaped permission scripts" {
        $permissionServer.ConnectionContext.ExecuteNonQuery("USE [master]") | Out-Null
        $splatPermissionRole = @{
            SqlInstance        = $permissionServer
            Database           = "${permissionPrefix}_absent"
            IncludeServerLevel = $true
            EnableException    = $true
        }
        $permissionRoleRows = @(Get-DbaPermission @splatPermissionRole | Where-Object Grantee -EQ $permissionRoleName)
        $permissionRoleRows.Count | Should -Be 1
        $permissionRoleRows[0].PermState | Should -BeExactly "DENY"
        $permissionRoleRows[0].GrantStatement | Should -Match "^DENY VIEW SERVER STATE "
        $permissionRoleRows[0].GrantStatement | Should -Match ([regex]::Escape($permissionQuotedRole))
        $permissionRoleRows[0].RevokeStatement | Should -Match ([regex]::Escape($permissionQuotedRole))
        $permissionServer.ConnectionContext.ExecuteNonQuery($permissionRoleRows[0].RevokeStatement) | Out-Null
        $permissionServer.ConnectionContext.ExecuteNonQuery($permissionRoleRows[0].GrantStatement) | Out-Null
        $permissionRoleAfter = @(Get-DbaPermission @splatPermissionRole | Where-Object Grantee -EQ $permissionRoleName)
        $permissionRoleAfter.Count | Should -Be 1
        $permissionRoleAfter[0].PermState | Should -BeExactly "DENY"
    }

    It "returns the real user securable and executable principal permission scripts" {
        $permissionUserRows = @(Get-DbaPermission @splatPermissionRead | Where-Object { $PSItem.Grantee -eq $permissionUser -and $PSItem.PermissionName -eq "IMPERSONATE" })
        $permissionUserRows.Count | Should -Be 1
        $permissionUserRows[0].Securable | Should -BeExactly $permissionTarget
        $permissionUserRows[0].SecurableType | Should -BeExactly "DATABASE_PRINCIPAL"
        $permissionUserRows[0].GrantStatement | Should -Not -BeNullOrEmpty
        $permissionUserRows[0].RevokeStatement | Should -Not -BeNullOrEmpty
        $permissionDb.ExecuteNonQuery($permissionUserRows[0].RevokeStatement)
        $permissionDb.ExecuteNonQuery($permissionUserRows[0].GrantStatement)
        $permissionRestoredUser = @(Get-DbaPermission @splatPermissionRead | Where-Object { $PSItem.Grantee -eq $permissionUser -and $PSItem.PermissionName -eq "IMPERSONATE" -and $PSItem.Securable -eq $permissionTarget })
        $permissionRestoredUser.Count | Should -Be 1
        $permissionRestoredUser[0].PermState | Should -BeExactly "GRANT"
    }

    It "returns the real type securable and executable type permission scripts" {
        $permissionTypeRows = @(Get-DbaPermission @splatPermissionRead | Where-Object { $PSItem.Grantee -eq $permissionUser -and $PSItem.PermissionName -eq "REFERENCES" })
        $permissionTypeRows.Count | Should -Be 1
        $permissionTypeRows[0].Securable | Should -BeExactly "$permissionSchema.$permissionType"
        $permissionTypeRows[0].SecurableType | Should -BeExactly "TYPE"
        $permissionTypeRows[0].GrantStatement | Should -Not -BeNullOrEmpty
        $permissionTypeRows[0].RevokeStatement | Should -Not -BeNullOrEmpty
        $permissionDb.ExecuteNonQuery($permissionTypeRows[0].RevokeStatement)
        $permissionDb.ExecuteNonQuery($permissionTypeRows[0].GrantStatement)
        $permissionRestoredType = @(Get-DbaPermission @splatPermissionRead | Where-Object { $PSItem.Grantee -eq $permissionUser -and $PSItem.PermissionName -eq "REFERENCES" -and $PSItem.Securable -eq "$permissionSchema.$permissionType" })
        $permissionRestoredType.Count | Should -Be 1
        $permissionRestoredType[0].PermState | Should -BeExactly "GRANT"
    }

    It "preserves column restrictions in grant deny and revoke permission scripts" {
        foreach ($columnState in 'GRANT', 'DENY', 'REVOKE') {
            $columnToken = 'column_' + [guid]::NewGuid().ToString('N')
            $columnUser = $columnToken + '_user'
            $columnName = 'restricted]column'
            $quotedColumn = '[' + $columnName.Replace(']', ']]') + ']'
            try {
                $permissionDb.ExecuteNonQuery("CREATE USER [$columnUser] WITHOUT LOGIN; CREATE TABLE dbo.[$columnToken] ($quotedColumn int, untouched int);")
                if ($columnState -eq 'REVOKE') {
                    $permissionDb.ExecuteNonQuery("GRANT SELECT ON OBJECT::dbo.[$columnToken] TO [$columnUser]; REVOKE SELECT ON OBJECT::dbo.[$columnToken] ($quotedColumn) FROM [$columnUser];")
                } else {
                    $permissionDb.ExecuteNonQuery("$columnState SELECT ON OBJECT::dbo.[$columnToken] ($quotedColumn) TO [$columnUser];")
                }
                $columnCatalogSql = "SELECT minor_id, state_desc FROM sys.database_permissions WHERE class=1 AND major_id=OBJECT_ID(N'dbo.$columnToken') AND grantee_principal_id=USER_ID(N'$columnUser') AND permission_name=N'SELECT' ORDER BY minor_id;"
                $columnBefore = @($permissionDb.ExecuteWithResults($columnCatalogSql).Tables[0].Rows | ForEach-Object { "$($PSItem.minor_id)|$($PSItem.state_desc)" })
                $columnBefore | Should -Contain "1|$columnState"
                $columnRows = @(Get-DbaPermission @splatPermissionRead | Where-Object { $PSItem.Grantee -eq $columnUser -and $PSItem.PermissionName -eq 'SELECT' -and $PSItem.PermState -eq $columnState })
                $columnRows.Count | Should -Be 1
                $columnRows[0].GrantStatement | Should -Match ([regex]::Escape(" ($quotedColumn)"))
                $columnRows[0].RevokeStatement | Should -Match ([regex]::Escape(" ($quotedColumn)"))
                $permissionDb.ExecuteNonQuery($columnRows[0].RevokeStatement)
                if ($columnState -ne 'REVOKE') {
                    @($permissionDb.ExecuteWithResults($columnCatalogSql).Tables[0].Rows).Count | Should -Be 0
                }
                $permissionDb.ExecuteNonQuery($columnRows[0].GrantStatement)
                $columnAfter = @($permissionDb.ExecuteWithResults($columnCatalogSql).Tables[0].Rows | ForEach-Object { "$($PSItem.minor_id)|$($PSItem.state_desc)" })
                $columnAfter | Should -BeExactly $columnBefore
            } finally {
                $permissionDb.ExecuteNonQuery("IF OBJECT_ID(N'dbo.$columnToken') IS NOT NULL DROP TABLE dbo.[$columnToken]; IF USER_ID(N'$columnUser') IS NOT NULL DROP USER [$columnUser];")
                $permissionDb.ExecuteWithResults("SELECT OBJECT_ID(N'dbo.$columnToken') AS ObjectId, USER_ID(N'$columnUser') AS UserId;").Tables[0].Rows[0].ItemArray | ForEach-Object { $PSItem | Should -Be ([DBNull]::Value) }
            }
        }
    }

    It "renders and replays ASSEMBLY permission scripts with the actual securable" {
        $Scope = 'ASSEMBLY'
        $Class = 5
        $Catalog = 'sys.assemblies'
        $IdColumn = 'assembly_id'
        $Type = 'ASSEMBLY'
        $scopeToken = 'scope_' + [guid]::NewGuid().ToString('N')
        $scopeUser = $scopeToken + '_user]'
        $scopeName = $scopeToken + '_target]'
        # Use the assembly already present in this disposable database. No CLR code is loaded
        # or executed and no server trust/configuration is changed; only our user gains a row.
        if ($Scope -eq 'ASSEMBLY') { $scopeName = 'Microsoft.SqlServer.Types' }
        $quotedScopeName = '[' + $scopeName.Replace(']', ']]') + ']'
        $quotedScopeUser = '[' + $scopeUser.Replace(']', ']]') + ']'
        $scopePassword = 'Native!' + [guid]::NewGuid().ToString('N')
        $scopeCreated = $false
        try {
            $permissionDb.ExecuteNonQuery("CREATE USER $quotedScopeUser WITHOUT LOGIN;")
            switch ($Scope) {
                'FULLTEXT CATALOG' { $permissionDb.ExecuteNonQuery("CREATE FULLTEXT CATALOG $quotedScopeName;"); $scopeCreated = $true }
                'SYMMETRIC KEY' { $permissionDb.ExecuteNonQuery("CREATE SYMMETRIC KEY $quotedScopeName WITH ALGORITHM = AES_256 ENCRYPTION BY PASSWORD = '$scopePassword';"); $scopeCreated = $true }
                'CERTIFICATE' { $permissionDb.ExecuteNonQuery("CREATE CERTIFICATE $quotedScopeName ENCRYPTION BY PASSWORD = '$scopePassword' WITH SUBJECT = 'native permission fixture';"); $scopeCreated = $true }
                'ASYMMETRIC KEY' { $permissionDb.ExecuteNonQuery("CREATE ASYMMETRIC KEY $quotedScopeName WITH ALGORITHM = RSA_2048 ENCRYPTION BY PASSWORD = '$scopePassword';"); $scopeCreated = $true }
            }
            $scopeIdRows = @($permissionDb.ExecuteWithResults("SELECT $IdColumn AS Id FROM $Catalog WHERE name=N'$scopeName';").Tables[0].Rows)
            $scopeIdRows.Count | Should -Be 1
            $scopeId = [int]$scopeIdRows[0].Id
            $scopeCatalogSql = "SELECT class, major_id, permission_name, state_desc FROM sys.database_permissions WHERE grantee_principal_id=USER_ID(N'$scopeUser') AND class=$Class AND major_id=$scopeId;"
            foreach ($scopeState in 'GRANT', 'DENY', 'GRANT_WITH_GRANT_OPTION') {
                $scopeVerb = if ($scopeState -eq 'DENY') { 'DENY' } else { 'GRANT' }
                $scopeOption = if ($scopeState -eq 'GRANT_WITH_GRANT_OPTION') { ' WITH GRANT OPTION' } else { '' }
                $permissionDb.ExecuteNonQuery("$scopeVerb VIEW DEFINITION ON ${Scope}::$quotedScopeName TO $quotedScopeUser$scopeOption;")
                $scopeBefore = @($permissionDb.ExecuteWithResults($scopeCatalogSql).Tables[0].Rows | ForEach-Object { "$($PSItem.class)|$($PSItem.major_id)|$($PSItem.permission_name)|$($PSItem.state_desc)" })
                $scopeBefore | Should -BeExactly @("$Class|$scopeId|VIEW DEFINITION|$scopeState")
                $scopeRows = @(Get-DbaPermission @splatPermissionRead | Where-Object { $PSItem.Grantee -eq $scopeUser -and $PSItem.PermissionName -eq 'VIEW DEFINITION' })
                $scopeRows.Count | Should -Be 1
                $scopeRows[0].SecurableType | Should -BeExactly $Type
                $scopeRows[0].Securable | Should -BeExactly $scopeName
                $scopeRows[0].GrantStatement | Should -BeExactly "$scopeVerb VIEW DEFINITION ON ${Scope}::$quotedScopeName TO $quotedScopeUser$scopeOption"
                $scopeRows[0].RevokeStatement | Should -BeExactly "REVOKE VIEW DEFINITION ON ${Scope}::$quotedScopeName FROM $quotedScopeUser"
                $scopeRevoke = $scopeRows[0].RevokeStatement
                if ($scopeState -eq 'GRANT_WITH_GRANT_OPTION') { $scopeRevoke += ' CASCADE' }
                $permissionDb.ExecuteNonQuery($scopeRevoke)
                @($permissionDb.ExecuteWithResults($scopeCatalogSql).Tables[0].Rows).Count | Should -Be 0
                $permissionDb.ExecuteNonQuery($scopeRows[0].GrantStatement)
                $scopeAfter = @($permissionDb.ExecuteWithResults($scopeCatalogSql).Tables[0].Rows | ForEach-Object { "$($PSItem.class)|$($PSItem.major_id)|$($PSItem.permission_name)|$($PSItem.state_desc)" })
                $scopeAfter | Should -BeExactly $scopeBefore
                $permissionDb.ExecuteNonQuery($scopeRevoke)
            }
        } finally {
            $permissionDb.ExecuteNonQuery("IF USER_ID(N'$scopeUser') IS NOT NULL DROP USER $quotedScopeUser;")
            if ($scopeCreated) {
                $permissionDb.ExecuteNonQuery("DROP $Scope $quotedScopeName;")
                @($permissionDb.ExecuteWithResults("SELECT $IdColumn FROM $Catalog WHERE name=N'$scopeName';").Tables[0].Rows).Count | Should -Be 0
            }
            $permissionDb.ExecuteWithResults("SELECT USER_ID(N'$scopeUser') AS Id;").Tables[0].Rows[0].Id | Should -Be ([DBNull]::Value)
        }
    }

    It "renders and replays FULLTEXT CATALOG permission scripts with the actual securable" {
        $Scope = 'FULLTEXT CATALOG'
        $Class = 23
        $Catalog = 'sys.fulltext_catalogs'
        $IdColumn = 'fulltext_catalog_id'
        $Type = 'FULLTEXT_CATALOG'
        $scopeToken = 'scope_' + [guid]::NewGuid().ToString('N')
        $scopeUser = $scopeToken + '_user]'
        $scopeName = $scopeToken + '_target]'
        # Use the assembly already present in this disposable database. No CLR code is loaded
        # or executed and no server trust/configuration is changed; only our user gains a row.
        if ($Scope -eq 'ASSEMBLY') { $scopeName = 'Microsoft.SqlServer.Types' }
        $quotedScopeName = '[' + $scopeName.Replace(']', ']]') + ']'
        $quotedScopeUser = '[' + $scopeUser.Replace(']', ']]') + ']'
        $scopePassword = 'Native!' + [guid]::NewGuid().ToString('N')
        $scopeCreated = $false
        try {
            $permissionDb.ExecuteNonQuery("CREATE USER $quotedScopeUser WITHOUT LOGIN;")
            switch ($Scope) {
                'FULLTEXT CATALOG' { $permissionDb.ExecuteNonQuery("CREATE FULLTEXT CATALOG $quotedScopeName;"); $scopeCreated = $true }
                'SYMMETRIC KEY' { $permissionDb.ExecuteNonQuery("CREATE SYMMETRIC KEY $quotedScopeName WITH ALGORITHM = AES_256 ENCRYPTION BY PASSWORD = '$scopePassword';"); $scopeCreated = $true }
                'CERTIFICATE' { $permissionDb.ExecuteNonQuery("CREATE CERTIFICATE $quotedScopeName ENCRYPTION BY PASSWORD = '$scopePassword' WITH SUBJECT = 'native permission fixture';"); $scopeCreated = $true }
                'ASYMMETRIC KEY' { $permissionDb.ExecuteNonQuery("CREATE ASYMMETRIC KEY $quotedScopeName WITH ALGORITHM = RSA_2048 ENCRYPTION BY PASSWORD = '$scopePassword';"); $scopeCreated = $true }
            }
            $scopeIdRows = @($permissionDb.ExecuteWithResults("SELECT $IdColumn AS Id FROM $Catalog WHERE name=N'$scopeName';").Tables[0].Rows)
            $scopeIdRows.Count | Should -Be 1
            $scopeId = [int]$scopeIdRows[0].Id
            $scopeCatalogSql = "SELECT class, major_id, permission_name, state_desc FROM sys.database_permissions WHERE grantee_principal_id=USER_ID(N'$scopeUser') AND class=$Class AND major_id=$scopeId;"
            foreach ($scopeState in 'GRANT', 'DENY', 'GRANT_WITH_GRANT_OPTION') {
                $scopeVerb = if ($scopeState -eq 'DENY') { 'DENY' } else { 'GRANT' }
                $scopeOption = if ($scopeState -eq 'GRANT_WITH_GRANT_OPTION') { ' WITH GRANT OPTION' } else { '' }
                $permissionDb.ExecuteNonQuery("$scopeVerb VIEW DEFINITION ON ${Scope}::$quotedScopeName TO $quotedScopeUser$scopeOption;")
                $scopeBefore = @($permissionDb.ExecuteWithResults($scopeCatalogSql).Tables[0].Rows | ForEach-Object { "$($PSItem.class)|$($PSItem.major_id)|$($PSItem.permission_name)|$($PSItem.state_desc)" })
                $scopeBefore | Should -BeExactly @("$Class|$scopeId|VIEW DEFINITION|$scopeState")
                $scopeRows = @(Get-DbaPermission @splatPermissionRead | Where-Object { $PSItem.Grantee -eq $scopeUser -and $PSItem.PermissionName -eq 'VIEW DEFINITION' })
                $scopeRows.Count | Should -Be 1
                $scopeRows[0].SecurableType | Should -BeExactly $Type
                $scopeRows[0].Securable | Should -BeExactly $scopeName
                $scopeRows[0].GrantStatement | Should -BeExactly "$scopeVerb VIEW DEFINITION ON ${Scope}::$quotedScopeName TO $quotedScopeUser$scopeOption"
                $scopeRows[0].RevokeStatement | Should -BeExactly "REVOKE VIEW DEFINITION ON ${Scope}::$quotedScopeName FROM $quotedScopeUser"
                $scopeRevoke = $scopeRows[0].RevokeStatement
                if ($scopeState -eq 'GRANT_WITH_GRANT_OPTION') { $scopeRevoke += ' CASCADE' }
                $permissionDb.ExecuteNonQuery($scopeRevoke)
                @($permissionDb.ExecuteWithResults($scopeCatalogSql).Tables[0].Rows).Count | Should -Be 0
                $permissionDb.ExecuteNonQuery($scopeRows[0].GrantStatement)
                $scopeAfter = @($permissionDb.ExecuteWithResults($scopeCatalogSql).Tables[0].Rows | ForEach-Object { "$($PSItem.class)|$($PSItem.major_id)|$($PSItem.permission_name)|$($PSItem.state_desc)" })
                $scopeAfter | Should -BeExactly $scopeBefore
                $permissionDb.ExecuteNonQuery($scopeRevoke)
            }
        } finally {
            $permissionDb.ExecuteNonQuery("IF USER_ID(N'$scopeUser') IS NOT NULL DROP USER $quotedScopeUser;")
            if ($scopeCreated) {
                $permissionDb.ExecuteNonQuery("DROP $Scope $quotedScopeName;")
                @($permissionDb.ExecuteWithResults("SELECT $IdColumn FROM $Catalog WHERE name=N'$scopeName';").Tables[0].Rows).Count | Should -Be 0
            }
            $permissionDb.ExecuteWithResults("SELECT USER_ID(N'$scopeUser') AS Id;").Tables[0].Rows[0].Id | Should -Be ([DBNull]::Value)
        }
    }

    It "renders and replays SYMMETRIC KEY permission scripts with the actual securable" {
        $Scope = 'SYMMETRIC KEY'
        $Class = 24
        $Catalog = 'sys.symmetric_keys'
        $IdColumn = 'symmetric_key_id'
        $Type = 'SYMMETRIC_KEYS'
        $scopeToken = 'scope_' + [guid]::NewGuid().ToString('N')
        $scopeUser = $scopeToken + '_user]'
        $scopeName = $scopeToken + '_target]'
        # Use the assembly already present in this disposable database. No CLR code is loaded
        # or executed and no server trust/configuration is changed; only our user gains a row.
        if ($Scope -eq 'ASSEMBLY') { $scopeName = 'Microsoft.SqlServer.Types' }
        $quotedScopeName = '[' + $scopeName.Replace(']', ']]') + ']'
        $quotedScopeUser = '[' + $scopeUser.Replace(']', ']]') + ']'
        $scopePassword = 'Native!' + [guid]::NewGuid().ToString('N')
        $scopeCreated = $false
        try {
            $permissionDb.ExecuteNonQuery("CREATE USER $quotedScopeUser WITHOUT LOGIN;")
            switch ($Scope) {
                'FULLTEXT CATALOG' { $permissionDb.ExecuteNonQuery("CREATE FULLTEXT CATALOG $quotedScopeName;"); $scopeCreated = $true }
                'SYMMETRIC KEY' { $permissionDb.ExecuteNonQuery("CREATE SYMMETRIC KEY $quotedScopeName WITH ALGORITHM = AES_256 ENCRYPTION BY PASSWORD = '$scopePassword';"); $scopeCreated = $true }
                'CERTIFICATE' { $permissionDb.ExecuteNonQuery("CREATE CERTIFICATE $quotedScopeName ENCRYPTION BY PASSWORD = '$scopePassword' WITH SUBJECT = 'native permission fixture';"); $scopeCreated = $true }
                'ASYMMETRIC KEY' { $permissionDb.ExecuteNonQuery("CREATE ASYMMETRIC KEY $quotedScopeName WITH ALGORITHM = RSA_2048 ENCRYPTION BY PASSWORD = '$scopePassword';"); $scopeCreated = $true }
            }
            $scopeIdRows = @($permissionDb.ExecuteWithResults("SELECT $IdColumn AS Id FROM $Catalog WHERE name=N'$scopeName';").Tables[0].Rows)
            $scopeIdRows.Count | Should -Be 1
            $scopeId = [int]$scopeIdRows[0].Id
            $scopeCatalogSql = "SELECT class, major_id, permission_name, state_desc FROM sys.database_permissions WHERE grantee_principal_id=USER_ID(N'$scopeUser') AND class=$Class AND major_id=$scopeId;"
            foreach ($scopeState in 'GRANT', 'DENY', 'GRANT_WITH_GRANT_OPTION') {
                $scopeVerb = if ($scopeState -eq 'DENY') { 'DENY' } else { 'GRANT' }
                $scopeOption = if ($scopeState -eq 'GRANT_WITH_GRANT_OPTION') { ' WITH GRANT OPTION' } else { '' }
                $permissionDb.ExecuteNonQuery("$scopeVerb VIEW DEFINITION ON ${Scope}::$quotedScopeName TO $quotedScopeUser$scopeOption;")
                $scopeBefore = @($permissionDb.ExecuteWithResults($scopeCatalogSql).Tables[0].Rows | ForEach-Object { "$($PSItem.class)|$($PSItem.major_id)|$($PSItem.permission_name)|$($PSItem.state_desc)" })
                $scopeBefore | Should -BeExactly @("$Class|$scopeId|VIEW DEFINITION|$scopeState")
                $scopeRows = @(Get-DbaPermission @splatPermissionRead | Where-Object { $PSItem.Grantee -eq $scopeUser -and $PSItem.PermissionName -eq 'VIEW DEFINITION' })
                $scopeRows.Count | Should -Be 1
                $scopeRows[0].SecurableType | Should -BeExactly $Type
                $scopeRows[0].Securable | Should -BeExactly $scopeName
                $scopeRows[0].GrantStatement | Should -BeExactly "$scopeVerb VIEW DEFINITION ON ${Scope}::$quotedScopeName TO $quotedScopeUser$scopeOption"
                $scopeRows[0].RevokeStatement | Should -BeExactly "REVOKE VIEW DEFINITION ON ${Scope}::$quotedScopeName FROM $quotedScopeUser"
                $scopeRevoke = $scopeRows[0].RevokeStatement
                if ($scopeState -eq 'GRANT_WITH_GRANT_OPTION') { $scopeRevoke += ' CASCADE' }
                $permissionDb.ExecuteNonQuery($scopeRevoke)
                @($permissionDb.ExecuteWithResults($scopeCatalogSql).Tables[0].Rows).Count | Should -Be 0
                $permissionDb.ExecuteNonQuery($scopeRows[0].GrantStatement)
                $scopeAfter = @($permissionDb.ExecuteWithResults($scopeCatalogSql).Tables[0].Rows | ForEach-Object { "$($PSItem.class)|$($PSItem.major_id)|$($PSItem.permission_name)|$($PSItem.state_desc)" })
                $scopeAfter | Should -BeExactly $scopeBefore
                $permissionDb.ExecuteNonQuery($scopeRevoke)
            }
        } finally {
            $permissionDb.ExecuteNonQuery("IF USER_ID(N'$scopeUser') IS NOT NULL DROP USER $quotedScopeUser;")
            if ($scopeCreated) {
                $permissionDb.ExecuteNonQuery("DROP $Scope $quotedScopeName;")
                @($permissionDb.ExecuteWithResults("SELECT $IdColumn FROM $Catalog WHERE name=N'$scopeName';").Tables[0].Rows).Count | Should -Be 0
            }
            $permissionDb.ExecuteWithResults("SELECT USER_ID(N'$scopeUser') AS Id;").Tables[0].Rows[0].Id | Should -Be ([DBNull]::Value)
        }
    }

    It "renders and replays CERTIFICATE permission scripts with the actual securable" {
        $Scope = 'CERTIFICATE'
        $Class = 25
        $Catalog = 'sys.certificates'
        $IdColumn = 'certificate_id'
        $Type = 'CERTIFICATE'
        $scopeToken = 'scope_' + [guid]::NewGuid().ToString('N')
        $scopeUser = $scopeToken + '_user]'
        $scopeName = $scopeToken + '_target]'
        # Use the assembly already present in this disposable database. No CLR code is loaded
        # or executed and no server trust/configuration is changed; only our user gains a row.
        if ($Scope -eq 'ASSEMBLY') { $scopeName = 'Microsoft.SqlServer.Types' }
        $quotedScopeName = '[' + $scopeName.Replace(']', ']]') + ']'
        $quotedScopeUser = '[' + $scopeUser.Replace(']', ']]') + ']'
        $scopePassword = 'Native!' + [guid]::NewGuid().ToString('N')
        $scopeCreated = $false
        try {
            $permissionDb.ExecuteNonQuery("CREATE USER $quotedScopeUser WITHOUT LOGIN;")
            switch ($Scope) {
                'FULLTEXT CATALOG' { $permissionDb.ExecuteNonQuery("CREATE FULLTEXT CATALOG $quotedScopeName;"); $scopeCreated = $true }
                'SYMMETRIC KEY' { $permissionDb.ExecuteNonQuery("CREATE SYMMETRIC KEY $quotedScopeName WITH ALGORITHM = AES_256 ENCRYPTION BY PASSWORD = '$scopePassword';"); $scopeCreated = $true }
                'CERTIFICATE' { $permissionDb.ExecuteNonQuery("CREATE CERTIFICATE $quotedScopeName ENCRYPTION BY PASSWORD = '$scopePassword' WITH SUBJECT = 'native permission fixture';"); $scopeCreated = $true }
                'ASYMMETRIC KEY' { $permissionDb.ExecuteNonQuery("CREATE ASYMMETRIC KEY $quotedScopeName WITH ALGORITHM = RSA_2048 ENCRYPTION BY PASSWORD = '$scopePassword';"); $scopeCreated = $true }
            }
            $scopeIdRows = @($permissionDb.ExecuteWithResults("SELECT $IdColumn AS Id FROM $Catalog WHERE name=N'$scopeName';").Tables[0].Rows)
            $scopeIdRows.Count | Should -Be 1
            $scopeId = [int]$scopeIdRows[0].Id
            $scopeCatalogSql = "SELECT class, major_id, permission_name, state_desc FROM sys.database_permissions WHERE grantee_principal_id=USER_ID(N'$scopeUser') AND class=$Class AND major_id=$scopeId;"
            foreach ($scopeState in 'GRANT', 'DENY', 'GRANT_WITH_GRANT_OPTION') {
                $scopeVerb = if ($scopeState -eq 'DENY') { 'DENY' } else { 'GRANT' }
                $scopeOption = if ($scopeState -eq 'GRANT_WITH_GRANT_OPTION') { ' WITH GRANT OPTION' } else { '' }
                $permissionDb.ExecuteNonQuery("$scopeVerb VIEW DEFINITION ON ${Scope}::$quotedScopeName TO $quotedScopeUser$scopeOption;")
                $scopeBefore = @($permissionDb.ExecuteWithResults($scopeCatalogSql).Tables[0].Rows | ForEach-Object { "$($PSItem.class)|$($PSItem.major_id)|$($PSItem.permission_name)|$($PSItem.state_desc)" })
                $scopeBefore | Should -BeExactly @("$Class|$scopeId|VIEW DEFINITION|$scopeState")
                $scopeRows = @(Get-DbaPermission @splatPermissionRead | Where-Object { $PSItem.Grantee -eq $scopeUser -and $PSItem.PermissionName -eq 'VIEW DEFINITION' })
                $scopeRows.Count | Should -Be 1
                $scopeRows[0].SecurableType | Should -BeExactly $Type
                $scopeRows[0].Securable | Should -BeExactly $scopeName
                $scopeRows[0].GrantStatement | Should -BeExactly "$scopeVerb VIEW DEFINITION ON ${Scope}::$quotedScopeName TO $quotedScopeUser$scopeOption"
                $scopeRows[0].RevokeStatement | Should -BeExactly "REVOKE VIEW DEFINITION ON ${Scope}::$quotedScopeName FROM $quotedScopeUser"
                $scopeRevoke = $scopeRows[0].RevokeStatement
                if ($scopeState -eq 'GRANT_WITH_GRANT_OPTION') { $scopeRevoke += ' CASCADE' }
                $permissionDb.ExecuteNonQuery($scopeRevoke)
                @($permissionDb.ExecuteWithResults($scopeCatalogSql).Tables[0].Rows).Count | Should -Be 0
                $permissionDb.ExecuteNonQuery($scopeRows[0].GrantStatement)
                $scopeAfter = @($permissionDb.ExecuteWithResults($scopeCatalogSql).Tables[0].Rows | ForEach-Object { "$($PSItem.class)|$($PSItem.major_id)|$($PSItem.permission_name)|$($PSItem.state_desc)" })
                $scopeAfter | Should -BeExactly $scopeBefore
                $permissionDb.ExecuteNonQuery($scopeRevoke)
            }
        } finally {
            $permissionDb.ExecuteNonQuery("IF USER_ID(N'$scopeUser') IS NOT NULL DROP USER $quotedScopeUser;")
            if ($scopeCreated) {
                $permissionDb.ExecuteNonQuery("DROP $Scope $quotedScopeName;")
                @($permissionDb.ExecuteWithResults("SELECT $IdColumn FROM $Catalog WHERE name=N'$scopeName';").Tables[0].Rows).Count | Should -Be 0
            }
            $permissionDb.ExecuteWithResults("SELECT USER_ID(N'$scopeUser') AS Id;").Tables[0].Rows[0].Id | Should -Be ([DBNull]::Value)
        }
    }

    It "renders and replays ASYMMETRIC KEY permission scripts with the actual securable" {
        $Scope = 'ASYMMETRIC KEY'
        $Class = 26
        $Catalog = 'sys.asymmetric_keys'
        $IdColumn = 'asymmetric_key_id'
        $Type = 'ASYMMETRIC_KEY'
        $scopeToken = 'scope_' + [guid]::NewGuid().ToString('N')
        $scopeUser = $scopeToken + '_user]'
        $scopeName = $scopeToken + '_target]'
        # Use the assembly already present in this disposable database. No CLR code is loaded
        # or executed and no server trust/configuration is changed; only our user gains a row.
        if ($Scope -eq 'ASSEMBLY') { $scopeName = 'Microsoft.SqlServer.Types' }
        $quotedScopeName = '[' + $scopeName.Replace(']', ']]') + ']'
        $quotedScopeUser = '[' + $scopeUser.Replace(']', ']]') + ']'
        $scopePassword = 'Native!' + [guid]::NewGuid().ToString('N')
        $scopeCreated = $false
        try {
            $permissionDb.ExecuteNonQuery("CREATE USER $quotedScopeUser WITHOUT LOGIN;")
            switch ($Scope) {
                'FULLTEXT CATALOG' { $permissionDb.ExecuteNonQuery("CREATE FULLTEXT CATALOG $quotedScopeName;"); $scopeCreated = $true }
                'SYMMETRIC KEY' { $permissionDb.ExecuteNonQuery("CREATE SYMMETRIC KEY $quotedScopeName WITH ALGORITHM = AES_256 ENCRYPTION BY PASSWORD = '$scopePassword';"); $scopeCreated = $true }
                'CERTIFICATE' { $permissionDb.ExecuteNonQuery("CREATE CERTIFICATE $quotedScopeName ENCRYPTION BY PASSWORD = '$scopePassword' WITH SUBJECT = 'native permission fixture';"); $scopeCreated = $true }
                'ASYMMETRIC KEY' { $permissionDb.ExecuteNonQuery("CREATE ASYMMETRIC KEY $quotedScopeName WITH ALGORITHM = RSA_2048 ENCRYPTION BY PASSWORD = '$scopePassword';"); $scopeCreated = $true }
            }
            $scopeIdRows = @($permissionDb.ExecuteWithResults("SELECT $IdColumn AS Id FROM $Catalog WHERE name=N'$scopeName';").Tables[0].Rows)
            $scopeIdRows.Count | Should -Be 1
            $scopeId = [int]$scopeIdRows[0].Id
            $scopeCatalogSql = "SELECT class, major_id, permission_name, state_desc FROM sys.database_permissions WHERE grantee_principal_id=USER_ID(N'$scopeUser') AND class=$Class AND major_id=$scopeId;"
            foreach ($scopeState in 'GRANT', 'DENY', 'GRANT_WITH_GRANT_OPTION') {
                $scopeVerb = if ($scopeState -eq 'DENY') { 'DENY' } else { 'GRANT' }
                $scopeOption = if ($scopeState -eq 'GRANT_WITH_GRANT_OPTION') { ' WITH GRANT OPTION' } else { '' }
                $permissionDb.ExecuteNonQuery("$scopeVerb VIEW DEFINITION ON ${Scope}::$quotedScopeName TO $quotedScopeUser$scopeOption;")
                $scopeBefore = @($permissionDb.ExecuteWithResults($scopeCatalogSql).Tables[0].Rows | ForEach-Object { "$($PSItem.class)|$($PSItem.major_id)|$($PSItem.permission_name)|$($PSItem.state_desc)" })
                $scopeBefore | Should -BeExactly @("$Class|$scopeId|VIEW DEFINITION|$scopeState")
                $scopeRows = @(Get-DbaPermission @splatPermissionRead | Where-Object { $PSItem.Grantee -eq $scopeUser -and $PSItem.PermissionName -eq 'VIEW DEFINITION' })
                $scopeRows.Count | Should -Be 1
                $scopeRows[0].SecurableType | Should -BeExactly $Type
                $scopeRows[0].Securable | Should -BeExactly $scopeName
                $scopeRows[0].GrantStatement | Should -BeExactly "$scopeVerb VIEW DEFINITION ON ${Scope}::$quotedScopeName TO $quotedScopeUser$scopeOption"
                $scopeRows[0].RevokeStatement | Should -BeExactly "REVOKE VIEW DEFINITION ON ${Scope}::$quotedScopeName FROM $quotedScopeUser"
                $scopeRevoke = $scopeRows[0].RevokeStatement
                if ($scopeState -eq 'GRANT_WITH_GRANT_OPTION') { $scopeRevoke += ' CASCADE' }
                $permissionDb.ExecuteNonQuery($scopeRevoke)
                @($permissionDb.ExecuteWithResults($scopeCatalogSql).Tables[0].Rows).Count | Should -Be 0
                $permissionDb.ExecuteNonQuery($scopeRows[0].GrantStatement)
                $scopeAfter = @($permissionDb.ExecuteWithResults($scopeCatalogSql).Tables[0].Rows | ForEach-Object { "$($PSItem.class)|$($PSItem.major_id)|$($PSItem.permission_name)|$($PSItem.state_desc)" })
                $scopeAfter | Should -BeExactly $scopeBefore
                $permissionDb.ExecuteNonQuery($scopeRevoke)
            }
        } finally {
            $permissionDb.ExecuteNonQuery("IF USER_ID(N'$scopeUser') IS NOT NULL DROP USER $quotedScopeUser;")
            if ($scopeCreated) {
                $permissionDb.ExecuteNonQuery("DROP $Scope $quotedScopeName;")
                @($permissionDb.ExecuteWithResults("SELECT $IdColumn FROM $Catalog WHERE name=N'$scopeName';").Tables[0].Rows).Count | Should -Be 0
            }
            $permissionDb.ExecuteWithResults("SELECT USER_ID(N'$scopeUser') AS Id;").Tables[0].Rows[0].Id | Should -Be ([DBNull]::Value)
        }
    }

    It "renders executable server principal and endpoint permission scripts with their actual scope" {
        $serverToken = 'native_scope_' + [guid]::NewGuid().ToString('N')
        $scopeLogin = $serverToken + '_login]'
        $scopeRole = $serverToken + '_role]'
        $scopeTargetRole = $serverToken + '_target]'
        $quotedScopeLogin = '[' + $scopeLogin.Replace(']', ']]') + ']'
        $quotedScopeRole = '[' + $scopeRole.Replace(']', ']]') + ']'
        $quotedScopeTargetRole = '[' + $scopeTargetRole.Replace(']', ']]') + ']'
        $scopePassword = 'Native!' + [guid]::NewGuid().ToString('N')
        $permissionServer.ConnectionContext.ExecuteNonQuery('USE [master]') | Out-Null
        try {
            $permissionServer.ConnectionContext.ExecuteNonQuery("CREATE LOGIN $quotedScopeLogin WITH PASSWORD=N'$scopePassword', CHECK_POLICY=OFF; CREATE SERVER ROLE $quotedScopeRole; CREATE SERVER ROLE $quotedScopeTargetRole;") | Out-Null
            $scopeEndpoint = $permissionServer.ConnectionContext.ExecuteWithResults("SELECT TOP (1) endpoint_id, name FROM sys.endpoints WHERE type_desc=N'TSQL' ORDER BY endpoint_id;").Tables[0].Rows
            @($scopeEndpoint).Count | Should -Be 1
            $quotedScopeEndpoint = '[' + $scopeEndpoint[0].name.Replace(']', ']]') + ']'
            $permissionServer.ConnectionContext.ExecuteNonQuery("GRANT IMPERSONATE ON LOGIN::$quotedScopeLogin TO $quotedScopeRole; GRANT VIEW DEFINITION ON SERVER ROLE::$quotedScopeTargetRole TO $quotedScopeRole; GRANT VIEW DEFINITION ON ENDPOINT::$quotedScopeEndpoint TO $quotedScopeRole;") | Out-Null
            $scopeCatalogSql = "SELECT class, major_id, permission_name, state_desc FROM sys.server_permissions WHERE grantee_principal_id=SUSER_ID(N'$scopeRole') ORDER BY class, major_id, permission_name;"
            $scopeBefore = @($permissionServer.ConnectionContext.ExecuteWithResults($scopeCatalogSql).Tables[0].Rows | ForEach-Object { "$($PSItem.class)|$($PSItem.major_id)|$($PSItem.permission_name)|$($PSItem.state_desc)" })
            $scopeBefore.Count | Should -Be 3
            $scopeRows = @(Get-DbaPermission -SqlInstance $permissionServer -Database "${permissionPrefix}_absent" -IncludeServerLevel -EnableException | Where-Object Grantee -EQ $scopeRole)
            $scopeRows.Count | Should -Be 3
            foreach ($scopeRow in $scopeRows) {
                if ($scopeRow.PermissionName -eq 'IMPERSONATE') {
                    $scopeRow.SecurableType | Should -BeExactly 'SERVER_PRINCIPAL'
                    $scopeRow.Securable | Should -BeExactly $scopeLogin
                    $scopeClause = " ON LOGIN::$quotedScopeLogin"
                } elseif ($scopeRow.Securable -eq $scopeTargetRole) {
                    $scopeRow.PermissionName | Should -BeExactly 'VIEW DEFINITION'
                    $scopeRow.SecurableType | Should -BeExactly 'SERVER_PRINCIPAL'
                    $scopeClause = " ON SERVER ROLE::$quotedScopeTargetRole"
                } else {
                    $scopeRow.PermissionName | Should -BeExactly 'VIEW DEFINITION'
                    $scopeRow.SecurableType | Should -BeExactly 'ENDPOINT'
                    $scopeRow.Securable | Should -BeExactly $scopeEndpoint[0].name
                    $scopeClause = " ON ENDPOINT::$quotedScopeEndpoint"
                }
                $scopeRow.GrantStatement | Should -BeExactly ("GRANT " + $scopeRow.PermissionName + $scopeClause + " TO $quotedScopeRole")
                $scopeRow.RevokeStatement | Should -BeExactly ("REVOKE " + $scopeRow.PermissionName + $scopeClause + " FROM $quotedScopeRole")
                $permissionServer.ConnectionContext.ExecuteNonQuery($scopeRow.RevokeStatement) | Out-Null
                @($permissionServer.ConnectionContext.ExecuteWithResults($scopeCatalogSql).Tables[0].Rows).Count | Should -Be 2
                $permissionServer.ConnectionContext.ExecuteNonQuery($scopeRow.GrantStatement) | Out-Null
            }
            $scopeAfter = @($permissionServer.ConnectionContext.ExecuteWithResults($scopeCatalogSql).Tables[0].Rows | ForEach-Object { "$($PSItem.class)|$($PSItem.major_id)|$($PSItem.permission_name)|$($PSItem.state_desc)" })
            $scopeAfter | Should -BeExactly $scopeBefore
        } finally {
            $permissionServer.ConnectionContext.ExecuteNonQuery("IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name=N'$scopeRole') DROP SERVER ROLE $quotedScopeRole; IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name=N'$scopeTargetRole') DROP SERVER ROLE $quotedScopeTargetRole; IF SUSER_ID(N'$scopeLogin') IS NOT NULL DROP LOGIN $quotedScopeLogin;") | Out-Null
            $permissionServer.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.server_principals WHERE name IN (N'$scopeRole',N'$scopeTargetRole',N'$scopeLogin');") | Should -Be 0
        }
    }

}

Describe "Get-DbaPermission availability group scripts" -Tag IntegrationTests {
    # Installed nativeRoles scope supplies InstanceHadr only on the two SQL2022 legs.
    if ($TestConfig.InstanceHadr) {
        Context "availability group permission script scope" {
            BeforeAll {
                $permissionAgServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceHadr -EnableException
                $permissionAgServer.ConnectionContext.ExecuteNonQuery("USE [master]") | Out-Null
                $permissionAgLoginName = "native_permission_ag_" + [guid]::NewGuid().ToString("N")
                $permissionAgQuotedLogin = "[" + $permissionAgLoginName.Replace("]", "]]") + "]"
                $permissionAgPassword = "Native!" + [guid]::NewGuid().ToString("N")
                $permissionAgGroups = @($permissionAgServer.ConnectionContext.ExecuteWithResults("SELECT name FROM sys.availability_groups ORDER BY name;").Tables[0].Rows)
                if ($permissionAgGroups.Count -ne 1) { throw "Expected the one claimed availability group" }
                $permissionAgName = [string]$permissionAgGroups[0].name
                $permissionAgQuotedName = "[" + $permissionAgName.Replace("]", "]]") + "]"
                $permissionAgLogin = New-Object Microsoft.SqlServer.Management.Smo.Login -ArgumentList $permissionAgServer, $permissionAgLoginName
                $permissionAgLogin.LoginType = [Microsoft.SqlServer.Management.Smo.LoginType]::SqlLogin
                $permissionAgLogin.Create($permissionAgPassword)
                $permissionAgServer.ConnectionContext.ExecuteNonQuery("GRANT VIEW DEFINITION ON AVAILABILITY GROUP::$permissionAgQuotedName TO $permissionAgQuotedLogin") | Out-Null
                $permissionAgCatalogSql = "SELECT class, class_desc, major_id, permission_name, state_desc FROM sys.server_permissions WHERE grantee_principal_id=SUSER_ID(N'$permissionAgLoginName') AND class=108;"
            }

            AfterAll {
                if ($permissionAgServer -and $permissionAgLoginName) {
                    try {
                        $permissionAgServer.Logins.Refresh()
                        if ($permissionAgServer.Logins[$permissionAgLoginName]) { $permissionAgServer.Logins[$permissionAgLoginName].Drop() }
                        $permissionAgRemaining = $permissionAgServer.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.server_principals WHERE name=N'$permissionAgLoginName';")
                        if ($permissionAgRemaining -ne 0) { throw "Availability-group test login cleanup incomplete" }
                    } finally { $permissionAgServer.ConnectionContext.Disconnect() }
                }
            }

            It "renders and replays permission scripts for the actual availability group" {
                $permissionAgBefore = @($permissionAgServer.ConnectionContext.ExecuteWithResults($permissionAgCatalogSql).Tables[0].Rows)
                $permissionAgBefore.Count | Should -Be 1
                $permissionAgBefore[0].class | Should -Be 108
                $permissionAgBefore[0].class_desc | Should -BeExactly "AVAILABILITY GROUP"
                $permissionAgBefore[0].permission_name | Should -BeExactly "VIEW DEFINITION"
                $permissionAgBefore[0].state_desc | Should -BeExactly "GRANT"
                $splatPermissionAgRead = @{
                    SqlInstance        = $permissionAgServer
                    Database           = $permissionAgLoginName + "_absent"
                    IncludeServerLevel = $true
                    EnableException    = $true
                }
                $permissionAgRows = @(Get-DbaPermission @splatPermissionAgRead | Where-Object { $PSItem.Grantee -eq $permissionAgLoginName -and $PSItem.PermissionName -eq "VIEW DEFINITION" })
                $permissionAgRows.Count | Should -Be 1
                $permissionAgRows[0].SecurableType | Should -BeExactly $permissionAgBefore[0].class_desc
                $permissionAgRows[0].Securable | Should -BeExactly $permissionAgName
                $permissionAgRows[0].PermState | Should -BeExactly "GRANT"
                $permissionAgRows[0].GrantStatement | Should -BeExactly "GRANT VIEW DEFINITION ON AVAILABILITY GROUP::$permissionAgQuotedName TO $permissionAgQuotedLogin"
                $permissionAgRows[0].RevokeStatement | Should -BeExactly "REVOKE VIEW DEFINITION ON AVAILABILITY GROUP::$permissionAgQuotedName FROM $permissionAgQuotedLogin"
                $permissionAgServer.ConnectionContext.ExecuteNonQuery($permissionAgRows[0].RevokeStatement) | Out-Null
                @($permissionAgServer.ConnectionContext.ExecuteWithResults($permissionAgCatalogSql).Tables[0].Rows).Count | Should -Be 0
                $permissionAgServer.ConnectionContext.ExecuteNonQuery($permissionAgRows[0].GrantStatement) | Out-Null
                $permissionAgAfter = @($permissionAgServer.ConnectionContext.ExecuteWithResults($permissionAgCatalogSql).Tables[0].Rows)
                $permissionAgAfter.Count | Should -Be 1
                $permissionAgAfter[0].major_id | Should -Be $permissionAgBefore[0].major_id
                $permissionAgAfter[0].state_desc | Should -BeExactly "GRANT"
                $permissionAgAfter[0].permission_name | Should -BeExactly "VIEW DEFINITION"
            }
        }
    }
}

Describe "Get-DbaPermission SQL login" -Tag IntegrationTests, NativeChecklist:sql-login {
    It "reads master permissions using the supplied SQL credential" {
        $splatPermissionLogin = @{
            SqlInstance     = $TestConfig.InstanceSqlLogin
            SqlCredential   = $TestConfig.SqlLoginCred
            Database        = "master"
            EnableException = $true
        }
        $permissionLoginRows = @(Get-DbaPermission @splatPermissionLogin)
        $permissionLoginRows.Count | Should -BeGreaterThan 0
        @($permissionLoginRows.Database | Sort-Object -Unique) | Should -BeExactly @("master")
    }

    # Manager pin-sqllogin-20261111.txt: both editions warn with no rows, and EnableException also stops.
    It "warns and returns no rows without the required SQL credential" {
        $permissionLoginWarnings = @()
        $splatPermissionNoLogin = @{
            SqlInstance     = $TestConfig.InstanceSqlLogin
            Database        = "master"
            WarningVariable = "permissionLoginWarnings"
            WarningAction   = "SilentlyContinue"
        }
        @(Get-DbaPermission @splatPermissionNoLogin).Count | Should -Be 0
        ($permissionLoginWarnings -join " ") | Should -BeLike "*Failure*Login failed*"
        { Get-DbaPermission @splatPermissionNoLogin -EnableException } | Should -Throw
    }
}

Describe "Get-DbaPermission Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $splatPermissionAzureConnect = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            ConnectTimeout  = 60
            EnableException = $true
        }
        for ($permissionAzureAttempt = 0; $permissionAzureAttempt -le 6; $permissionAzureAttempt++) {
            try {
                $permissionAzureServer = Connect-DbaInstance @splatPermissionAzureConnect
                break
            } catch {
                $permissionAzureFailure = $PSItem.Exception
                $permissionAzureResuming = $false
                while ($permissionAzureFailure) {
                    if ($permissionAzureFailure.Number -in 40613, -2 -or $permissionAzureFailure.NativeErrorCode -eq 258 -or $permissionAzureFailure.Message -match "timeout|timed out") { $permissionAzureResuming = $true }
                    $permissionAzureFailure = $permissionAzureFailure.InnerException
                }
                if (-not $permissionAzureResuming -or $permissionAzureAttempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        $permissionAzureUser = "native_permission_" + [Guid]::NewGuid().ToString("N")
        $permissionAzureServer.ConnectionContext.ExecuteNonQuery("CREATE USER [$permissionAzureUser] WITHOUT LOGIN; GRANT VIEW DEFINITION TO [$permissionAzureUser];") | Out-Null
    }

    AfterAll {
        if ($permissionAzureServer -and $permissionAzureUser) {
            $permissionAzureServer.ConnectionContext.ExecuteNonQuery("DROP USER [$permissionAzureUser]") | Out-Null
        }
    }

    It "returns real database permissions and warns when server permissions are requested" -Tag NativeChecklist:azure-sqldb {
        $permissionAzureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $permissionAzureWarnings = @()
        $splatPermissionAzureRead = @{
            SqlInstance        = $permissionAzureServer
            Database           = $TestConfig.AzureSqlDbName
            IncludeServerLevel = $true
            EnableException    = $true
            WarningVariable    = "permissionAzureWarnings"
            WarningAction      = "SilentlyContinue"
        }
        $permissionAzureRows = @(Get-DbaPermission @splatPermissionAzureRead)
        @($permissionAzureRows | Where-Object { $PSItem.Grantee -eq $permissionAzureUser -and $PSItem.PermissionName -eq "VIEW DEFINITION" -and $PSItem.PermState -eq "GRANT" }).Count | Should -Be 1
        @($permissionAzureRows.Database | Sort-Object -Unique) | Should -BeExactly @($TestConfig.AzureSqlDbName)
        ($permissionAzureWarnings -join " ") | Should -BeLike "*Server-level permissions are not supported on Azure SQL Database. Skipping -IncludeServerLevel.*"
    }
}

Describe "Get-DbaPermission statement faults" -Tag IntegrationTests {
    BeforeAll {
        $permissionFaultAdmin = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $permissionFaultName = "native_permission_fault_" + [Guid]::NewGuid().ToString("N")
        $permissionFaultPassword = "A!8x" + [Guid]::NewGuid().ToString("N")
        $permissionFaultLogin = New-Object Microsoft.SqlServer.Management.Smo.Login -ArgumentList $permissionFaultAdmin, $permissionFaultName
        $permissionFaultLogin.LoginType = [Microsoft.SqlServer.Management.Smo.LoginType]::SqlLogin
        $permissionFaultLogin.Create($permissionFaultPassword)
        $permissionFaultMaster = $permissionFaultAdmin.Databases["master"]
        $permissionFaultUser = New-Object Microsoft.SqlServer.Management.Smo.User -ArgumentList $permissionFaultMaster, $permissionFaultName
        $permissionFaultUser.Login = $permissionFaultName
        $permissionFaultUser.Create()
        $permissionFaultType = (Get-Command Get-DbaPermission -CommandType Cmdlet).ImplementingType

        # Each call has its own runspace, so Pester's caller try cannot change the plain-call behavior.
        function Invoke-PermissionFaultCase {
            param($Server, [string]$Mode, [string]$Site)
            $permissionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $permissionEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaPermission", $permissionFaultType, $null
            $permissionState.Commands.Add($permissionEntry)
            $permissionRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($permissionState)
            $permissionShell = [System.Management.Automation.PowerShell]::Create()
            $permissionOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
            $permissionStop = $null
            try {
                $permissionRunspace.Open()
                $permissionShell.Runspace = $permissionRunspace
                $null = $permissionShell.AddScript(@'
param($Server, $Mode, $Site)
$ErrorActionPreference = "Continue"
$Error.Clear()
$global:NativePermissionErrors = @()
$splatFault = @{ SqlInstance = $Server; Database = "master"; EnableException = $false; ErrorVariable = "+global:NativePermissionErrors" }
if ($Site -eq "query") { $splatFault.IncludeServerLevel = $true }
if ($Mode -eq "enabled") { $splatFault.EnableException = $true }
if ($Mode -eq "stop") { $splatFault.ErrorAction = "Stop" }
if ($Mode -eq "silent") { $splatFault.ErrorAction = "SilentlyContinue" }
if ($Mode -eq "try") {
    try {
        Get-DbaPermission @splatFault
        "inside-next"
    } catch {
        [pscustomobject]@{ Caught = $PSItem }
    }
} else {
    Get-DbaPermission @splatFault
}
"next"
'@).AddArgument($Server).AddArgument($Mode).AddArgument($Site)
                try { $null = $permissionShell.Invoke($null, $permissionOutput) } catch { $permissionStop = $PSItem.Exception.InnerException }
                [pscustomobject]@{
                    Rows     = @($permissionOutput | Where-Object { $PSItem -is [System.Data.DataRow] })
                    Errors   = @($permissionShell.Streams.Error)
                    Warnings = @($permissionShell.Streams.Warning)
                    Caught   = @($permissionOutput | Where-Object { $null -ne $PSItem.PSObject.Properties["Caught"] } | ForEach-Object Caught)
                    Markers  = @($permissionOutput | Where-Object { $PSItem -is [string] })
                    Stop     = $permissionStop
                    History  = @($permissionRunspace.SessionStateProxy.GetVariable("Error"))
                    ErrorVariable = @($permissionRunspace.SessionStateProxy.GetVariable("NativePermissionErrors"))
                }
            } finally {
                $permissionShell.Dispose()
                $permissionRunspace.Dispose()
                $permissionOutput.Dispose()
            }
        }
    }

    AfterAll {
        if ($permissionFaultAdmin) {
            try {
                $permissionFaultMaster = $permissionFaultAdmin.Databases["master"]
                $permissionFaultMaster.Users.Refresh()
                if ($permissionFaultMaster.Users[$permissionFaultName]) { $permissionFaultMaster.Users[$permissionFaultName].Drop() }
            } finally {
                $permissionFaultAdmin.Logins.Refresh()
                if ($permissionFaultAdmin.Logins[$permissionFaultName]) { $permissionFaultAdmin.Logins[$permissionFaultName].Drop() }
            }
            $permissionFaultMaster.Users.Refresh()
            $permissionFaultAdmin.Logins.Refresh()
            $permissionFaultMaster.Users[$permissionFaultName] | Should -BeNullOrEmpty
            $permissionFaultAdmin.Logins[$permissionFaultName] | Should -BeNullOrEmpty
        }
    }

    # Paired probe paired-engine-records-r2-ar-20261112.txt measured complete channels and
    # causal chains on both editions. Keep-going governs EnableException and ErrorAction Stop;
    # the installed engine-record rule governs the unfiltered native EV/history sequences.
    It "preserves the measured error and caller flow at the <Site> site" -TestCases @(
        @{ Site = "query"; View = "sys.server_permissions"; ErrorId = "ScriptMethodRuntimeException"; PlainErrors = 1 }
        @{ Site = "enumeration"; View = "sys.databases"; ErrorId = "ExceptionInGetEnumerator"; PlainErrors = 2 }
    ) {
        param($Site, $View, $ErrorId, $PlainErrors)
        $permissionFaultMaster.ExecuteNonQuery("DENY SELECT ON OBJECT::$View TO [$permissionFaultName]")
        try {
            foreach ($permissionMode in @("plain", "enabled", "stop", "try", "silent")) {
                # Catalog-denial tests use the lane's Windows connection; SQL authentication is
                # tested separately on InstanceSqlLogin and is not required on every pool instance.
                $permissionFaultConnection = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection -EnableException
                $permissionFresh = New-Object Microsoft.SqlServer.Management.Smo.Server -ArgumentList ($permissionFaultConnection.ConnectionContext.Copy())
                $permissionImpersonating = $false
                try {
                    $permissionOriginalLogin = $permissionFresh.ConnectionContext.ExecuteScalar("SELECT ORIGINAL_LOGIN()")
                    $permissionFresh.ConnectionContext.ExecuteNonQuery("EXECUTE AS LOGIN = N'" + $permissionFaultName.Replace("'", "''") + "'") | Out-Null
                    $permissionImpersonating = $true
                    $permissionFresh.ConnectionContext.ExecuteScalar("SELECT SUSER_SNAME()") | Should -BeExactly $permissionFaultName
                    $permissionCase = Invoke-PermissionFaultCase -Server $permissionFresh -Mode $permissionMode -Site $Site
                    $permissionCase.Warnings.Count | Should -Be 0
                    if ($permissionMode -in @("plain", "silent") -and $Site -eq "query") {
                        $permissionCase.Rows.Count | Should -BeGreaterThan 0
                        @($permissionCase.Rows.Database | Sort-Object -Unique) | Should -BeExactly @("master")
                    } else {
                        $permissionCase.Rows.Count | Should -Be 0
                    }
                    $permissionRecords = @($permissionCase.Errors)
                    if ($permissionMode -eq "stop") {
                        $permissionCase.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
                        $permissionCase.Errors.Count | Should -Be 0
                        $permissionCase.Caught.Count | Should -Be 0
                        $permissionCase.Markers.Count | Should -Be 0
                        $permissionRecords = @($permissionCase.Stop.ErrorRecord)
                    } else {
                        $permissionCase.Stop | Should -BeNullOrEmpty
                        $permissionCase.Markers | Should -BeExactly @("next")
                        if ($permissionMode -eq "try") {
                            $permissionCase.Errors.Count | Should -Be 0
                            $permissionCase.Caught.Count | Should -Be 1
                            $permissionRecords = @($permissionCase.Caught)
                        } else {
                            $permissionCase.Caught.Count | Should -Be 0
                            $permissionCase.Errors.Count | Should -Be $(if ($permissionMode -eq "plain") { $PlainErrors } elseif ($permissionMode -eq "silent") { 0 } else { 1 })
                        }
                    }
                    # Installed engine-record rule: no filtering of repeated records or wrappers.
                    $permissionBareType = "System.Management.Automation.ErrorRecord"
                    $permissionInvocationType = "System.Management.Automation.CmdletInvocationException"
                    $permissionPreferenceType = "System.Management.Automation.ActionPreferenceStopException"
                    $permissionHistoryTypes = @($permissionBareType)
                    $permissionVariableTypes = @($permissionInvocationType)
                    if ($permissionMode -in @("plain", "silent")) {
                        $permissionHistoryTypes = @($permissionBareType) * $PlainErrors
                        $permissionVariableTypes = @($permissionBareType) * $PlainErrors
                    } elseif ($permissionMode -eq "stop") {
                        $permissionHistoryTypes = @($permissionPreferenceType, $permissionBareType)
                        $permissionVariableTypes = @($permissionPreferenceType)
                    }
                    foreach ($permissionChannel in @("History", "ErrorVariable")) {
                        $permissionExpectedTypes = if ($permissionChannel -eq "History") { $permissionHistoryTypes } else { $permissionVariableTypes }
                        $permissionEntries = @($permissionCase.$permissionChannel)
                        $permissionEntries.Count | Should -Be @($permissionExpectedTypes).Count
                        for ($permissionIndex = 0; $permissionIndex -lt $permissionEntries.Count; $permissionIndex++) {
                            $permissionEntry = $permissionEntries[$permissionIndex]
                            $permissionEntry.GetType().FullName | Should -BeExactly @($permissionExpectedTypes)[$permissionIndex]
                            $permissionChannelRecord = if ($permissionEntry -is [System.Management.Automation.ErrorRecord]) { $permissionEntry } else { $permissionEntry.ErrorRecord }
                            $permissionChannelRecord.FullyQualifiedErrorId | Should -BeExactly ($ErrorId + "," + $permissionFaultType.FullName)
                            $permissionRecords += $permissionChannelRecord
                        }
                    }
                    foreach ($permissionRecord in $permissionRecords) {
                        # The sole allowed owner difference is this registered command's native implementing type.
                        $permissionRecord.FullyQualifiedErrorId | Should -BeExactly ($ErrorId + "," + $permissionFaultType.FullName)
                        $permissionRecord.CategoryInfo.Category.ToString() | Should -BeExactly "NotSpecified"
                        $permissionRecord.CategoryInfo.Activity | Should -BeExactly "Get-DbaPermission"
                        $permissionRecord.CategoryInfo.Reason | Should -BeExactly $permissionRecord.Exception.GetType().Name
                        $permissionRecord.CategoryInfo.TargetName | Should -BeExactly ""
                        $permissionRecord.CategoryInfo.TargetType | Should -BeExactly ""
                        ($null -eq $permissionRecord.TargetObject) | Should -BeTrue
                        ($null -eq $permissionRecord.ErrorDetails) | Should -BeTrue
                        if ($Site -eq "query") {
                            $permissionRecord.Exception.GetType().FullName | Should -BeExactly "System.Management.Automation.MethodInvocationException"
                            $permissionRecord.Exception.InnerException.GetType().FullName | Should -BeExactly "System.Management.Automation.RuntimeException"
                            $permissionRecord.Exception.InnerException.InnerException.GetType().FullName | Should -BeExactly "System.Management.Automation.RuntimeException"
                            $permissionRecord.Exception.HResult | Should -Be -2146233087
                            $permissionRecord.Exception.InnerException.HResult | Should -Be -2146233087
                            $permissionRecord.Exception.InnerException.InnerException.HResult | Should -Be -2146233087
                            $permissionRecord.Exception.InnerException.InnerException.InnerException | Should -BeNullOrEmpty
                            $permissionQueryMessage = "An exception occurred while executing a Transact-SQL statement or batch.The SELECT permission was denied on the object 'server_permissions', database 'mssqlsystemresource', schema 'sys'."
                            $permissionRecord.Exception.InnerException.Message | Should -BeExactly $permissionQueryMessage
                            $permissionRecord.Exception.InnerException.InnerException.Message | Should -BeExactly $permissionQueryMessage
                            $permissionRecord.Exception.Message | Should -BeExactly ('Exception calling "Query" with "1" argument(s): "' + $permissionQueryMessage + '"')
                        } else {
                            $permissionRecord.Exception.GetType().FullName | Should -BeExactly "System.Management.Automation.ExtendedTypeSystemException"
                            $permissionRecord.Exception.Message | Should -BeExactly 'The following exception occurred while trying to enumerate the collection: "Failed to retrieve data for this request.".'
                            $permissionRecord.Exception.InnerException.GetType().FullName | Should -BeExactly "Microsoft.SqlServer.Management.Sdk.Sfc.EnumeratorException"
                            $permissionRecord.Exception.InnerException.Message | Should -BeExactly "Failed to retrieve data for this request."
                            $permissionRecord.Exception.InnerException.InnerException.GetType().FullName | Should -BeExactly "Microsoft.SqlServer.Management.Common.ExecutionFailureException"
                            $permissionRecord.Exception.InnerException.InnerException.Message | Should -BeExactly "An exception occurred while executing a Transact-SQL statement or batch."
                            $permissionRecord.Exception.InnerException.InnerException.InnerException.GetType().FullName | Should -BeExactly "Microsoft.Data.SqlClient.SqlException"
                            $permissionRecord.Exception.InnerException.InnerException.InnerException.Message | Should -BeExactly "The SELECT permission was denied on the object 'databases', database 'mssqlsystemresource', schema 'sys'."
                            $permissionRecord.Exception.HResult | Should -Be -2146233087
                            $permissionRecord.Exception.InnerException.HResult | Should -Be -2146233088
                            $permissionRecord.Exception.InnerException.InnerException.HResult | Should -Be -2146233088
                            $permissionRecord.Exception.InnerException.InnerException.InnerException.HResult | Should -Be -2146232060
                            $permissionRecord.Exception.InnerException.InnerException.InnerException.InnerException | Should -BeNullOrEmpty
                        }
                    }
                } finally {
                    try {
                        if ($permissionImpersonating) {
                            $permissionFresh.ConnectionContext.ExecuteNonQuery("REVERT") | Out-Null
                            $permissionFresh.ConnectionContext.ExecuteScalar("SELECT SUSER_SNAME()") | Should -BeExactly $permissionOriginalLogin
                        }
                    } finally {
                        $permissionFresh.ConnectionContext.Disconnect()
                        $permissionFaultConnection.ConnectionContext.Disconnect()
                    }
                }
            }
        } finally {
            $permissionFaultMaster.ExecuteNonQuery("REVOKE SELECT ON OBJECT::$View FROM [$permissionFaultName]")
        }
    }
}
