#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaUserPermission",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned function declares no SupportsShouldProcess, so it has no -WhatIf or -Confirm; its tempdb objects are working state it drops again
# NativeChecklist: azure-sqldb N/A -- the pinned connect's -AzureUnsupported is kept: the command builds views in tempdb over master.sys.syslogins and [<database>].sys.* of every database, and Azure SQL Database supports no cross-database three-part names beyond tempdb and the current database (https://learn.microsoft.com/azure/azure-sql/database/transact-sql-tsql-differences-sql-server?view=azuresql#t-sql-syntax-not-supported-in-azure-sql-database), so Azure support would be a rewrite of the command

BeforeAll {
    # The SQL-login instance is shared by every leg of every run. This command builds and drops objects in its tempdb, so each
    # leg's SQL-login block runs under one exclusive session lock there. Nothing retries or catches an error: a lock that is
    # not granted fails the block's setup.
    $upLockResource = "dbatools-native-userpermission-sqllogin"
    function Enter-NativeSqlLoginLock {
        $splatLock = @{
            SqlInstance         = $TestConfig.InstanceSqlLogin
            SqlCredential       = $TestConfig.SqlLoginCred
            Database            = "master"
            NonPooledConnection = $true
            ClientName          = "native-up-lock-" + [guid]::NewGuid().ToString("N")
            EnableException     = $true
        }
        $lockServer = Connect-DbaInstance @splatLock
        $lockServer.ConnectionContext.AutoDisconnectMode = [Microsoft.SqlServer.Management.Common.AutoDisconnectMode]::NoAutoDisconnect
        $lockServer.ConnectionContext.StatementTimeout = 660
        $lockServer.ConnectionContext.Connect()
        $lockResult = [int]$lockServer.ConnectionContext.ExecuteScalar("DECLARE @result int; EXEC @result = master.sys.sp_getapplock @Resource = N'$upLockResource', @LockMode = N'Exclusive', @LockOwner = N'Session', @LockTimeout = 600000; SELECT @result;")
        if ($lockResult -lt 0) {
            $lockServer.ConnectionContext.Disconnect()
            throw "sp_getapplock returned $lockResult for $upLockResource on $($TestConfig.InstanceSqlLogin)"
        }
        $lockServer
    }
    function Exit-NativeSqlLoginLock($LockServer) {
        if (-not $LockServer) { return }
        try {
            $unlockResult = [int]$LockServer.ConnectionContext.ExecuteScalar("DECLARE @result int; EXEC @result = master.sys.sp_releaseapplock @Resource = N'$upLockResource', @LockOwner = N'Session'; SELECT @result;")
            $unlockResult | Should -Be 0
        } finally {
            # Ending the session releases the lock in any case.
            $LockServer.ConnectionContext.Disconnect()
        }
    }

    # Users, a role with two members, and explicit grants: SELECT on a table to bob and to public, VIEW DEFINITION on the
    # database to bob.
    $upFixtureSql = @"
CREATE USER [alice] WITHOUT LOGIN;
CREATE USER [bob] WITHOUT LOGIN;
CREATE ROLE [userrole] AUTHORIZATION dbo;
ALTER ROLE [userrole] ADD MEMBER [alice];
ALTER ROLE [userrole] ADD MEMBER [bob];
CREATE TABLE dbo.nup_table (id int);
GRANT SELECT ON dbo.nup_table TO [bob];
GRANT SELECT ON dbo.nup_table TO public;
GRANT VIEW DEFINITION TO [bob];
"@
    function New-NativeUpDatabase($Server, $Name) {
        $newDb = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $Server, $Name
        $newDb.Create()
        $newDb.ExecuteNonQuery($upFixtureSql)
    }
    function Remove-NativeUpDatabase($Server, $Name) {
        $Server.Databases.Refresh()
        if ($Server.Databases[$Name]) {
            $Server.KillDatabase($Name)
        }
    }
}

Describe "Native Get-DbaUserPermission" -Tag IntegrationTests {
    BeforeAll {
        $upPrefix = "dbatoolsci_nup_" + [guid]::NewGuid().ToString("N").Substring(0, 8)
        $upDbName = "${upPrefix}_a"
        $upOtherName = "${upPrefix}_o"
        $upBracketName = "${upPrefix}_b]x"
        $upQuoteName = "${upPrefix}_c'q"
        $upServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        foreach ($upName in @($upDbName, $upOtherName, $upBracketName, $upQuoteName)) {
            New-NativeUpDatabase $upServer $upName
        }
        $upServer.Databases.Refresh()
        $upBadInstance = 'Data Source=localhost,1;Initial Catalog=master;Integrated Security=True;Connect Timeout=1;Encrypt=False'
        $upProperties = "ComputerName,InstanceName,SqlInstance,Object,Type,Member,RoleSecurableClass,SchemaOwner,Securable,GranteeType,Grantee,Permission,State,Grantor,GrantorType,SourceView"
    }

    AfterAll {
        foreach ($upName in @($upDbName, $upOtherName, $upBracketName, $upQuoteName)) {
            Remove-NativeUpDatabase $upServer $upName
        }
        $upServer.ConnectionContext.Disconnect()
    }

    It "returns the server rows and the database's role members and grants, in the pinned shape" {
        $results = @(Get-DbaUserPermission -SqlInstance $TestConfig.InstanceSingle -Database $upDbName -WarningVariable warnings -WarningAction SilentlyContinue)
        @($warnings).Count | Should -Be 0
        ($results[0].PSObject.Properties.Name -join ",") | Should -BeExactly $upProperties
        $results[0].PSObject.TypeNames[0] | Should -BeExactly "System.Management.Automation.PSCustomObject"
        @($results | Where-Object Object -notin "SERVER", $upDbName).Count | Should -Be 0
        @($results | Where-Object { $PSItem.Object -eq "SERVER" -and $PSItem.Type -eq "SERVER LOGINS" }).Count | Should -BeGreaterThan 0
        @($results | Where-Object { $PSItem.Object -eq "SERVER" -and $PSItem.Type -eq "SERVER SECURABLES" }).Count | Should -BeGreaterThan 0
        $results[0].SqlInstance | Should -Be $upServer.DomainInstanceName
        $results[0].InstanceName | Should -Be $upServer.ServiceName
        $members = @($results | Where-Object { $PSItem.Object -eq $upDbName -and $PSItem.Type -eq "DB ROLE MEMBERS" -and $PSItem.RoleSecurableClass -eq "userrole" })
        @($members.Member | Sort-Object) -join "," | Should -BeExactly "alice,bob"
        $grant = @($results | Where-Object { $PSItem.Object -eq $upDbName -and $PSItem.Type -eq "DB SECURABLES" -and $PSItem.Grantee -eq "bob" -and $PSItem.Permission -eq "SELECT" })
        $grant.Count | Should -BeGreaterThan 0
        $grant[0].State | Should -BeExactly "GRANT"
        $grant[0].SchemaOwner | Should -BeExactly "dbo"
        @($results | Where-Object { $PSItem.Type -eq "DB SECURABLES" -and $PSItem.Grantee -in "public", "guest" }).Count | Should -Be 0
    }

    It "returns only the role members with -ExcludeSecurables, and the grants with -ExcludeSecurables:`$false" -Tag "NativeChecklist:switch-false" {
        $excluded = @(Get-DbaUserPermission -SqlInstance $TestConfig.InstanceSingle -Database $upDbName -ExcludeSecurables)
        @($excluded.Type | Sort-Object -Unique) -join "," | Should -BeExactly "DB ROLE MEMBERS,SERVER LOGINS"
        $included = @(Get-DbaUserPermission -SqlInstance $TestConfig.InstanceSingle -Database $upDbName -ExcludeSecurables:$false)
        @($included | Where-Object Type -eq "DB SECURABLES").Count | Should -BeGreaterThan 0
        @($included | Where-Object Type -eq "SERVER SECURABLES").Count | Should -BeGreaterThan 0
    }

    It "adds the public and guest grants with -IncludePublicGuest, and not with -IncludePublicGuest:`$false" -Tag "NativeChecklist:switch-false" {
        $public = @(Get-DbaUserPermission -SqlInstance $TestConfig.InstanceSingle -Database $upDbName -IncludePublicGuest)
        @($public | Where-Object { $PSItem.Type -eq "DB SECURABLES" -and $PSItem.Grantee -eq "public" -and $PSItem.Permission -eq "SELECT" }).Count | Should -BeGreaterThan 0
        $plain = @(Get-DbaUserPermission -SqlInstance $TestConfig.InstanceSingle -Database $upDbName -IncludePublicGuest:$false -IncludeSystemObjects:$false)
        @($plain | Where-Object { $PSItem.Type -eq "DB SECURABLES" -and $PSItem.Grantee -eq "public" }).Count | Should -Be 0
        @($plain | Where-Object { $PSItem.Type -eq "DB SECURABLES" -and $PSItem.SchemaOwner -eq "sys" }).Count | Should -Be 0
    }

    It "applies -ExcludeDatabase, and -ExcludeSystemDatabase only when it is set" -Tag "NativeChecklist:switch-false" {
        $results = @(Get-DbaUserPermission -SqlInstance $TestConfig.InstanceSingle -Database $upDbName, $upOtherName -ExcludeDatabase $upOtherName.ToUpperInvariant())
        @($results | Where-Object Object -ne "SERVER" | Select-Object -ExpandProperty Object -Unique) -join "," | Should -BeExactly $upDbName
        $system = @(Get-DbaUserPermission -SqlInstance $TestConfig.InstanceSingle -Database model, $upDbName -ExcludeSystemDatabase -ExcludeSecurables)
        @($system | Where-Object Object -ne "SERVER" | Select-Object -ExpandProperty Object -Unique) -join "," | Should -BeExactly $upDbName
        $all = @(Get-DbaUserPermission -SqlInstance $TestConfig.InstanceSingle -Database model, $upDbName -ExcludeSystemDatabase:$false -ExcludeSecurables)
        @($all | Where-Object Object -ne "SERVER" | Select-Object -ExpandProperty Object -Unique | Sort-Object) -join "," | Should -BeExactly (@($upDbName, "model") -join ",")
    }

    It "reads each -SqlInstance and each piped instance once" -Tag "NativeChecklist:pipeline-multiple" {
        $single = @(Get-DbaUserPermission -SqlInstance $TestConfig.InstanceSingle -Database $upDbName -ExcludeSecurables)
        $bound = @(Get-DbaUserPermission -SqlInstance $TestConfig.InstanceSingle, $TestConfig.InstanceSingle -Database $upDbName -ExcludeSecurables)
        $piped = @($TestConfig.InstanceSingle, $TestConfig.InstanceSingle | Get-DbaUserPermission -Database $upDbName -ExcludeSecurables)
        $single.Count | Should -BeGreaterThan 0
        $bound.Count | Should -Be (2 * $single.Count)
        $piped.Count | Should -Be (2 * $single.Count)
    }

    It "warns for an instance it cannot connect and goes on to the next with EnableException false" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $results = @(@($upBadInstance, $TestConfig.InstanceSingle) | Get-DbaUserPermission -Database $upDbName -ExcludeSecurables -EnableException:$false -WarningVariable warnings -WarningAction SilentlyContinue)
        @($warnings).Count | Should -BeGreaterThan 0
        (@($warnings) -join " ") | Should -Match "Failure"
        @($results | Where-Object Object -eq $upDbName).Count | Should -BeGreaterThan 0
    }

    It "stops at an instance it cannot connect with EnableException, keeping the earlier instance's rows" -Tag "NativeChecklist:enable-exception", "NativeChecklist:multi-instance-failure" {
        $output = New-Object System.Collections.ArrayList
        $failure = $null
        try {
            @($TestConfig.InstanceSingle, $upBadInstance) | Get-DbaUserPermission -Database $upDbName -ExcludeSecurables -EnableException -WarningAction SilentlyContinue | ForEach-Object { $null = $output.Add($PSItem) }
        } catch {
            $failure = $PSItem
        }
        $failure | Should -Not -BeNullOrEmpty
        @($output | Where-Object Object -eq $upDbName).Count | Should -BeGreaterThan 0
    }

    It "returns the rows of a database whose name holds a closing bracket, without a warning" {
        $results = @(Get-DbaUserPermission -SqlInstance $TestConfig.InstanceSingle -Database $upBracketName -WarningVariable warnings -WarningAction SilentlyContinue)
        @($warnings).Count | Should -Be 0
        $members = @($results | Where-Object { $PSItem.Object -eq $upBracketName -and $PSItem.Type -eq "DB ROLE MEMBERS" -and $PSItem.RoleSecurableClass -eq "userrole" })
        @($members.Member | Sort-Object) -join "," | Should -BeExactly "alice,bob"
    }

    It "names the database in the SourceView of a grant whose class the STIG view does not list" {
        # bin/stig.sql:283-316 names a catalog view for each listed class (DATABASE gives sys.databases) and gives every other
        # class, such as a database scoped credential, '<QUOTETARGETDB>.sys.database_permissions'. That row's Schema/Owner is
        # NULL, so only -IncludeSystemObjects keeps it.
        $upSecret = "Nup" + [guid]::NewGuid().ToString("N") + "!aA1"
        foreach ($name in @($upDbName, $upQuoteName)) {
            $upServer.Databases[$name].ExecuteNonQuery("CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'$upSecret'; CREATE DATABASE SCOPED CREDENTIAL [nup_credential] WITH IDENTITY = N'dbatoolsci', SECRET = N'$upSecret'; GRANT CONTROL ON DATABASE SCOPED CREDENTIAL::[nup_credential] TO [bob];")
            $results = @(Get-DbaUserPermission -SqlInstance $TestConfig.InstanceSingle -Database $name -IncludeSystemObjects -WarningVariable warnings -WarningAction SilentlyContinue)
            @($warnings).Count | Should -Be 0
            $bobGrants = @($results | Where-Object { $PSItem.Object -eq $name -and $PSItem.Type -eq "DB SECURABLES" -and $PSItem.Grantee -eq "bob" })
            $credential = @($bobGrants | Where-Object { $PSItem.RoleSecurableClass -like "*CREDENTIAL*" -and $PSItem.Permission -eq "CONTROL" })
            $credential.Count | Should -BeGreaterThan 0
            foreach ($row in $credential) {
                $row.SourceView | Should -BeExactly "$name.sys.database_permissions"
            }
            # A listed class keeps its own catalog view, as the pin reports it.
            $database = @($bobGrants | Where-Object RoleSecurableClass -eq "DATABASE")
            $database.Count | Should -BeGreaterThan 0
            foreach ($row in $database) {
                $row.SourceView | Should -BeExactly "sys.databases"
            }
        }
    }

    It "selects databases by a -Database wildcard pattern, as its help documents" {
        $results = @(Get-DbaUserPermission -SqlInstance $TestConfig.InstanceSingle -Database "${upPrefix}_a*" -ExcludeSecurables)
        @($results | Where-Object Object -ne "SERVER" | Select-Object -ExpandProperty Object -Unique) -join "," | Should -BeExactly $upDbName
    }

    Context "tempdb objects of another session" {
        BeforeAll {
            # What another caller's run leaves in tempdb while it reads: a STIG schema with one of the pinned views.
            $upTempdb = $upServer.Databases["tempdb"]
            $upTempdb.ExecuteNonQuery("IF SCHEMA_ID(N'STIG') IS NULL EXEC (N'CREATE SCHEMA STIG');")
            $upTempdb.ExecuteNonQuery("IF OBJECT_ID(N'STIG.server_role_members') IS NULL EXEC (N'CREATE VIEW STIG.server_role_members AS SELECT CAST(N''dbatoolsci_keep'' AS sysname) AS [Role], CAST(N''dbatoolsci_keep'' AS sysname) AS [Member]');")
        }

        AfterAll {
            $upTempdb.ExecuteNonQuery("IF OBJECT_ID(N'STIG.server_role_members') IS NOT NULL DROP VIEW STIG.server_role_members;")
            $upTempdb.ExecuteNonQuery("IF SCHEMA_ID(N'STIG') IS NOT NULL EXEC (N'DROP SCHEMA STIG');")
        }

        It "leaves another session's tempdb STIG objects in place" {
            $results = @(Get-DbaUserPermission -SqlInstance $TestConfig.InstanceSingle -Database $upDbName -ExcludeSecurables -WarningVariable warnings -WarningAction SilentlyContinue)
            @($warnings).Count | Should -Be 0
            @($results | Where-Object Object -eq $upDbName).Count | Should -BeGreaterThan 0
            $kept = $upTempdb.ExecuteWithResults("SELECT [Member] FROM STIG.server_role_members;").Tables[0].Rows
            @($kept).Count | Should -Be 1
            $kept[0].Member | Should -BeExactly "dbatoolsci_keep"
        }
    }

    It "leaves no schema of its own in tempdb" {
        $null = Get-DbaUserPermission -SqlInstance $TestConfig.InstanceSingle -Database $upDbName -ExcludeSecurables
        [int]$upServer.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM tempdb.sys.schemas WHERE name LIKE N'STIG[_]%' OR name = N'STIG';") | Should -Be 0
    }
}

Describe "Native Get-DbaUserPermission over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            # The lock is held from before the database is created until after it is dropped.
            $loginLock = Enter-NativeSqlLoginLock
            # Unique per leg and run: the instance is shared.
            $loginDbName = "dbatoolsci_nupsql_" + [guid]::NewGuid().ToString("N").Substring(0, 8)
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            New-NativeUpDatabase $loginServer $loginDbName
        }
        AfterAll {
            try {
                Remove-NativeUpDatabase $loginServer $loginDbName
                $loginServer.ConnectionContext.Disconnect()
            } finally {
                Exit-NativeSqlLoginLock $loginLock
            }
        }

        It "works with -SqlCredential" {
            $results = @(Get-DbaUserPermission -SqlInstance $loginInstance -SqlCredential $loginCred -Database $loginDbName -EnableException)
            $members = @($results | Where-Object { $PSItem.Object -eq $loginDbName -and $PSItem.Type -eq "DB ROLE MEMBERS" -and $PSItem.RoleSecurableClass -eq "userrole" })
            @($members.Member | Sort-Object) -join "," | Should -BeExactly "alice,bob"
            @($results | Where-Object Object -eq "SERVER").Count | Should -BeGreaterThan 0
        }

        It "fails cleanly without the credential: a warning and no output" {
            $results = Get-DbaUserPermission -SqlInstance $loginInstance -Database $loginDbName -WarningVariable warnings -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
            $warnings | Should -Not -BeNullOrEmpty
        }

        It "fails cleanly without the credential under -EnableException, as the pinned function does: its connect's Stop-Function throws" {
            { Get-DbaUserPermission -SqlInstance $loginInstance -Database $loginDbName -EnableException -WarningAction SilentlyContinue } | Should -Throw
        }
    }
}
