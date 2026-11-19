#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Copy-DbaServerRole",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: pipeline-multiple N/A -- no parameter accepts pipeline input; Destination is an explicit array, covered below.
# NativeChecklist: sql-login N/A -- the pinned function declares SourceSqlCredential and DestinationSqlCredential, not SqlCredential.
# NativeChecklist: azure-sqldb N/A -- Azure SQL Database has no user-defined server roles: CREATE SERVER ROLE applies to SQL Server and Azure SQL Managed Instance only (https://learn.microsoft.com/sql/t-sql/statements/create-server-role-transact-sql), and Azure SQL Database offers only its fixed ##MS_## server roles, with no server-level permissions to grant (https://learn.microsoft.com/azure/azure-sql/database/security-server-roles). The command refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does, tested below.

Describe "Native Copy-DbaServerRole" -Tag IntegrationTests {
    BeforeAll {
        $nativeSource = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -EnableException
        $nativeDestination = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -EnableException
        # Unique per leg and run; every object below carries the prefix and is removed in AfterAll.
        $nativePrefix = "dbatoolsci_nsr_" + [Guid]::NewGuid().ToString("N")
        $nativeMain = $nativePrefix + "_main"
        $nativeBare = $nativePrefix + "_bare"
        $nativeScope = $nativePrefix + "_scope"
        $nativeMissing = $nativePrefix + "_missing"
        $nativeBoth = $nativePrefix + "_both"
        $nativeSourceOnly = $nativePrefix + "_srconly"
        $nativeDestOnly = $nativePrefix + "_dstonly"
        $nativeDatabase = $nativePrefix + "_db"
        $nativeRoles = @($nativeMain, $nativeBare, $nativeScope)
        $nativePassword = "Ns1!" + [Guid]::NewGuid().ToString("N")

        foreach ($nativeServer in @($nativeSource, $nativeDestination)) {
            $nativeServer.ConnectionContext.ExecuteNonQuery("CREATE LOGIN [$nativeBoth] WITH PASSWORD = N'$nativePassword', CHECK_POLICY = OFF;")
        }
        $nativeSource.ConnectionContext.ExecuteNonQuery("CREATE LOGIN [$nativeSourceOnly] WITH PASSWORD = N'$nativePassword', CHECK_POLICY = OFF;")

        # A role with every statement form the copy replays: a plain grant, a grant with grant option, a deny and a grant
        # on a login securable, and two login members, one of which exists only on the source.
        $nativeSource.ConnectionContext.ExecuteNonQuery("CREATE SERVER ROLE [$nativeMain];")
        $nativeSource.ConnectionContext.ExecuteNonQuery("GRANT CONNECT ANY DATABASE TO [$nativeMain];")
        $nativeSource.ConnectionContext.ExecuteNonQuery("GRANT VIEW SERVER STATE TO [$nativeMain] WITH GRANT OPTION;")
        $nativeSource.ConnectionContext.ExecuteNonQuery("DENY VIEW ANY DATABASE TO [$nativeMain];")
        $nativeSource.ConnectionContext.ExecuteNonQuery("GRANT IMPERSONATE ON LOGIN::[$nativeBoth] TO [$nativeMain];")
        $nativeSource.ConnectionContext.ExecuteNonQuery("ALTER SERVER ROLE [$nativeMain] ADD MEMBER [$nativeBoth];")
        $nativeSource.ConnectionContext.ExecuteNonQuery("ALTER SERVER ROLE [$nativeMain] ADD MEMBER [$nativeSourceOnly];")

        # A role without members.
        $nativeSource.ConnectionContext.ExecuteNonQuery("CREATE SERVER ROLE [$nativeBare];")
        $nativeSource.ConnectionContext.ExecuteNonQuery("GRANT VIEW ANY DEFINITION TO [$nativeBare];")

        # A role whose name a database role in a source database shares, with a database permission of its own.
        $nativeSource.ConnectionContext.ExecuteNonQuery("CREATE SERVER ROLE [$nativeScope];")
        $nativeSource.ConnectionContext.ExecuteNonQuery("GRANT VIEW SERVER STATE TO [$nativeScope];")
        $nativeSource.ConnectionContext.ExecuteNonQuery("CREATE DATABASE [$nativeDatabase];")
        $nativeSource.ConnectionContext.ExecuteNonQuery("EXEC [$nativeDatabase].sys.sp_executesql N'CREATE ROLE [$nativeScope]; GRANT CREATE TABLE TO [$nativeScope];';")
        $nativeSource.Roles.Refresh()
        $nativeSource.Databases.Refresh()

        # The role's server permissions as the server stores them, one line each, sorted; a login securable by name.
        $nativeReadPermissions = {
            param($Server, $Name)
            # The catalog columns carry different collations, so they are read separately and joined here, not in T-SQL.
            $query = "SELECT perm.state_desc AS StateDesc, perm.permission_name AS PermissionName, perm.class_desc AS ClassDesc, ISNULL(target.name, N'') AS TargetName FROM sys.server_permissions AS perm INNER JOIN sys.server_principals AS grantee ON grantee.principal_id = perm.grantee_principal_id LEFT OUTER JOIN sys.server_principals AS target ON perm.class = 101 AND target.principal_id = perm.major_id WHERE grantee.name = N'$Name';"
            @($Server.ConnectionContext.ExecuteWithResults($query).Tables[0].Rows | ForEach-Object { "{0} {1} {2} {3}" -f $PSItem.StateDesc, $PSItem.PermissionName, $PSItem.ClassDesc, $PSItem.TargetName } | Sort-Object) -join "|"
        }
        $nativeReadMembers = {
            param($Server, $Name)
            $query = "SELECT member.name AS Name FROM sys.server_role_members AS link INNER JOIN sys.server_principals AS role ON role.principal_id = link.role_principal_id INNER JOIN sys.server_principals AS member ON member.principal_id = link.member_principal_id WHERE role.name = N'$Name';"
            @($Server.ConnectionContext.ExecuteWithResults($query).Tables[0].Rows | ForEach-Object { $PSItem.Name } | Sort-Object)
        }
        $nativeRoleExists = {
            param($Server, $Name)
            [int]$Server.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.server_principals WHERE type = 'R' AND name = N'$Name';") -eq 1
        }
        $nativeDropRole = {
            param($Server, $Name)
            if (& $nativeRoleExists $Server $Name) {
                foreach ($nativeMember in (& $nativeReadMembers $Server $Name)) {
                    $Server.ConnectionContext.ExecuteNonQuery("ALTER SERVER ROLE [$Name] DROP MEMBER [$nativeMember];")
                }
                $Server.ConnectionContext.ExecuteNonQuery("DROP SERVER ROLE [$Name];")
            }
        }
        $nativeMasterRoleSql = "IF EXISTS (SELECT 1 FROM master.sys.database_principals WHERE type = 'R' AND name = N'$nativeScope') EXEC master.sys.sp_executesql N'DROP ROLE [$nativeScope];';"
    }

    AfterEach {
        foreach ($nativeName in $nativeRoles) {
            & $nativeDropRole $nativeDestination $nativeName
        }
        $nativeDestination.ConnectionContext.ExecuteNonQuery($nativeMasterRoleSql)
        $nativeDestination.Roles.Refresh()
    }

    AfterAll {
        foreach ($nativeServer in @($nativeSource, $nativeDestination)) {
            if (-not $nativeServer) { continue }
            foreach ($nativeName in $nativeRoles) {
                & $nativeDropRole $nativeServer $nativeName
            }
            foreach ($nativeLogin in @($nativeBoth, $nativeSourceOnly, $nativeDestOnly)) {
                $nativeServer.ConnectionContext.ExecuteNonQuery("IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$nativeLogin') DROP LOGIN [$nativeLogin];")
            }
        }
        if ($nativeDestination) { $nativeDestination.ConnectionContext.ExecuteNonQuery($nativeMasterRoleSql) }
        if ($nativeSource) {
            $nativeSource.ConnectionContext.ExecuteNonQuery("IF DB_ID(N'$nativeDatabase') IS NOT NULL BEGIN ALTER DATABASE [$nativeDatabase] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$nativeDatabase]; END")
        }
    }

    It "copies a role with its server permissions and login memberships in the pinned MigrationObject shape" {
        $splatCopyMain = @{
            Source          = $TestConfig.InstanceCopy1
            Destination     = $TestConfig.InstanceCopy2
            ServerRole      = $nativeMain
            EnableException = $true
        }
        $nativeResults = @(Copy-DbaServerRole @splatCopyMain)
        $nativeResults.Count | Should -Be 1
        $nativeResults[0].Status | Should -BeExactly "Successful"
        $nativeResults[0].Name | Should -BeExactly $nativeMain
        $nativeResults[0].Type | Should -BeExactly "Server Role"
        $nativeResults[0].SourceServer | Should -BeExactly $nativeSource.Name
        $nativeResults[0].DestinationServer | Should -BeExactly $nativeDestination.Name
        $nativeResults[0].Notes | Should -BeNullOrEmpty
        $nativeResults[0].DateTime | Should -BeOfType Dataplat.Dbatools.Utility.DbaDateTime
        $nativeResults[0].PSObject.TypeNames[0] | Should -BeExactly "dbatools.MigrationObject"
        ($nativeResults[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly "DateTime,SourceServer,DestinationServer,Name,Type,Status,Notes"
        ($nativeResults[0].PSObject.Properties.Name -join ",") | Should -BeExactly "SourceServer,DestinationServer,Type,Name,Status,Notes,DateTime"

        $nativeExpected = & $nativeReadPermissions $nativeSource $nativeMain
        $nativeExpected | Should -BeLikeExactly "*DENY VIEW ANY DATABASE*"
        $nativeExpected | Should -BeLikeExactly "*GRANT_WITH_GRANT_OPTION VIEW SERVER STATE*"
        $nativeExpected | Should -BeLikeExactly "*GRANT IMPERSONATE SERVER_PRINCIPAL $nativeBoth*"
        & $nativeReadPermissions $nativeDestination $nativeMain | Should -BeExactly $nativeExpected
        # The login that exists on both servers becomes a member; the source-only login is skipped.
        (& $nativeReadMembers $nativeDestination $nativeMain) -join "," | Should -BeExactly $nativeBoth
    }

    It "skips an existing role without Force and replaces it with Force" -Tag NativeChecklist:switch-false {
        $splatCopyBare = @{
            Source          = $TestConfig.InstanceCopy1
            Destination     = $TestConfig.InstanceCopy2
            ServerRole      = $nativeBare
            Force           = $false
            EnableException = $true
        }
        @(Copy-DbaServerRole @splatCopyBare)[0].Status | Should -BeExactly "Successful"
        $nativeSkipped = @(Copy-DbaServerRole @splatCopyBare)
        $nativeSkipped.Count | Should -Be 1
        $nativeSkipped[0].Status | Should -BeExactly "Skipped"
        $nativeSkipped[0].Notes | Should -BeExactly "Already exists on destination"

        # A permission only the destination has is gone after the role is dropped and recreated.
        $nativeDestination.ConnectionContext.ExecuteNonQuery("GRANT ALTER TRACE TO [$nativeBare];")
        $nativePreference = $ConfirmPreference
        $splatCopyBare.Force = $true
        $nativeReplaced = @(Copy-DbaServerRole @splatCopyBare)
        $nativeReplaced.Count | Should -Be 1
        $nativeReplaced[0].Status | Should -BeExactly "Successful"
        $ConfirmPreference | Should -Be $nativePreference
        & $nativeReadPermissions $nativeDestination $nativeBare | Should -BeExactly (& $nativeReadPermissions $nativeSource $nativeBare)
    }

    It "replaces a role that has members with Force" {
        $splatCopyMain = @{
            Source          = $TestConfig.InstanceCopy1
            Destination     = $TestConfig.InstanceCopy2
            ServerRole      = $nativeMain
            EnableException = $true
        }
        @(Copy-DbaServerRole @splatCopyMain)[0].Status | Should -BeExactly "Successful"
        (& $nativeReadMembers $nativeDestination $nativeMain) -join "," | Should -BeExactly $nativeBoth
        $nativeDestination.ConnectionContext.ExecuteNonQuery("GRANT ALTER TRACE TO [$nativeMain];")

        $splatCopyMain.Force = $true
        $nativeReplaced = @(Copy-DbaServerRole @splatCopyMain)
        $nativeReplaced.Count | Should -Be 1
        $nativeReplaced[0].Status | Should -BeExactly "Successful"
        $nativeReplaced[0].Notes | Should -BeNullOrEmpty
        & $nativeReadPermissions $nativeDestination $nativeMain | Should -BeExactly (& $nativeReadPermissions $nativeSource $nativeMain)
        (& $nativeReadMembers $nativeDestination $nativeMain) -join "," | Should -BeExactly $nativeBoth
    }

    It "drops destination members the source role lacks when Force recreates the role" {
        # Drop and recreate: the recreated role has the source role's login members only.
        $splatCopyMain = @{
            Source          = $TestConfig.InstanceCopy1
            Destination     = $TestConfig.InstanceCopy2
            ServerRole      = $nativeMain
            EnableException = $true
        }
        @(Copy-DbaServerRole @splatCopyMain)[0].Status | Should -BeExactly "Successful"
        $nativeDestination.ConnectionContext.ExecuteNonQuery("CREATE LOGIN [$nativeDestOnly] WITH PASSWORD = N'$nativePassword', CHECK_POLICY = OFF;")
        $nativeDestination.ConnectionContext.ExecuteNonQuery("ALTER SERVER ROLE [$nativeMain] ADD MEMBER [$nativeDestOnly];")
        (& $nativeReadMembers $nativeDestination $nativeMain) -join "," | Should -BeExactly ((@($nativeBoth, $nativeDestOnly) | Sort-Object) -join ",")

        $splatCopyMain.Force = $true
        @(Copy-DbaServerRole @splatCopyMain)[0].Status | Should -BeExactly "Successful"
        (& $nativeReadMembers $nativeDestination $nativeMain) -join "," | Should -BeExactly $nativeBoth
        # The login itself stays; only its membership in the dropped role is gone.
        [int]$nativeDestination.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.server_principals WHERE name = N'$nativeDestOnly';") | Should -Be 1
    }

    It "leaves an existing role and its members unchanged under WhatIf with Force" -Tag NativeChecklist:whatif-confirm {
        $splatCopyMain = @{
            Source          = $TestConfig.InstanceCopy1
            Destination     = $TestConfig.InstanceCopy2
            ServerRole      = $nativeMain
            EnableException = $true
        }
        @(Copy-DbaServerRole @splatCopyMain)[0].Status | Should -BeExactly "Successful"
        $nativeDestination.ConnectionContext.ExecuteNonQuery("GRANT ALTER TRACE TO [$nativeMain];")
        $nativeBefore = & $nativeReadPermissions $nativeDestination $nativeMain

        @(Copy-DbaServerRole @splatCopyMain -Force -WhatIf).Count | Should -Be 0
        & $nativeRoleExists $nativeDestination $nativeMain | Should -BeTrue
        & $nativeReadPermissions $nativeDestination $nativeMain | Should -BeExactly $nativeBefore
        (& $nativeReadMembers $nativeDestination $nativeMain) -join "," | Should -BeExactly $nativeBoth
    }

    It "replays only the role's server permissions, not those of a same-named database principal" {
        # The destination's master database holds a database role of the same name, which a replayed database grant reaches.
        $nativeDestination.ConnectionContext.ExecuteNonQuery("EXEC master.sys.sp_executesql N'CREATE ROLE [$nativeScope];';")
        $nativeWarnings = @()
        $splatCopyScope = @{
            Source          = $TestConfig.InstanceCopy1
            Destination     = $TestConfig.InstanceCopy2
            ServerRole      = $nativeScope
            WarningVariable = "nativeWarnings"
            WarningAction   = "SilentlyContinue"
        }
        $nativeResults = @(Copy-DbaServerRole @splatCopyScope)
        $nativeResults.Count | Should -Be 1
        $nativeResults[0].Status | Should -BeExactly "Successful"
        @($nativeWarnings | Where-Object { "$PSItem" -like "*Could not grant permission*" }).Count | Should -Be 0
        & $nativeReadPermissions $nativeDestination $nativeScope | Should -BeExactly (& $nativeReadPermissions $nativeSource $nativeScope)
        $nativeMasterGrants = "SELECT COUNT(*) FROM master.sys.database_permissions AS perm INNER JOIN master.sys.database_principals AS grantee ON grantee.principal_id = perm.grantee_principal_id WHERE grantee.name = N'$nativeScope';"
        [int]$nativeDestination.ConnectionContext.ExecuteScalar($nativeMasterGrants) | Should -Be 0
    }

    It "lets ExcludeServerRole win over ServerRole and ignores names the source does not have" {
        $splatCopyExclude = @{
            Source            = $TestConfig.InstanceCopy1
            Destination       = $TestConfig.InstanceCopy2
            ServerRole        = @($nativeBare, $nativeMain, $nativeMissing)
            ExcludeServerRole = $nativeMain
            EnableException   = $true
        }
        $nativeResults = @(Copy-DbaServerRole @splatCopyExclude)
        ($nativeResults.Name -join ",") | Should -BeExactly $nativeBare
        & $nativeRoleExists $nativeDestination $nativeMain | Should -BeFalse
    }

    It "does not create a role under WhatIf" -Tag NativeChecklist:whatif-confirm {
        $splatCopyWhatIf = @{
            Source      = $TestConfig.InstanceCopy1
            Destination = $TestConfig.InstanceCopy2
            ServerRole  = $nativeBare
            Force       = $true
            WhatIf      = $true
        }
        @(Copy-DbaServerRole @splatCopyWhatIf).Count | Should -Be 0
        & $nativeRoleExists $nativeDestination $nativeBare | Should -BeFalse
    }

    It "continues to a valid destination after a connection failure" -Tag NativeChecklist:multi-instance-failure, NativeChecklist:enable-exception {
        $nativeWarnings = @()
        $splatCopyFailure = @{
            Source          = $TestConfig.InstanceCopy1
            Destination     = @("TCP:127.0.0.1,1", $TestConfig.InstanceCopy2)
            ServerRole      = $nativeBare
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "nativeWarnings"
        }
        $nativeResults = @(Copy-DbaServerRole @splatCopyFailure)
        $nativeResults.Count | Should -Be 1
        $nativeResults[0].Status | Should -BeExactly "Successful"
        ($nativeWarnings -join " ") | Should -BeLike "*Failure*"
    }

    It "throws a connection error for an unreachable destination under EnableException" -Tag NativeChecklist:enable-exception {
        $nativeCaught = $null
        try {
            $null = Copy-DbaServerRole -Source $TestConfig.InstanceCopy1 -Destination "TCP:127.0.0.1,1" -ServerRole $nativeBare -EnableException
        } catch {
            $nativeCaught = $PSItem
        }
        $nativeCaught | Should -Not -BeNullOrEmpty
        $nativeCaught.CategoryInfo.Category | Should -Be "ConnectionError"
    }

    It "warns and writes nothing for an unreachable source, and throws under EnableException" -Tag NativeChecklist:enable-exception {
        $nativeWarnings = @()
        $splatCopySource = @{
            Source          = "TCP:127.0.0.1,1"
            Destination     = $TestConfig.InstanceCopy2
            ServerRole      = $nativeBare
            WarningAction   = "SilentlyContinue"
            WarningVariable = "nativeWarnings"
        }
        @(Copy-DbaServerRole @splatCopySource).Count | Should -Be 0
        ($nativeWarnings -join " ") | Should -BeLike "*Failure*"

        $nativeCaught = $null
        try {
            $null = Copy-DbaServerRole @splatCopySource -EnableException
        } catch {
            $nativeCaught = $PSItem
        }
        $nativeCaught | Should -Not -BeNullOrEmpty
        $nativeCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        & $nativeRoleExists $nativeDestination $nativeBare | Should -BeFalse
    }
}

Describe "Native Copy-DbaServerRole refuses Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            ConnectTimeout  = 60
            EnableException = $true
        }
        # Only this connect step retries, a fixed number of times; the command under test runs once per test.
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                # A paused serverless database answers 40613, or lets the login time out, while it resumes.
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -eq 40613 -or $azureError.Number -eq -2 -or $azureError.NativeErrorCode -eq 258 -or $azureError.Message -like "*timed out*") { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        # A name no instance has, so nothing is ever copied by these tests.
        $azureRoleName = "dbatoolsci_nsr_azure_" + [Guid]::NewGuid().ToString("N")
    }

    It "refuses an Azure SQL Database destination with a warning and no output" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = @()
        $splatAzureDestination = @{
            Source          = $TestConfig.InstanceCopy1
            Destination     = $azureServer
            ServerRole      = $azureRoleName
            WarningVariable = "azureWarnings"
            WarningAction   = "SilentlyContinue"
        }
        @(Copy-DbaServerRole @splatAzureDestination).Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "refuses an Azure SQL Database source with a warning and no output" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = @()
        $splatAzureSource = @{
            Source          = $azureServer
            Destination     = $TestConfig.InstanceCopy2
            ServerRole      = $azureRoleName
            WarningVariable = "azureWarnings"
            WarningAction   = "SilentlyContinue"
        }
        @(Copy-DbaServerRole @splatAzureSource).Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "throws a connection error for an Azure SQL Database destination under EnableException" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureCaught = $null
        try {
            $null = Copy-DbaServerRole -Source $TestConfig.InstanceCopy1 -Destination $azureServer -ServerRole $azureRoleName -EnableException
        } catch {
            $azureCaught = $PSItem
        }
        $azureCaught | Should -Not -BeNullOrEmpty
        $azureCaught.CategoryInfo.Category | Should -Be "ConnectionError"
    }
}
