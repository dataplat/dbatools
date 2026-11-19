#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Add-DbaDbRoleMember",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Add-DbaDbRoleMember SQL authentication" -Tag IntegrationTests, "NativeChecklist:sql-login" {
    BeforeAll {
        $loginServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -EnableException
        $loginDbName = "dbatoolsci_role_login_$([guid]::NewGuid().ToString('N'))"
        $loginDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $loginServer, $loginDbName
        $loginDatabase.Create()
        $loginDatabase.ExecuteNonQuery('CREATE USER [native_member] WITHOUT LOGIN; CREATE ROLE [native_role];')
    }

    AfterAll {
        if ($loginServer -and $loginDatabase -and $loginDatabase.State -eq 'Existing') {
            $loginServer.KillDatabase($loginDbName)
        }
    }

    It "adds membership with the SQL credential" {
        $splatLoginRole = @{
            SqlInstance = $TestConfig.InstanceSqlLogin
            SqlCredential = $TestConfig.SqlLoginCred
            Database = $loginDbName
            Role = 'native_role'
            Member = 'native_member'
            Confirm = $false
            EnableException = $true
        }
        @(Add-DbaDbRoleMember @splatLoginRole).Count | Should -Be 0
        $loginMembership = $loginDatabase.ExecuteWithResults("SELECT COUNT(*) AS MemberCount FROM sys.database_role_members WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'native_role') AND member_principal_id = DATABASE_PRINCIPAL_ID(N'native_member');")
        $loginMembership.Tables[0].Rows[0].MemberCount | Should -Be 1
    }

    It "warns without output when the SQL credential is omitted" {
        $loginWarnings = @()
        $splatLoginDenied = @{
            SqlInstance = $TestConfig.InstanceSqlLogin
            Database = $loginDbName
            Role = 'native_role'
            Member = 'native_member'
            Confirm = $false
            EnableException = $false
            WarningAction = 'SilentlyContinue'
            WarningVariable = 'loginWarnings'
        }
        @(Add-DbaDbRoleMember @splatLoginDenied).Count | Should -Be 0
        $loginWarnings | Should -Not -BeNullOrEmpty
    }

    It "warns without output with EnableException when the SQL credential is omitted" {
        # Pinned public/Add-DbaDbRoleMember.ps1:122/:126 calls Get-DbaDbRole without forwarding EnableException.
        $loginWarnings = @()
        $splatLoginDenied = @{
            SqlInstance = $TestConfig.InstanceSqlLogin
            Database = $loginDbName
            Role = "native_role"
            Member = "native_member"
            Confirm = $false
            EnableException = $true
            WarningAction = "SilentlyContinue"
            WarningVariable = "loginWarnings"
        }
        @(Add-DbaDbRoleMember @splatLoginDenied).Count | Should -Be 0
        $loginWarnings | Should -Not -BeNullOrEmpty
    }
}

Describe "Native Add-DbaDbRoleMember Azure" -Tag IntegrationTests {
    It "adds a contained user to a role in Azure SQL Database" -Tag "NativeChecklist:azure-sqldb" {
        $splatAzureConnection = @{
            SqlInstance = $TestConfig.AzureSqlDbServer
            Database = $TestConfig.AzureSqlDbName
            SqlCredential = $TestConfig.AzureSqlDbCred
            EnableException = $true
        }
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -in @(40613, -2) -or $azureError -is [System.TimeoutException]) { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureDatabase = $azureServer.Databases[$TestConfig.AzureSqlDbName]
        $azureSuffix = [guid]::NewGuid().ToString("N")
        $azureUserName = "native_member_$azureSuffix"
        $azureRoleName = "native_role_$azureSuffix"
        try {
            $azureDatabase.ExecuteNonQuery("CREATE USER [$azureUserName] WITHOUT LOGIN;")
            $azureDatabase.ExecuteNonQuery("CREATE ROLE [$azureRoleName];")
            $azureDatabase.Roles.Refresh()
            $azureDatabase.Users.Refresh()
            $splatAzureRole = @{
                InputObject = $azureDatabase.Roles[$azureRoleName]
                Member = $azureUserName
                Confirm = $false
                EnableException = $true
            }
            @(Add-DbaDbRoleMember @splatAzureRole).Count | Should -Be 0
            $azureMembership = $azureDatabase.ExecuteWithResults("SELECT COUNT(*) AS MemberCount FROM sys.database_role_members WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'$azureRoleName') AND member_principal_id = DATABASE_PRINCIPAL_ID(N'$azureUserName');")
            $azureMembership.Tables[0].Rows[0].MemberCount | Should -Be 1
        } finally {
            $azureDatabase.ExecuteNonQuery("IF DATABASE_PRINCIPAL_ID(N'$azureUserName') IS NOT NULL DROP USER [$azureUserName];")
            $azureDatabase.ExecuteNonQuery("IF DATABASE_PRINCIPAL_ID(N'$azureRoleName') IS NOT NULL DROP ROLE [$azureRoleName];")
        }
    }
}

Describe "Native Add-DbaDbRoleMember" -Tag IntegrationTests {
    BeforeAll {
        $nativeRoleServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeRoleDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeRoleServer, "dbatoolsci_native_role_$(Get-Random)"
        $nativeRoleDatabase.Create()
        $nativeRoleDatabase.ExecuteNonQuery("CREATE USER [native_member] WITHOUT LOGIN; CREATE ROLE [native_child]; CREATE ROLE [native_parent]; CREATE ROLE [native_second]; CREATE ROLE [native_'quoted]]role];")
        $nativeRoleDatabase.Roles.Refresh()
        $nativeRoleDatabase.Users.Refresh()
        $nativeRoleLiteralDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeRoleServer, ($nativeRoleDatabase.Name + '_literal_safe')
        $nativeRoleLiteralDatabase.Create()
        # Rename after creation so the literal '?' never enters a physical file path.
        $nativeRoleLiteralDatabase.Rename($nativeRoleDatabase.Name + '_literal?')
        $nativeRoleOtherDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeRoleServer, ($nativeRoleDatabase.Name + '_literalX')
        $nativeRoleOtherDatabase.Create()
        foreach ($database in @($nativeRoleLiteralDatabase, $nativeRoleOtherDatabase)) {
            $database.ExecuteNonQuery('CREATE USER [native_member] WITHOUT LOGIN; CREATE ROLE [native_parent]; CREATE ROLE [native_second];')
            $database.Roles.Refresh()
            $database.Users.Refresh()
        }
        $nativeRoleServer.Databases.Refresh()
    }

    BeforeEach {
        foreach ($database in @($nativeRoleLiteralDatabase, $nativeRoleOtherDatabase)) {
            foreach ($roleName in 'native_parent', 'native_second') {
                foreach ($memberName in @($database.Roles[$roleName].EnumMembers())) {
                    $database.Roles[$roleName].DropMember($memberName)
                }
            }
        }
        foreach ($nativeRoleName in "native_parent", "native_second", "native_'quoted]role") {
            $nativeRole = $nativeRoleDatabase.Roles[$nativeRoleName]
            foreach ($nativeRoleMember in @($nativeRole.EnumMembers())) {
                $nativeRole.DropMember($nativeRoleMember)
            }
        }
    }

    AfterAll {
        foreach ($database in @($nativeRoleLiteralDatabase, $nativeRoleOtherDatabase)) {
            if ($database -and $database.State -eq 'Existing') { $nativeRoleServer.KillDatabase($database.Name) }
        }
        if ($nativeRoleDatabase) {
            $nativeRoleServer.KillDatabase($nativeRoleDatabase.Name)
        }
    }

    It "selects databases using the documented wildcard in both server input forms" {
        $pattern = $nativeRoleDatabase.Name + '*'
        @(Add-DbaDbRoleMember -SqlInstance $nativeRoleServer -Database $pattern -Role native_parent -Member native_member -Confirm:$false -EnableException).Count | Should -Be 0
        @(Add-DbaDbRoleMember -InputObject $nativeRoleServer -Database $pattern -Role native_second -Member native_member -Confirm:$false -EnableException).Count | Should -Be 0
        foreach ($database in @($nativeRoleDatabase, $nativeRoleLiteralDatabase, $nativeRoleOtherDatabase)) {
            @($database.Roles['native_parent'].EnumMembers()) | Should -Contain 'native_member'
            @($database.Roles['native_second'].EnumMembers()) | Should -Contain 'native_member'
        }
    }

    It "keeps an existing database name containing a wildcard character literal" {
        @(Add-DbaDbRoleMember -SqlInstance $nativeRoleServer -Database $nativeRoleLiteralDatabase.Name -Role native_parent -Member native_member -Confirm:$false -EnableException).Count | Should -Be 0
        @($nativeRoleLiteralDatabase.Roles['native_parent'].EnumMembers()) | Should -Contain 'native_member'
        @($nativeRoleOtherDatabase.Roles['native_parent'].EnumMembers()).Count | Should -Be 0
        @($nativeRoleDatabase.Roles['native_parent'].EnumMembers()).Count | Should -Be 0
    }

    It "adds users and roles across multiple role pipeline records without emitting objects" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:switch-false" {
        $splatNativeRole = @{
            Member          = @("native_member", "native_child")
            Confirm         = $false
            WhatIf          = $false
            EnableException = $true
        }
        $nativeRoles = @($nativeRoleDatabase.Roles["native_parent"], $nativeRoleDatabase.Roles["native_second"])
        @($nativeRoles | Add-DbaDbRoleMember @splatNativeRole).Count | Should -Be 0
        foreach ($nativeRole in $nativeRoles) {
            $nativeMembers = @($nativeRole.EnumMembers())
            $nativeMembers | Should -Contain "native_member"
            $nativeMembers | Should -Contain "native_child"
        }
        @($nativeRoles | Add-DbaDbRoleMember @splatNativeRole).Count | Should -Be 0
        @($nativeRoles[0].EnumMembers()).Count | Should -Be 2
    }

    It "honors WhatIf without changing membership" -Tag "NativeChecklist:whatif-confirm" {
        $splatNativeRole = @{
            InputObject     = $nativeRoleDatabase
            Role            = "native_parent"
            Member          = "native_member"
            Confirm         = $false
            WhatIf          = $true
            EnableException = $true
        }
        @(Add-DbaDbRoleMember @splatNativeRole).Count | Should -Be 0
        @($nativeRoleDatabase.Roles["native_parent"].EnumMembers()).Count | Should -Be 0
    }

    It "accepts database and server input forms and the User alias with quoted role names" {
        $splatNativeRole = @{
            InputObject     = $nativeRoleDatabase
            Role            = "native_'quoted]role"
            User            = "native_member"
            Confirm         = $false
            EnableException = $true
        }
        @(Add-DbaDbRoleMember @splatNativeRole).Count | Should -Be 0
        @($nativeRoleDatabase.Roles["native_'quoted]role"].EnumMembers()) | Should -Contain "native_member"
        $splatNativeRole.InputObject = $nativeRoleServer
        $splatNativeRole.Database = $nativeRoleDatabase.Name
        $splatNativeRole.Role = "native_second"
        @(Add-DbaDbRoleMember @splatNativeRole).Count | Should -Be 0
        @($nativeRoleDatabase.Roles["native_second"].EnumMembers()) | Should -Contain "native_member"
    }

    It "retains successful instance work around a failed connection" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false" {
        $splatNativeRole = @{
            SqlInstance     = @($nativeRoleServer, "tcp:127.0.0.1,1", $nativeRoleServer)
            Database        = $nativeRoleDatabase.Name
            Role            = "native_parent"
            Member          = "native_member"
            Confirm         = $false
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "nativeRoleWarnings"
        }
        @(Add-DbaDbRoleMember @splatNativeRole).Count | Should -Be 0
        @($nativeRoleDatabase.Roles["native_parent"].EnumMembers()) | Should -Contain "native_member"
        ($nativeRoleWarnings -join " ") | Should -BeLike "*Failure*"
    }

    It "warns or throws for unsupported input according to EnableException" -Tag "NativeChecklist:enable-exception" {
        $splatNativeRole = @{
            InputObject     = @{ Invalid = "object" }
            Member          = "native_member"
            Confirm         = $false
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "nativeRoleWarnings"
        }
        @(Add-DbaDbRoleMember @splatNativeRole).Count | Should -Be 0
        ($nativeRoleWarnings -join " ") | Should -BeLike "*InputObject is not a server, database, or database role.*"
        $splatNativeRole.EnableException = $true
        { Add-DbaDbRoleMember @splatNativeRole } | Should -Throw "*InputObject is not a server, database, or database role.*"
    }

    It "preserves a failing AddMember method error independently of EnableException" {
        $splatNativeRole = @{
            InputObject     = $nativeRoleDatabase.Roles["native_parent"]
            Member          = "native_parent"
            Confirm         = $false
            EnableException = $false
        }
        $nativeRoleError = $null
        try {
            Add-DbaDbRoleMember @splatNativeRole
        } catch {
            $nativeRoleError = $PSItem
        }
        $nativeRoleError | Should -Not -BeNullOrEmpty
        $nativeRoleError.Exception | Should -BeOfType System.Management.Automation.MethodInvocationException
        $nativeRoleError.FullyQualifiedErrorId | Should -BeLike "FailedOperationException*"
        $nativeRoleError.Exception.Message | Should -BeLike "*Exception calling *AddMember*"
        @($nativeRoleDatabase.Roles["native_parent"].EnumMembers()) | Should -Not -Contain "native_parent"
    }
}
