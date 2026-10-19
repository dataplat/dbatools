#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaLogin",
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
                "ExcludeSystemLogins",
                "SyncSaName",
                "OutFile",
                "InputObject",
                "LoginRenameHashtable",
                "KillActiveConnection",
                "ExcludePermissionSync",
                "ExcludeDatabaseMapping",
                "NewSid",
                "ObjectLevel",
                "Force",
                "UpdateExisting",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "OutFile behavior" {
        BeforeAll {
            Mock Test-FunctionInterrupt { $false } -ModuleName dbatools
            Mock Get-DbaLogin {
                [PSCustomObject]@{
                    Name = "tester"
                }
            } -ModuleName dbatools
            Mock Export-DbaLogin {
                $FilePath
            } -ModuleName dbatools
        }

        It "passes ExcludeDatabase to Export-DbaLogin when ExcludeDatabaseMapping is used" {
            $null = Copy-DbaLogin -Source "sql1" -Login "tester" -OutFile "C:\temp\logins.sql" -ExcludeDatabaseMapping

            Should -Invoke Export-DbaLogin -Times 1 -Exactly -ModuleName dbatools -ParameterFilter {
                $FilePath -eq "C:\temp\logins.sql" -and $ExcludeDatabase
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # drop all objects
        Function Initialize-TestLogin {
            Param ($Instance, $Login)
            Get-DbaProcess -SqlInstance $Instance -Login $Login | Stop-DbaProcess
            if ($l = Get-DbaLogin -SqlInstance $Instance -Login $Login) {
                foreach ($map in $l.EnumDatabaseMappings()) {
                    $null = Invoke-DbaQuery -SqlInstance $Instance -Database $map.DbName -Query "DROP USER [$($map.Username)]"
                }
                $l.Drop()
            }
            $dropUserQuery = "IF EXISTS (SELECT * FROM sys.database_principals WHERE name = '{0}') DROP USER [{0}]" -f $Login
            $null = Invoke-DbaQuery -SqlInstance $instance -Database tempdb -Query $dropUserQuery
        }
        $logins = "claudio", "port", "tester", "tester_new"
        $dropTableQuery = "IF EXISTS (SELECT * FROM sys.tables WHERE name = 'tester_table') DROP TABLE tester_table"
        foreach ($instance in $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2) {
            foreach ($login in $logins) {
                Initialize-TestLogin -Instance $instance -Login $login
            }
            $null = Invoke-DbaQuery -SqlInstance $instance -Database tempdb -Query $dropTableQuery

        }

        # create objects
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -InputFile "$($TestConfig.appveyorlabrepo)\sql2008-scripts\logins.sql"

        $tableQuery = @("CREATE TABLE tester_table (a int)", "CREATE USER tester FOR LOGIN tester", "GRANT INSERT ON tester_table TO tester;")
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -Query ($tableQuery -join '; ')
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Database tempdb -Query $tableQuery[0]

        # we want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    BeforeEach {
        # cleanup targets
        Initialize-TestLogin -Instance $TestConfig.InstanceCopy2 -Login tester
        Initialize-TestLogin -Instance $TestConfig.InstanceCopy1 -Login tester_new
    }
    AfterAll {
        # we want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # cleanup everything
        $logins = "claudio", "port", "tester", "tester_new"

        foreach ($instance in $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2) {
            foreach ($login in $logins) {
                Initialize-TestLogin -Instance $instance -Login $login
            }
            $null = Invoke-DbaQuery -SqlInstance $instance -Database tempdb -Query $dropTableQuery
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Copy login with the same properties." {
        It "Should copy successfully" {
            $results = Copy-DbaLogin -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -Login Tester
            $results.Status | Should -Be "Successful"
            $login1 = Get-DbaLogin -SqlInstance $TestConfig.InstanceCopy1 -login Tester
            $login2 = Get-DbaLogin -SqlInstance $TestConfig.InstanceCopy2 -login Tester

            $login2 | Should -Not -BeNullOrEmpty

            # Compare its value
            $login1.Name | Should -Be $login2.Name
            $login1.Language | Should -Be $login2.Language
            $login1.Credential | Should -Be $login2.Credential
            $login1.DefaultDatabase | Should -Be $login2.DefaultDatabase
            $login1.IsDisabled | Should -Be $login2.IsDisabled
            $login1.IsLocked | Should -Be $login2.IsLocked
            $login1.IsPasswordExpired | Should -Be $login2.IsPasswordExpired
            $login1.PasswordExpirationEnabled | Should -Be $login2.PasswordExpirationEnabled
            $login1.PasswordPolicyEnforced | Should -Be $login2.PasswordPolicyEnforced
            $login1.Sid | Should -Be $login2.Sid
            $login1.Status | Should -Be $login2.Status
        }

        It "Should login with newly created Sql Login (also tests credential login) and gets name" {
            $password = ConvertTo-SecureString -Force -AsPlainText tester1
            $cred = New-Object System.Management.Automation.PSCredential ("tester", $password)
            $s = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -SqlCredential $cred
            $s.Name | Should -Be $TestConfig.InstanceCopy1
        }
    }

    Context "No overwrite" {
        It "Should say skipped" {
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -InputFile "$($TestConfig.appveyorlabrepo)\sql2008-scripts\logins.sql"
            $results = Copy-DbaLogin -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -Login tester
            $results.Status | Should -Be "Skipped"
            $results.Notes | Should -Be "Already exists on destination"
        }
    }

    Context "ExcludeSystemLogins Parameter" {
        It "Should say skipped" {
            $results = Copy-DbaLogin -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -ExcludeSystemLogins
            $results.Status | Should -Contain 'Skipped'
            if (([DbaInstanceParameter]$TestConfig.InstanceCopy1).ComputerName -ne ([DbaInstanceParameter]$TestConfig.InstanceCopy2).ComputerName) {
                $results.Notes | Should -Contain 'Local machine name'
            } else {
                $results.Notes | Should -Contain 'System login'
            }
        }
    }

    Context "Supports pipe" {
        It "migrates the one tester login" {
            $results = Get-DbaLogin -SqlInstance $TestConfig.InstanceCopy1 -Login tester | Copy-DbaLogin -Destination $TestConfig.InstanceCopy2 -Force
            $results.Name | Should -Be "tester"
            $results.Status | Should -Be "Successful"
        }
    }

    Context "Supports cloning" {
        It "clones the one tester login" {
            $results = Copy-DbaLogin -Source $TestConfig.InstanceCopy1 -Login tester -Destination $TestConfig.InstanceCopy1 -Force -LoginRenameHashtable @{ tester = 'tester_new' } -NewSid
            $results.Name | Should -Be "tester_new"
            $results.Status | Should -Be "Successful"
            Get-DbaLogin -SqlInstance $TestConfig.InstanceCopy1 -Login tester_new | Should -Not -BeNullOrEmpty
        }
        It "clones the one tester login using pipe" {
            $results = Get-DbaLogin -SqlInstance $TestConfig.InstanceCopy1 -Login tester | Copy-DbaLogin -Destination $TestConfig.InstanceCopy1 -Force -LoginRenameHashtable @{ tester = 'tester_new' } -NewSid
            $results.Name | Should -Be "tester_new"
            $results.Status | Should -Be "Successful"
            Get-DbaLogin -SqlInstance $TestConfig.InstanceCopy1 -Login tester_new | Should -Not -BeNullOrEmpty
        }
        It "clones the one tester login to a different server with a new name" {
            'tester', 'tester_new' | ForEach-Object {
                Initialize-TestLogin -Instance $TestConfig.InstanceCopy2 -Login $_
            }
            $results = Get-DbaLogin -SqlInstance $TestConfig.InstanceCopy1 -Login tester | Copy-DbaLogin -Destination $TestConfig.InstanceCopy2 -LoginRenameHashtable @{ tester = 'tester_new' }
            $results.Name | Should -Be "tester_new"
            $results.Status | Should -Be "Successful"
            $login = (Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2).Logins['tester_new']
            $login | Should -Not -BeNullOrEmpty
            $login | Remove-DbaLogin -Force
        }
    }

    Context "Supports db object permissions" {
        BeforeAll {
            $tempExportFile = [System.IO.Path]::GetTempFileName()
        }
        BeforeEach {
            'tester', 'tester_new' | ForEach-Object {
                Initialize-TestLogin -Instance $TestConfig.InstanceCopy2 -Login $_
            }
        }
        AfterAll {
            Remove-Item -Path $tempExportFile -Force
        }
        It "clones the one tester login with sysadmin permissions" {
            $results = Copy-DbaLogin -Source $TestConfig.InstanceCopy1 -Login tester -Destination $TestConfig.InstanceCopy2 -LoginRenameHashtable @{ tester = 'tester_new' }
            $results.Name | Should -Be "tester_new"
            $results.Status | Should -Be "Successful"
            $i2 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
            $login = $i2.Logins['tester_new']
            $login | Should -Not -BeNullOrEmpty
            $role = $i2.Roles['sysadmin']
            $role.EnumMemberNames() | Should -Contain $results.Name
        }
        It "clones the one tester login with object permissions" {
            $results = Copy-DbaLogin -Source $TestConfig.InstanceCopy1 -Login tester -Destination $TestConfig.InstanceCopy2 -LoginRenameHashtable @{ tester = 'tester_new' } -ObjectLevel
            $results.Name | Should -Be "tester_new"
            $results.Status | Should -Be "Successful"
            $i2 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
            $login = $i2.Logins['tester_new']
            $login | Should -Not -BeNullOrEmpty
            $permissions = Export-DbaUser -SqlInstance $TestConfig.InstanceCopy2 -Database tempdb -User tester_new -Passthru
            $permissions | Should -BeLike '*GRANT INSERT ON OBJECT::`[dbo`].`[tester_table`] TO `[tester_new`]*'
        }
        It "scripts out two tester login with object permissions" {
            $results = Copy-DbaLogin -Source $TestConfig.InstanceCopy1 -Login tester, port -OutFile $tempExportFile -ObjectLevel
            $results | Should -Be $tempExportFile
            $permissions = Get-Content $tempExportFile -Raw
            $permissions | Should -BeLike '*CREATE LOGIN `[tester`]*'
            $permissions | Should -Match "(ALTER SERVER ROLE \[sysadmin\] ADD MEMBER \[tester\]|EXEC sp_addsrvrolemember @rolename=N'sysadmin', @loginame=N'tester')"
            $permissions | Should -BeLike '*GRANT INSERT ON OBJECT::`[dbo`].`[tester_table`] TO `[tester`]*'
            $permissions | Should -BeLike '*CREATE LOGIN `[port`]*'
            $permissions | Should -BeLike '*GRANT CONNECT SQL TO `[port`]*'
        }
    }

    Context "Linux SQL Server protection for BUILTIN\Administrators" -Skip:(-not $TestConfig.instanceLinux) {
        It "Should skip BUILTIN\Administrators on Linux source with -Force" {
            $splatCopy = @{
                Source      = $TestConfig.instanceLinux
                Destination = $TestConfig.InstanceCopy1
                Login       = "BUILTIN\Administrators"
                Force       = $true
            }
            $results = Copy-DbaLogin @splatCopy
            $results.Status | Should -Be "Skipped"
            $results.Notes | Should -Be "BUILTIN\Administrators is a critical system login"
        }

        It "Should skip BUILTIN\Administrators on Linux destination with -Force" {
            $splatCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.instanceLinux
                Login       = "BUILTIN\Administrators"
                Force       = $true
            }
            $results = Copy-DbaLogin @splatCopy
            $results.Status | Should -Be "Skipped"
            $results.Notes | Should -Be "BUILTIN\Administrators is a critical system login"
        }
    }

    Context "Regression test for issue #9163 - Warn when login not found" {
        It "Should warn when specified login does not exist on source" {
            $splatCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Login       = "nonexistentlogin"
            }
            $result = Copy-DbaLogin @splatCopy -WarningVariable warn -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $warn | Should -Not -BeNullOrEmpty
            $warn | Should -BeLike "*nonexistentlogin*not found*"
        }

        It "Should warn for each non-existent login when multiple are specified" {
            $splatCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Login       = "nonexistent1", "nonexistent2"
            }
            $result = Copy-DbaLogin @splatCopy -WarningVariable warn -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $warn.Count | Should -Be 2
            $warn[0] | Should -BeLike "*nonexistent1*not found*"
            $warn[1] | Should -BeLike "*nonexistent2*not found*"
        }

        It "Should not warn when login exists" {
            $splatCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Login       = "tester"
            }
            $result = Copy-DbaLogin @splatCopy -WarningVariable warn -WarningAction SilentlyContinue
            $result.Status | Should -Be "Successful"
            $warn | Should -BeNullOrEmpty
        }
    }

    Context "Regression test for issue #8572 - Windows group lockout protection" {
        It "Should not throw when processing SQL logins with -Force" {
            # Verify SQL logins are not affected by Windows group checks
            $splatCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Login       = "tester"
                Force       = $true
            }
            $results = Copy-DbaLogin @splatCopy
            $results.Status | Should -Be "Successful"
        }

        It "Should handle Windows logins gracefully when not in a domain" {
            # This test verifies the code path doesn't break non-domain scenarios
            # In CI (non-domain), Windows logins typically fail earlier in the process
            # but the lockout protection code should not introduce new errors
            {
                $splatCopy = @{
                    Source      = $TestConfig.InstanceCopy1
                    Destination = $TestConfig.InstanceCopy2
                    Login       = "NT AUTHORITY\SYSTEM"
                    Force       = $true
                }
                Copy-DbaLogin @splatCopy -WarningAction SilentlyContinue
            } | Should -Not -Throw
        }

        It "Should verify the safety check logic exists for Windows groups" {
            # This test verifies the safety check added in issue #8572
            # The safety check should skip Windows groups that provide the current user's only access
            # when those groups have high privileges (sysadmin, securityadmin, or ALTER ANY LOGIN)

            # Note: Full automated testing requires:
            # 1. A Windows domain environment with AD groups
            # 2. A test user that accesses SQL only via an AD group (no direct login)
            # 3. The ability to test the actual lockout scenario

            # This test verifies that the protection code exists and is properly structured
            # Manual testing should be performed in a domain environment to verify the protection works

            $testPath = $PSScriptRoot
            if (-not $testPath) {
                $testPath = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
            }
            $moduleRoot = Split-Path -Path $testPath -Parent
            $functionPath = Join-Path -Path $moduleRoot -ChildPath "public\Copy-DbaLogin.ps1"
            $functionContent = Get-Content -Path $functionPath -Raw
            $functionContent | Should -BeLike '*LoginType -eq "WindowsGroup"*'
            $functionContent | Should -BeLike '*potential lockout risk*'
            $functionContent | Should -BeLike '*xp_logininfo*'
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "The connections of the caller are left in the database they were in (#10555)" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $contextDbName = "dbatoolsci_ctx_copylogin_$(Get-Random)"
            $contextLoginName = "dbatoolsci_ctx_login_$(Get-Random)"

            # The database exists on both servers and the login has a user in it on the source, so the
            # permission sync walks the database level collections of both servers - which is the leak
            # this context guards against.
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Name $contextDbName
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Name $contextDbName
            $splatContextLogin = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Login       = $contextLoginName
                Password    = (ConvertTo-SecureString -String "dbatools.IO" -AsPlainText -Force)
            }
            $null = New-DbaLogin @splatContextLogin
            $splatContextUser = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Database    = $contextDbName
                Login       = $contextLoginName
                Username    = $contextLoginName
            }
            $null = New-DbaDbUser @splatContextUser

            # Only a non-pooled connection can show this. A pooled connection that is closed between two
            # calls reconnects at its default database, which puts the database back by accident.
            $sourceCallerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -NonPooledConnection
            $destCallerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -NonPooledConnection
            $sourceContextBefore = $sourceCallerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()")
            $destContextBefore = $destCallerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()")

            $splatCopyLogin = @{
                Source      = $sourceCallerServer
                Destination = $destCallerServer
                Login       = $contextLoginName
            }
            $contextResult = Copy-DbaLogin @splatCopyLogin

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
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Database $contextDbName -ErrorAction SilentlyContinue
            $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Login $contextLoginName -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "copies the login and syncs its database user" {
            # Only a command that really did something can move the connections, so without this the
            # assertions below would pass for the wrong reason.
            $contextResult.Status | Should -Be "Successful"
            (Get-DbaLogin -SqlInstance $TestConfig.InstanceCopy2 -Login $contextLoginName).Name | Should -Be $contextLoginName
            (Get-DbaDbUser -SqlInstance $TestConfig.InstanceCopy2 -Database $contextDbName).Name | Should -Contain $contextLoginName
        }

        It "leaves the source connection in the database it was in" {
            $sourceContextAfter | Should -Be $sourceContextBefore
        }

        It "leaves the destination connection in the database it was in" {
            $destContextAfter | Should -Be $destContextBefore
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Existing logins are updated in place with -UpdateExisting (#10772)" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $updateLoginName = "dbatoolsci_update_$(Get-Random)"
            $sidLoginName = "dbatoolsci_updatesid_$(Get-Random)"
            $sourcePassword = "dbatools.IO.Source1"

            # Password policy on, as CREATE LOGIN has it by default. SQL Server refuses a hashed password for such
            # a login, which is the case the update has to handle.
            $splatSourceLogin = @{
                SqlInstance               = $TestConfig.InstanceCopy1
                Login                     = $updateLoginName
                SecurePassword            = (ConvertTo-SecureString -String $sourcePassword -AsPlainText -Force)
                PasswordPolicyEnforced    = $true
                PasswordExpirationEnabled = $true
                Language                  = "us_english"
            }
            $sourceLogin = New-DbaLogin @splatSourceLogin

            # The same SID, so the update in place applies, but every property it compares differs except the policy.
            $splatDestLogin = @{
                SqlInstance            = $TestConfig.InstanceCopy2
                Login                  = $updateLoginName
                SecurePassword         = (ConvertTo-SecureString -String "dbatools.IO.Dest1" -AsPlainText -Force)
                Sid                    = $sourceLogin.Sid
                PasswordPolicyEnforced = $true
                DefaultDatabase        = "tempdb"
                Language               = "Deutsch"
                Disabled               = $true
            }
            $null = New-DbaLogin @splatDestLogin

            # Created separately on both instances, so the SIDs differ.
            foreach ($instance in $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2) {
                $splatSidLogin = @{
                    SqlInstance    = $instance
                    Login          = $sidLoginName
                    SecurePassword = (ConvertTo-SecureString -String "dbatools.IO.Sid1" -AsPlainText -Force)
                }
                $null = New-DbaLogin @splatSidLogin
            }

            # Read from sys.sql_logins, so the assertions don't depend on cached SMO objects. The principal_id
            # changes when a login is dropped and recreated.
            $loginStateQuery = @"
SELECT principal_id,
       CONVERT(VARCHAR(514), password_hash, 1) AS password_hash,
       CONVERT(VARCHAR(514), sid, 1) AS sid,
       is_policy_checked,
       is_expiration_checked,
       default_database_name,
       default_language_name,
       is_disabled,
       CONVERT(VARCHAR(30), LOGINPROPERTY(name, 'PasswordLastSetTime'), 121) AS password_last_set
FROM sys.sql_logins
WHERE name = @name
"@
            $splatSourceState = @{
                SqlInstance  = $TestConfig.InstanceCopy1
                Query        = $loginStateQuery
                SqlParameter = @{ name = $updateLoginName }
            }
            $splatDestState = @{
                SqlInstance  = $TestConfig.InstanceCopy2
                Query        = $loginStateQuery
                SqlParameter = @{ name = $updateLoginName }
            }
            $splatSidSourceState = @{
                SqlInstance  = $TestConfig.InstanceCopy1
                Query        = $loginStateQuery
                SqlParameter = @{ name = $sidLoginName }
            }
            $splatSidDestState = @{
                SqlInstance  = $TestConfig.InstanceCopy2
                Query        = $loginStateQuery
                SqlParameter = @{ name = $sidLoginName }
            }
            $destStateBefore = Invoke-DbaQuery @splatDestState

            $splatUpdate = @{
                Source         = $TestConfig.InstanceCopy1
                Destination    = $TestConfig.InstanceCopy2
                Login          = $updateLoginName
                UpdateExisting = $true
            }

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $splatRemoveLogin = @{
                SqlInstance = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
                Login       = $updateLoginName, $sidLoginName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaLogin @splatRemoveLogin

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "updates the password and the properties of the existing login without dropping it" {
            $result = Copy-DbaLogin @splatUpdate

            $WarnVar | Should -BeNullOrEmpty
            $result.Status | Should -Be "Successful"
            $result.Notes | Should -Be "Updated in place: password, CHECK_EXPIRATION, default database, default language, disabled state"

            $sourceState = Invoke-DbaQuery @splatSourceState
            $destState = Invoke-DbaQuery @splatDestState
            $destState.principal_id | Should -Be $destStateBefore.principal_id
            $destState.password_hash | Should -Be $sourceState.password_hash
            $destState.is_policy_checked | Should -BeTrue
            $destState.is_expiration_checked | Should -BeTrue
            $destState.default_database_name | Should -Be $sourceState.default_database_name
            $destState.default_language_name | Should -Be "us_english"
            $destState.is_disabled | Should -BeFalse
        }

        It "leaves an identical login untouched on a repeated run" {
            $stateBefore = Invoke-DbaQuery @splatDestState

            $result = Copy-DbaLogin @splatUpdate

            $WarnVar | Should -BeNullOrEmpty
            $result.Status | Should -Be "Skipped"
            $result.Notes | Should -Be "Login is identical on source and destination"
            $stateAfter = Invoke-DbaQuery @splatDestState
            $stateAfter.principal_id | Should -Be $stateBefore.principal_id
            $stateAfter.password_last_set | Should -Be $stateBefore.password_last_set
        }

        It "skips a login with a different SID with a warning" {
            $sidBefore = (Invoke-DbaQuery @splatSidDestState).sid

            $splatSidUpdate = @{
                Source         = $TestConfig.InstanceCopy1
                Destination    = $TestConfig.InstanceCopy2
                Login          = $sidLoginName
                UpdateExisting = $true
                WarningAction  = "SilentlyContinue"
            }
            $result = Copy-DbaLogin @splatSidUpdate

            $result.Status | Should -Be "Skipped"
            $result.Notes | Should -Be "Different SID on destination, use -Force to drop and recreate"
            $WarnVar | Should -BeLike "*$sidLoginName*different SID*"
            (Invoke-DbaQuery @splatSidDestState).sid | Should -Be $sidBefore
        }

        It "drops and recreates a login with a different SID when -Force is also used" {
            $splatSidForce = @{
                Source         = $TestConfig.InstanceCopy1
                Destination    = $TestConfig.InstanceCopy2
                Login          = $sidLoginName
                UpdateExisting = $true
                Force          = $true
            }
            $result = Copy-DbaLogin @splatSidForce

            $WarnVar | Should -BeNullOrEmpty
            $result.Status | Should -Be "Successful"
            (Invoke-DbaQuery @splatSidDestState).sid | Should -Be (Invoke-DbaQuery @splatSidSourceState).sid
        }

        # The last test of the context: SQL Server 2025 converts an older password hash to its own format at the
        # first successful login, so after this the hashes differ again although the password is the same.
        It "lets the login connect to the destination with the password of the source" {
            $splatConnect = @{
                SqlInstance         = $TestConfig.InstanceCopy2
                SqlCredential       = New-Object System.Management.Automation.PSCredential ($updateLoginName, (ConvertTo-SecureString -String $sourcePassword -AsPlainText -Force))
                NonPooledConnection = $true
            }
            $loginServer = Connect-DbaInstance @splatConnect
            try {
                $loginServer.ConnectionContext.ExecuteScalar("SELECT SUSER_SNAME()") | Should -Be $updateLoginName
            } finally {
                # An open session would keep AfterAll from removing the login.
                $null = $loginServer | Disconnect-DbaInstance
            }
        }
    }

    Context "A failing statement rolls the whole update in place back (#10772)" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $rollbackLoginName = "dbatoolsci_rollback_$(Get-Random)"
            $rollbackTriggerName = "dbatoolsci_rollback_trigger_$(Get-Random)"
            $dropTriggerQuery = "IF EXISTS (SELECT * FROM sys.server_triggers WHERE name = N'$rollbackTriggerName') DROP TRIGGER [$rollbackTriggerName] ON ALL SERVER"

            # Source with the password policy off and disabled, destination with the policy on and enabled. The update
            # turns the policy off, sets the hash and disables the login, and the destination keeps the policy off.
            $splatSourceLogin = @{
                SqlInstance    = $TestConfig.InstanceCopy1
                Login          = $rollbackLoginName
                SecurePassword = (ConvertTo-SecureString -String "dbatools.IO.Source2" -AsPlainText -Force)
                Disabled       = $true
            }
            $sourceLogin = New-DbaLogin @splatSourceLogin
            $splatDestLogin = @{
                SqlInstance            = $TestConfig.InstanceCopy2
                Login                  = $rollbackLoginName
                SecurePassword         = (ConvertTo-SecureString -String "dbatools.IO.Dest2" -AsPlainText -Force)
                Sid                    = $sourceLogin.Sid
                PasswordPolicyEnforced = $true
            }
            $null = New-DbaLogin @splatDestLogin

            # Fails only the last statement of the update, ALTER LOGIN ... DISABLE, and only for this login, so the
            # statements before it have already run. A trigger runs with XACT_ABORT ON, so a THROW would let the server
            # roll the transaction back by itself. RAISERROR with XACT_ABORT OFF leaves the transaction open, as an
            # error of the statement itself does, so only the rollback of the command can put the login back.
            $createTriggerQuery = @"
CREATE TRIGGER [$rollbackTriggerName] ON ALL SERVER FOR ALTER_LOGIN AS
IF EVENTDATA().value('(/EVENT_INSTANCE/ObjectName)[1]', 'sysname') = N'$rollbackLoginName'
    AND EVENTDATA().value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'nvarchar(max)') LIKE N'%DISABLE%'
BEGIN
    SET XACT_ABORT OFF;
    RAISERROR(N'dbatoolsci: refused by the test trigger', 16, 1);
END
"@
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Query $createTriggerQuery

            $loginStateQuery = @"
SELECT CONVERT(VARCHAR(514), password_hash, 1) AS password_hash,
       is_policy_checked,
       is_expiration_checked,
       is_disabled
FROM sys.sql_logins
WHERE name = @name
"@
            $splatSourceState = @{
                SqlInstance  = $TestConfig.InstanceCopy1
                Query        = $loginStateQuery
                SqlParameter = @{ name = $rollbackLoginName }
            }
            $splatDestState = @{
                SqlInstance  = $TestConfig.InstanceCopy2
                Query        = $loginStateQuery
                SqlParameter = @{ name = $rollbackLoginName }
            }
            # The update runs on a connection of the test, so the test can see whether a transaction was left open on
            # it. It is not pooled, so it keeps its session between the commands.
            $destCallerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -NonPooledConnection
            $splatUpdate = @{
                Source         = $TestConfig.InstanceCopy1
                Destination    = $destCallerServer
                Login          = $rollbackLoginName
                UpdateExisting = $true
            }
            $stateBefore = Invoke-DbaQuery @splatDestState
            $sourceState = Invoke-DbaQuery @splatSourceState

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $failedResult = Copy-DbaLogin @splatUpdate -WarningVariable failedWarn
            $tranCountAfterFailure = $destCallerServer.ConnectionContext.ExecuteScalar("SELECT @@TRANCOUNT")
            if ($tranCountAfterFailure -gt 0) {
                # Left open by the command, so the uncommitted update would block every read below. Closing the
                # connection rolls it back, so the test fails instead of waiting.
                $null = $destCallerServer | Disconnect-DbaInstance
            }
            $stateAfterFailure = Invoke-DbaQuery @splatDestState -EnableException

            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Query $dropTriggerQuery -EnableException
            $retryResult = Copy-DbaLogin @splatUpdate -WarningVariable retryWarn
            $stateAfterRetry = Invoke-DbaQuery @splatDestState -EnableException
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $destCallerServer | Disconnect-DbaInstance
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Query $dropTriggerQuery
            $splatRemoveLogin = @{
                SqlInstance = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
                Login       = $rollbackLoginName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaLogin @splatRemoveLogin

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "reports the update as failed with the error of the statement" {
            $failedWarn | Should -BeNullOrEmpty
            $failedResult.Status | Should -Be "Failed"
            $failedResult.Notes | Should -BeLike "*refused by the test trigger*"
        }

        It "leaves no transaction open on the connection of the caller" {
            $tranCountAfterFailure | Should -Be 0
        }

        It "leaves the login as it was, with the password policy still on" {
            $stateAfterFailure.password_hash | Should -Be $stateBefore.password_hash
            $stateAfterFailure.is_policy_checked | Should -BeTrue
            $stateAfterFailure.is_disabled | Should -BeFalse
        }

        It "applies the whole update on the next run" {
            $retryWarn | Should -BeNullOrEmpty
            $retryResult.Status | Should -Be "Successful"
            $retryResult.Notes | Should -Be "Updated in place: password, CHECK_POLICY, disabled state"
            $stateAfterRetry.password_hash | Should -Be $sourceState.password_hash
            $stateAfterRetry.is_policy_checked | Should -BeFalse
            $stateAfterRetry.is_expiration_checked | Should -BeFalse
            $stateAfterRetry.is_disabled | Should -BeTrue
        }
    }

    Context "A failing statement inside a transaction of the caller takes back only the update (#10772)" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $callerLoginName = "dbatoolsci_callertran_$(Get-Random)"
            $callerTriggerName = "dbatoolsci_callertran_trigger_$(Get-Random)"
            $dropCallerTriggerQuery = "IF EXISTS (SELECT * FROM sys.server_triggers WHERE name = N'$callerTriggerName') DROP TRIGGER [$callerTriggerName] ON ALL SERVER"

            # As in the context above: the update turns the policy off, sets the hash and disables the login, and the
            # trigger refuses the last statement with the transaction left open.
            $splatSourceLogin = @{
                SqlInstance    = $TestConfig.InstanceCopy1
                Login          = $callerLoginName
                SecurePassword = (ConvertTo-SecureString -String "dbatools.IO.Source3" -AsPlainText -Force)
                Disabled       = $true
            }
            $sourceLogin = New-DbaLogin @splatSourceLogin
            $splatDestLogin = @{
                SqlInstance            = $TestConfig.InstanceCopy2
                Login                  = $callerLoginName
                SecurePassword         = (ConvertTo-SecureString -String "dbatools.IO.Dest3" -AsPlainText -Force)
                Sid                    = $sourceLogin.Sid
                PasswordPolicyEnforced = $true
            }
            $null = New-DbaLogin @splatDestLogin
            $createTriggerQuery = @"
CREATE TRIGGER [$callerTriggerName] ON ALL SERVER FOR ALTER_LOGIN AS
IF EVENTDATA().value('(/EVENT_INSTANCE/ObjectName)[1]', 'sysname') = N'$callerLoginName'
    AND EVENTDATA().value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'nvarchar(max)') LIKE N'%DISABLE%'
BEGIN
    SET XACT_ABORT OFF;
    RAISERROR(N'dbatoolsci: refused by the test trigger', 16, 1);
END
"@
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Query $createTriggerQuery

            # The caller opens a transaction and does work of its own in it, which a rollback of the whole transaction
            # would take back. The connection is not pooled, so the transaction stays on its session between the
            # commands, and the command updates the login in that transaction.
            $destCallerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -NonPooledConnection
            $destCallerServer.ConnectionContext.BeginTransaction()
            $null = $destCallerServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE #dbatoolsci_callerwork (id INT)")

            # Read on the connection of the caller, which sees the uncommitted changes of its own transaction and is not
            # blocked by them.
            $callerStateQuery = @"
SELECT @@TRANCOUNT AS tran_count,
       CASE WHEN OBJECT_ID(N'tempdb..#dbatoolsci_callerwork') IS NULL THEN 0 ELSE 1 END AS caller_work,
       CONVERT(VARCHAR(514), password_hash, 1) AS password_hash,
       is_policy_checked,
       is_disabled
FROM sys.sql_logins
WHERE name = N'$callerLoginName'
"@
            $stateBefore = $destCallerServer.Query($callerStateQuery)
            $splatUpdate = @{
                Source         = $TestConfig.InstanceCopy1
                Destination    = $destCallerServer
                Login          = $callerLoginName
                UpdateExisting = $true
            }

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $failedResult = Copy-DbaLogin @splatUpdate -WarningVariable failedWarn
            $stateAfterFailure = $destCallerServer.Query($callerStateQuery)
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # The caller takes its transaction back.
            if ($destCallerServer.ConnectionContext.ExecuteScalar("SELECT @@TRANCOUNT") -gt 0) {
                $destCallerServer.ConnectionContext.RollBackTransaction()
            }
            $null = $destCallerServer | Disconnect-DbaInstance
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Query $dropCallerTriggerQuery
            $splatRemoveLogin = @{
                SqlInstance = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
                Login       = $callerLoginName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaLogin @splatRemoveLogin

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "reports the update as failed with the error of the statement" {
            $failedWarn | Should -BeNullOrEmpty
            $failedResult.Status | Should -Be "Failed"
            $failedResult.Notes | Should -BeLike "*refused by the test trigger*"
        }

        It "keeps the transaction of the caller and the work done in it" {
            $stateAfterFailure.tran_count | Should -Be 1
            $stateAfterFailure.caller_work | Should -Be 1
        }

        It "takes back its own statements, so the login is as it was" {
            $stateAfterFailure.password_hash | Should -Be $stateBefore.password_hash
            $stateAfterFailure.is_policy_checked | Should -BeTrue
            $stateAfterFailure.is_disabled | Should -BeFalse
        }
    }

    Context "The permissions of a renamed login are synced to the login it is renamed to (#10772)" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $renameRandom = Get-Random
            $renameSourceName = "dbatoolsci_renamesrc_$renameRandom"
            $renameDestName = "dbatoolsci_renamedest_$renameRandom"

            # The source login is in no server role.
            $splatSourceLogin = @{
                SqlInstance    = $TestConfig.InstanceCopy1
                Login          = $renameSourceName
                SecurePassword = (ConvertTo-SecureString -String "dbatools.IO.Source4" -AsPlainText -Force)
            }
            $sourceLogin = New-DbaLogin @splatSourceLogin

            # On the destination, the login it is renamed to has its SID and is a sysadmin, so the update in place has to
            # take it out of the role. Another login there has the name of the source login, is a sysadmin as well and
            # has nothing to do with the copy.
            $splatRenamedLogin = @{
                SqlInstance    = $TestConfig.InstanceCopy2
                Login          = $renameDestName
                SecurePassword = (ConvertTo-SecureString -String "dbatools.IO.Dest4" -AsPlainText -Force)
                Sid            = $sourceLogin.Sid
            }
            $null = New-DbaLogin @splatRenamedLogin
            $splatNamesakeLogin = @{
                SqlInstance    = $TestConfig.InstanceCopy2
                Login          = $renameSourceName
                SecurePassword = (ConvertTo-SecureString -String "dbatools.IO.Dest4" -AsPlainText -Force)
            }
            $null = New-DbaLogin @splatNamesakeLogin
            $splatSysadmin = @{
                SqlInstance = $TestConfig.InstanceCopy2
                ServerRole  = "sysadmin"
                Login       = $renameDestName, $renameSourceName
                Confirm     = $false
            }
            $null = Add-DbaServerRoleMember @splatSysadmin

            $splatSysadminState = @{
                SqlInstance  = $TestConfig.InstanceCopy2
                Query        = "SELECT m.name FROM sys.server_role_members AS rm INNER JOIN sys.server_principals AS r ON r.principal_id = rm.role_principal_id INNER JOIN sys.server_principals AS m ON m.principal_id = rm.member_principal_id WHERE r.name = N'sysadmin' AND m.name IN (@sourceName, @destName)"
                SqlParameter = @{
                    sourceName = $renameSourceName
                    destName   = $renameDestName
                }
            }
            $splatRenameUpdate = @{
                Source               = $TestConfig.InstanceCopy1
                Destination          = $TestConfig.InstanceCopy2
                Login                = $renameSourceName
                LoginRenameHashtable = @{ $renameSourceName = $renameDestName }
                UpdateExisting       = $true
            }

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $renameResult = Copy-DbaLogin @splatRenameUpdate
            $renameWarn = $WarnVar
            $sysadminsAfter = @((Invoke-DbaQuery @splatSysadminState -EnableException).name)
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # The login it is renamed to exists on the destination only.
            $splatRemoveSourceLogin = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Login       = $renameSourceName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaLogin @splatRemoveSourceLogin
            $splatRemoveDestLogin = @{
                SqlInstance = $TestConfig.InstanceCopy2
                Login       = $renameSourceName, $renameDestName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaLogin @splatRemoveDestLogin

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "updates the login it is renamed to in place" {
            $renameWarn | Should -BeNullOrEmpty
            $renameResult.Status | Should -Be "Successful"
            $renameResult.Name | Should -Be $renameDestName
        }

        It "takes the login it is renamed to out of the server role the source login is not in" {
            $sysadminsAfter | Should -Not -Contain $renameDestName
        }

        It "leaves the other login with the name of the source login in its server role" {
            $sysadminsAfter | Should -Contain $renameSourceName
        }
    }
}
