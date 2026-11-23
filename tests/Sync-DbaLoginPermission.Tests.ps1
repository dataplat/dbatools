#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Sync-DbaLoginPermission",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Login",
                "ExcludeLogin",
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

        $tempguid = [guid]::newguid()
        $DBUserName = "dbatoolssci_$($tempguid.guid)"
        $CreateTestUser = @"
CREATE LOGIN [$DBUserName]
    WITH PASSWORD = '$($tempguid.guid)';
USE master;
CREATE USER [$DBUserName] FOR LOGIN [$DBUserName]
    WITH DEFAULT_SCHEMA = dbo;
GRANT VIEW ANY DEFINITION to [$DBUserName];
"@
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Query $CreateTestUser -Database master

        # This is used later in the test
        $CreateTestLogin = @"
CREATE LOGIN [$DBUserName]
    WITH PASSWORD = '$($tempguid.guid)';
"@

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $DropTestUser = "DROP LOGIN [$DBUserName]"
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Query $DropTestUser -Database master

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command execution and functionality" {

        It "Should not have the user permissions of $DBUserName" {
            $permissionsBefore = Get-DbaUserPermission -SqlInstance $TestConfig.InstanceMulti2 -Database master | Where-Object { $_.member -eq $DBUserName }
            $permissionsBefore | Should -BeNullOrEmpty
        }

        It "Should execute against active nodes" {
            # Creates the user on
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti2 -Query $CreateTestLogin
            $results = Sync-DbaLoginPermission -Source $TestConfig.InstanceMulti1 -Destination $TestConfig.InstanceMulti2 -Login $DBUserName -ExcludeLogin "NotaLogin" -WarningVariable warn
            $results.Status | Should -Be "Successful"
            $warn | Should -BeNullOrEmpty
        }

        # The copy failes on Appveyor with: Failed to create or use STIG schema on APPVYR-WIN\sql2017
        It "Should have copied the user permissions of $DBUserName" -Skip:$env:appveyor {
            $permissionsAfter = Get-DbaUserPermission -SqlInstance $TestConfig.InstanceMulti2 -Database master | Where-Object { $_.member -eq $DBUserName -and $_.permission -eq "VIEW ANY DEFINITION" }
            $permissionsAfter.member | Should -Be $DBUserName
        }
    }

    Context "Login state synchronization" {
        BeforeAll {
            $tempLoginGuid = [guid]::newguid()
            $stateTestLogin = "dbatoolssci_state_$($tempLoginGuid.guid)"
            $createStateLogin = @"
CREATE LOGIN [$stateTestLogin]
    WITH PASSWORD = '$($tempLoginGuid.guid)';
"@
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Query $createStateLogin
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti2 -Query $createStateLogin

            # Disable and deny connect on source
            $splatDisable = @{
                SqlInstance = $TestConfig.InstanceMulti1
                Query       = "ALTER LOGIN [$stateTestLogin] DISABLE; DENY CONNECT SQL TO [$stateTestLogin];"
            }
            Invoke-DbaQuery @splatDisable
        }
        AfterAll {
            $dropStateLogin = "DROP LOGIN [$stateTestLogin]"
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Query $dropStateLogin -Database master
        }

        It "Should sync login disabled state from source to destination" {
            $sourceLogin = Get-DbaLogin -SqlInstance $TestConfig.InstanceMulti1 -Login $stateTestLogin
            $sourceLogin.IsDisabled | Should -Be $true

            $destLoginBefore = Get-DbaLogin -SqlInstance $TestConfig.InstanceMulti2 -Login $stateTestLogin
            $destLoginBefore.IsDisabled | Should -Be $false

            $splatSync = @{
                Source      = $TestConfig.InstanceMulti1
                Destination = $TestConfig.InstanceMulti2
                Login       = $stateTestLogin
            }
            $results = Sync-DbaLoginPermission @splatSync
            $results.Status | Should -Be "Successful"

            $destLoginAfter = Get-DbaLogin -SqlInstance $TestConfig.InstanceMulti2 -Login $stateTestLogin
            $destLoginAfter.IsDisabled | Should -Be $true
        }
    }

    Context "When the database user of a login has another name than the login (#10837)" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # A database principal is a user, and a user can have another name than its login, on each server another one.
            # The permissions were read and revoked by the name of the login: the user kept what the source user does not
            # have and did not get what it has, while an unrelated user that has the name of the login lost its permissions.
            $userDbName = "dbatoolsci_userdb_$(Get-Random)"
            $userLoginName = "dbatoolsci_userlogin_$(Get-Random)"
            $pairLoginName = "dbatoolsci_pairlogin_$(Get-Random)"
            $userPassword = ConvertTo-SecureString -String "dbatools.IO!$(Get-Random)" -AsPlainText -Force
            $null = New-DbaLogin -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Login $userLoginName, $pairLoginName -SecurePassword $userPassword
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Name $userDbName

            # The first login has a user of the same name on both servers, which is a member of a role on the source. On the
            # destination it has a permission the source user does not have, and another one from two grantors. A user
            # without login has the name of the login.
            # The second login has a user of another name on each server.
            $sourceUserSql = @"
CREATE USER [dbatoolsci_user] FOR LOGIN [$userLoginName];
GRANT VIEW DEFINITION TO [dbatoolsci_user];
CREATE ROLE [dbatoolsci_userrole];
ALTER ROLE [dbatoolsci_userrole] ADD MEMBER [dbatoolsci_user];
CREATE USER [dbatoolsci_sourceuser] FOR LOGIN [$pairLoginName];
GRANT CREATE VIEW TO [dbatoolsci_sourceuser];
"@
            $destUserSql = @"
CREATE USER [dbatoolsci_user] FOR LOGIN [$userLoginName];
GRANT ALTER ANY SCHEMA TO [dbatoolsci_user];
CREATE ROLE [dbatoolsci_userrole];
CREATE USER [dbatoolsci_grantor] WITHOUT LOGIN;
GRANT CREATE TABLE TO [dbatoolsci_grantor] WITH GRANT OPTION;
GRANT CREATE TABLE TO [dbatoolsci_user] AS [dbatoolsci_grantor];
GRANT CREATE TABLE TO [dbatoolsci_user];
CREATE USER [$userLoginName] WITHOUT LOGIN;
GRANT VIEW DATABASE STATE TO [$userLoginName];
CREATE USER [dbatoolsci_destuser] FOR LOGIN [$pairLoginName];
GRANT CREATE FUNCTION TO [dbatoolsci_destuser];
"@
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database $userDbName -Query $sourceUserSql
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti2 -Database $userDbName -Query $destUserSql

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $userSyncResult = Sync-DbaLoginPermission -Source $TestConfig.InstanceMulti1 -Destination $TestConfig.InstanceMulti2 -Login $userLoginName, $pairLoginName
            $userSyncWarnings = $WarnVar

            $destPermissionSql = @"
SELECT grantee.name AS Grantee, perm.permission_name AS Permission, grantor.name AS Grantor
FROM sys.database_permissions AS perm
INNER JOIN sys.database_principals AS grantee ON grantee.principal_id = perm.grantee_principal_id
INNER JOIN sys.database_principals AS grantor ON grantor.principal_id = perm.grantor_principal_id
WHERE perm.class = 0
"@
            $destPermissions = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti2 -Database $userDbName -Query $destPermissionSql
            $destRoleMembers = (Get-DbaDbRoleMember -SqlInstance $TestConfig.InstanceMulti2 -Database $userDbName -Role dbatoolsci_userrole).UserName
            $destUserNames = (Get-DbaDbUser -SqlInstance $TestConfig.InstanceMulti2 -Database $userDbName).Name
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Database $userDbName -ErrorAction SilentlyContinue
            $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Login $userLoginName, $pairLoginName -Force -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Syncs both logins without a warning" {
            $userSyncWarnings | Should -BeNullOrEmpty
            @($userSyncResult).Count | Should -Be 2
            $userSyncResult.Status | Should -Be "Successful", "Successful"
        }

        It "Grants the permissions of the source user to the user" {
            $destPermissions | Where-Object { $PSItem.Grantee -eq "dbatoolsci_user" -and $PSItem.Permission -eq "VIEW DEFINITION" } | Should -Not -BeNullOrEmpty
        }

        It "Revokes a permission from the user that the source user does not have" {
            $destPermissions | Where-Object { $PSItem.Grantee -eq "dbatoolsci_user" -and $PSItem.Permission -eq "ALTER ANY SCHEMA" } | Should -BeNullOrEmpty
        }

        It "Revokes such a permission from every grantor" {
            # A REVOKE without AS takes back the grant of dbo only, so the one of the other grantor stayed.
            $destPermissions | Where-Object { $PSItem.Grantee -eq "dbatoolsci_user" -and $PSItem.Permission -eq "CREATE TABLE" } | Should -BeNullOrEmpty
            $destPermissions | Where-Object { $PSItem.Grantee -eq "dbatoolsci_grantor" -and $PSItem.Permission -eq "CREATE TABLE" } | Should -Not -BeNullOrEmpty
        }

        It "Leaves a user alone that has the name of the login" {
            $destPermissions | Where-Object { $PSItem.Grantee -eq $userLoginName -and $PSItem.Permission -eq "VIEW DATABASE STATE" } | Should -Not -BeNullOrEmpty
            $destPermissions | Where-Object { $PSItem.Grantee -eq $userLoginName -and $PSItem.Permission -eq "CONNECT" } | Should -Not -BeNullOrEmpty
        }

        It "Adds the user to the database roles of the source user" {
            $destRoleMembers | Should -Contain "dbatoolsci_user"
        }

        It "Syncs the permissions to the user of the login when the users have different names" {
            $destPermissions | Where-Object { $PSItem.Grantee -eq "dbatoolsci_destuser" -and $PSItem.Permission -eq "CREATE VIEW" } | Should -Not -BeNullOrEmpty
            $destPermissions | Where-Object { $PSItem.Grantee -eq "dbatoolsci_destuser" -and $PSItem.Permission -eq "CREATE FUNCTION" } | Should -BeNullOrEmpty
            $destUserNames | Should -Not -Contain "dbatoolsci_sourceuser"
        }
    }

    BeforeDiscovery {
        # Databases whose names differ only in case exist on a case sensitive instance only. No CI environment has such an
        # instance, so InstanceCaseSensitive comes from a lab configuration, as for the tests of Copy-DbaLogin, and these
        # tests skip themselves everywhere else. The value decides a Skip, so it has to exist at discovery time.
        $hasCaseSensitive = -not [string]::IsNullOrWhiteSpace($TestConfig.InstanceCaseSensitive)
    }

    Context "When databases on a case sensitive instance differ only in case" -Skip:(-not $hasCaseSensitive) {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # The users of a login were looked up by the name of the database with keys that ignore case. So two databases
            # whose names differ only in case got the user of one of them, which in the other one is the user of another
            # login: that user got the permissions, and the permissions were compared with its own.
            # Two logins whose users have the name of each other's user in the other database of a pair, so that each one is
            # the other login of the other one. The first one is synced to the case sensitive instance, the second one from it.
            $csRandom = Get-Random
            $csInstance = $TestConfig.InstanceCaseSensitive
            $csToLogin = "dbatoolsci_csto_$csRandom"
            $csBackLogin = "dbatoolsci_csback_$csRandom"
            $csPassword = ConvertTo-SecureString -String "dbatools.IO!$csRandom" -AsPlainText -Force
            # Which of the two users the keys kept depends on the order of the databases. So the other instance has the first
            # database of one pair, in upper case, and the second database of the other pair, in lower case: with either
            # order one of them got the wrong user.
            $csDbAUpper = "dbatoolsci_CsDbA_$csRandom"
            $csDbALower = $csDbAUpper.ToLowerInvariant()
            $csDbBUpper = "dbatoolsci_CsDbB_$csRandom"
            $csDbBLower = $csDbBUpper.ToLowerInvariant()
            $csDatabases = @(
                $csDbAUpper,
                $csDbALower,
                $csDbBUpper,
                $csDbBLower
            )
            $ciDatabases = @(
                $csDbAUpper,
                $csDbBLower
            )

            $splatCsLogin = @{
                SqlInstance    = $TestConfig.InstanceMulti1, $csInstance
                Login          = $csToLogin, $csBackLogin
                SecurePassword = $csPassword
            }
            $null = New-DbaLogin @splatCsLogin

            # The second database of each pair is created under a name of its own and renamed, because the names of the
            # files come from the name of the database, and NTFS ignores case.
            $null = New-DbaDatabase -SqlInstance $csInstance -Name $csDbAUpper, $csDbBUpper, "dbatoolsci_cstmpa_$csRandom", "dbatoolsci_cstmpb_$csRandom"
            $null = Invoke-DbaQuery -SqlInstance $csInstance -Query "ALTER DATABASE [dbatoolsci_cstmpa_$csRandom] MODIFY NAME = [$csDbALower]; ALTER DATABASE [dbatoolsci_cstmpb_$csRandom] MODIFY NAME = [$csDbBLower]"
            # In the databases in upper case the user of the first login has the name in upper case, in the others the user
            # of the second login. The user of the first login has a permission that the source user of the second login
            # does not have, and the user of the second login is a member of the role that the first login gets.
            foreach ($csDb in $csDatabases) {
                if ($csDb -ceq $csDbAUpper -or $csDb -ceq $csDbBUpper) {
                    $csToUser = "dbatoolsci_CsUser"
                    $csBackUser = "dbatoolsci_csuser"
                } else {
                    $csToUser = "dbatoolsci_csuser"
                    $csBackUser = "dbatoolsci_CsUser"
                }
                $csUserSql = @"
CREATE USER [$csToUser] FOR LOGIN [$csToLogin];
CREATE USER [$csBackUser] FOR LOGIN [$csBackLogin];
GRANT CREATE PROCEDURE TO [$csToUser];
CREATE ROLE [dbatoolsci_csrole];
ALTER ROLE [dbatoolsci_csrole] ADD MEMBER [$csBackUser];
"@
                $splatCsUser = @{
                    SqlInstance = $csInstance
                    Database    = $csDb
                    Query       = $csUserSql
                }
                $null = Invoke-DbaQuery @splatCsUser
            }

            # On the other instance, the source user of the first login has CONTROL and is a member of the role. The user of
            # the second login has the permission that only the users of the first login have on the case sensitive instance.
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Name $ciDatabases
            $ciUserSql = @"
CREATE USER [dbatoolsci_cstouser] FOR LOGIN [$csToLogin];
GRANT CONTROL TO [dbatoolsci_cstouser];
CREATE ROLE [dbatoolsci_csrole];
ALTER ROLE [dbatoolsci_csrole] ADD MEMBER [dbatoolsci_cstouser];
CREATE USER [dbatoolsci_csbackuser] FOR LOGIN [$csBackLogin];
GRANT CREATE PROCEDURE TO [dbatoolsci_csbackuser];
"@
            foreach ($ciDb in $ciDatabases) {
                $splatCiUser = @{
                    SqlInstance = $TestConfig.InstanceMulti1
                    Database    = $ciDb
                    Query       = $ciUserSql
                }
                $null = Invoke-DbaQuery @splatCiUser
            }

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            # The second login first: the sync of the first one revokes the permission of its users that the second one
            # needs, because the other instance knows each pair as one database.
            $splatSyncBack = @{
                Source      = $csInstance
                Destination = $TestConfig.InstanceMulti1
                Login       = $csBackLogin
            }
            $csBackResult = Sync-DbaLoginPermission @splatSyncBack
            $csBackWarnings = $WarnVar
            $splatSyncTo = @{
                Source      = $TestConfig.InstanceMulti1
                Destination = $csInstance
                Login       = $csToLogin
            }
            $csToResult = Sync-DbaLoginPermission @splatSyncTo
            $csToWarnings = $WarnVar

            $csPermissionSql = @"
SELECT DB_NAME() AS DatabaseName, grantee.name AS Grantee, SUSER_SNAME(grantee.sid) AS LoginName, perm.permission_name AS Permission
FROM sys.database_permissions AS perm
INNER JOIN sys.database_principals AS grantee ON grantee.principal_id = perm.grantee_principal_id
WHERE perm.class = 0
"@
            $csRoleMemberSql = @"
SELECT DB_NAME() AS DatabaseName, dbrole.name AS RoleName, dbmember.name AS MemberName, SUSER_SNAME(dbmember.sid) AS LoginName
FROM sys.database_role_members AS rolemember
INNER JOIN sys.database_principals AS dbrole ON dbrole.principal_id = rolemember.role_principal_id
INNER JOIN sys.database_principals AS dbmember ON dbmember.principal_id = rolemember.member_principal_id
"@
            $csPermissions = foreach ($csDb in $csDatabases) {
                $splatCsPermission = @{
                    SqlInstance = $csInstance
                    Database    = $csDb
                    Query       = $csPermissionSql
                }
                Invoke-DbaQuery @splatCsPermission
            }
            $csRoleMembers = foreach ($csDb in $csDatabases) {
                $splatCsRoleMember = @{
                    SqlInstance = $csInstance
                    Database    = $csDb
                    Query       = $csRoleMemberSql
                }
                Invoke-DbaQuery @splatCsRoleMember
            }
            $ciPermissions = foreach ($ciDb in $ciDatabases) {
                $splatCiPermission = @{
                    SqlInstance = $TestConfig.InstanceMulti1
                    Database    = $ciDb
                    Query       = $csPermissionSql
                }
                Invoke-DbaQuery @splatCiPermission
            }
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $splatCsCleanup = @{
                SqlInstance = $csInstance
                Database    = $csDatabases
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaDatabase @splatCsCleanup
            $splatCiCleanup = @{
                SqlInstance = $TestConfig.InstanceMulti1
                Database    = $ciDatabases
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaDatabase @splatCiCleanup
            $splatCsLoginCleanup = @{
                SqlInstance = $TestConfig.InstanceMulti1, $csInstance
                Login       = $csToLogin, $csBackLogin
                Force       = $true
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaLogin @splatCsLoginCleanup

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Syncs both logins without a warning" {
            $csBackWarnings | Should -BeNullOrEmpty
            $csToWarnings | Should -BeNullOrEmpty
            @($csBackResult).Count | Should -Be 1
            @($csToResult).Count | Should -Be 1
            $csBackResult.Status | Should -Be "Successful"
            $csToResult.Status | Should -Be "Successful"
        }

        It "Grants the permissions of the source user to the user of the login in the database of the same name" {
            $csToControl = @($csPermissions | Where-Object { $PSItem.Permission -eq "CONTROL" -and $PSItem.LoginName -eq $csToLogin })
            $csToControl.Count | Should -Be 2
            $csToControl.DatabaseName -ccontains $csDbAUpper | Should -BeTrue
            $csToControl.DatabaseName -ccontains $csDbBLower | Should -BeTrue
        }

        It "Grants nothing to the user of another login whose name differs only in case" {
            $csPermissions | Where-Object { $PSItem.Permission -eq "CONTROL" -and $PSItem.LoginName -eq $csBackLogin } | Should -BeNullOrEmpty
        }

        It "Adds the user of the login to a role of which a user whose name differs only in case is a member" {
            $csToMembers = @($csRoleMembers | Where-Object { $PSItem.RoleName -eq "dbatoolsci_csrole" -and $PSItem.LoginName -eq $csToLogin })
            $csToMembers.Count | Should -Be 2
            $csToMembers.DatabaseName -ccontains $csDbAUpper | Should -BeTrue
            $csToMembers.DatabaseName -ccontains $csDbBLower | Should -BeTrue
        }

        It "Compares the permissions with the source user of the login in the database of the same name" {
            # The source users of the second login do not have the permission, the users of the same name of the first login do.
            @($ciPermissions | Where-Object { $PSItem.Permission -eq "CONNECT" -and $PSItem.LoginName -eq $csBackLogin }).Count | Should -Be 2
            $ciPermissions | Where-Object { $PSItem.Permission -eq "CREATE PROCEDURE" -and $PSItem.LoginName -eq $csBackLogin } | Should -BeNullOrEmpty
        }
    }

    Context "When the pipeline ends at the first login" {
        BeforeAll {
            # The command runs in a runspace of its own, created by the PowerShell API without a host. There
            # Write-Progress puts every record into Streams.Progress, so a bar that was never completed shows
            # as an Id whose last record is not a completed one. Select-Object -First 1 stops the command at
            # the result of the first login. The runspace imports the manifest: an import of the psm1 without a
            # command line skips the type data.
            $splatFirstLogin = @{
                Source      = $TestConfig.InstanceMulti1
                Destination = $TestConfig.InstanceMulti2
                Login       = $DBUserName
            }
            if ($TestConfig.SqlCred) {
                $splatFirstLogin.SourceSqlCredential = $TestConfig.SqlCred
                $splatFirstLogin.DestinationSqlCredential = $TestConfig.SqlCred
            }
            $syncRunspace = [runspacefactory]::CreateRunspace()
            $syncRunspace.Open()
            $importShell = [powershell]::Create()
            $importShell.Runspace = $syncRunspace
            $manifestPath = Join-Path -Path (Get-Module -Name $ModuleName | Select-Object -First 1).ModuleBase -ChildPath "$ModuleName.psd1"
            $null = $importShell.AddCommand("Import-Module").AddParameter("Name", $manifestPath).Invoke()
            $importShell.Dispose()

            $syncShell = [powershell]::Create()
            $syncShell.Runspace = $syncRunspace
            $firstLogin = $syncShell.AddCommand("Sync-DbaLoginPermission").AddParameters($splatFirstLogin).AddCommand("Select-Object").AddParameter("First", 1).Invoke()
            $syncRecords = @($syncShell.Streams.Progress)
            $syncShell.Dispose()
            $syncRunspace.Dispose()
        }

        It "Syncs the login" {
            $firstLogin.Status | Should -Be "Successful"
        }

        It "Completes its progress bar" {
            # An Id stays on screen when its last record is not a completed one. Windows PowerShell completes its
            # own bar for loading modules with Id 0 as well, so a completed record somewhere is not enough.
            $openIds = $syncRecords | Group-Object -Property ActivityId | Where-Object { @($PSItem.Group)[-1].RecordType -ne "Completed" } | Select-Object -ExpandProperty Name
            $syncRecords | Where-Object Activity -like "Executing Sync-DbaLoginPermission*" | Should -Not -BeNullOrEmpty
            $openIds | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "The connections of the caller are left in the database they were in (#10555)" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $contextDbName = "dbatoolsci_ctx_syncperm_$(Get-Random)"
            $contextLoginName = "dbatoolsci_ctx_login_$(Get-Random)"

            # The login exists on both servers because the sync does not create logins. The database exists
            # on both servers and the login has a user in it on the source, so the permission sync walks the
            # database level collections of both servers - which is the leak this context guards against.
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Name $contextDbName
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Name $contextDbName
            foreach ($contextInstance in $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2) {
                $splatContextLogin = @{
                    SqlInstance = $contextInstance
                    Login       = $contextLoginName
                    Password    = (ConvertTo-SecureString -String "dbatools.IO" -AsPlainText -Force)
                }
                $null = New-DbaLogin @splatContextLogin
            }
            $splatContextUser = @{
                SqlInstance = $TestConfig.InstanceMulti1
                Database    = $contextDbName
                Login       = $contextLoginName
                Username    = $contextLoginName
            }
            $null = New-DbaDbUser @splatContextUser

            # Only a non-pooled connection can show this. A pooled connection that is closed between two
            # calls reconnects at its default database, which puts the database back by accident.
            $sourceCallerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 -NonPooledConnection
            $destCallerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2 -NonPooledConnection
            $sourceContextBefore = $sourceCallerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()")
            $destContextBefore = $destCallerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()")

            $splatSyncPermission = @{
                Source      = $sourceCallerServer
                Destination = $destCallerServer
                Login       = $contextLoginName
            }
            $contextResult = Sync-DbaLoginPermission @splatSyncPermission

            $sourceContextAfter = $sourceCallerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()")
            $destContextAfter = $destCallerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()")

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $sourceCallerServer | Disconnect-DbaInstance
            $null = $destCallerServer | Disconnect-DbaInstance
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Database $contextDbName -ErrorAction SilentlyContinue
            $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Login $contextLoginName -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "syncs the database user of the login" {
            # Only a command that really did something can move the connections, so without this the
            # assertions below would pass for the wrong reason.
            $contextResult.Status | Should -Be "Successful"
            (Get-DbaDbUser -SqlInstance $TestConfig.InstanceMulti2 -Database $contextDbName).Name | Should -Contain $contextLoginName
        }

        It "leaves the source connection in the database it was in" {
            $sourceContextAfter | Should -Be $sourceContextBefore
        }

        It "leaves the destination connection in the database it was in" {
            $destContextAfter | Should -Be $destContextBefore
        }
    }
}