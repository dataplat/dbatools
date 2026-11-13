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

    Context "A server role that exists on the destination only loses the login updated in place (#10772)" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $destRoleRandom = Get-Random
            $destRoleLoginName = "dbatoolsci_destrolelogin_$destRoleRandom"
            $destRoleOtherName = "dbatoolsci_destroleother_$destRoleRandom"
            $destRoleName = "dbatoolsci_destrole_$destRoleRandom"

            # The source login is in no server role, and the source has no role of that name.
            $splatSourceLogin = @{
                SqlInstance    = $TestConfig.InstanceCopy1
                Login          = $destRoleLoginName
                SecurePassword = (ConvertTo-SecureString -String "dbatools.IO.Source5" -AsPlainText -Force)
            }
            $sourceLogin = New-DbaLogin @splatSourceLogin

            # On the destination, the login has the same SID and is a member of a user-defined server role that has
            # CONTROL SERVER. Another login is a member as well and has nothing to do with the copy.
            $splatDestLogin = @{
                SqlInstance    = $TestConfig.InstanceCopy2
                Login          = $destRoleLoginName
                SecurePassword = (ConvertTo-SecureString -String "dbatools.IO.Dest5" -AsPlainText -Force)
                Sid            = $sourceLogin.Sid
            }
            $null = New-DbaLogin @splatDestLogin
            $splatOtherLogin = @{
                SqlInstance    = $TestConfig.InstanceCopy2
                Login          = $destRoleOtherName
                SecurePassword = (ConvertTo-SecureString -String "dbatools.IO.Dest5" -AsPlainText -Force)
            }
            $null = New-DbaLogin @splatOtherLogin
            $null = New-DbaServerRole -SqlInstance $TestConfig.InstanceCopy2 -ServerRole $destRoleName
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Query "GRANT CONTROL SERVER TO [$destRoleName]"
            $splatDestRoleMember = @{
                SqlInstance = $TestConfig.InstanceCopy2
                ServerRole  = $destRoleName
                Login       = $destRoleLoginName, $destRoleOtherName
                Confirm     = $false
            }
            $null = Add-DbaServerRoleMember @splatDestRoleMember

            $splatDestRoleState = @{
                SqlInstance  = $TestConfig.InstanceCopy2
                Query        = "SELECT m.name FROM sys.server_role_members AS rm INNER JOIN sys.server_principals AS r ON r.principal_id = rm.role_principal_id INNER JOIN sys.server_principals AS m ON m.principal_id = rm.member_principal_id WHERE r.name = @roleName"
                SqlParameter = @{
                    roleName = $destRoleName
                }
            }
            $splatDestRoleUpdate = @{
                Source         = $TestConfig.InstanceCopy1
                Destination    = $TestConfig.InstanceCopy2
                Login          = $destRoleLoginName
                UpdateExisting = $true
            }

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $destRoleResult = Copy-DbaLogin @splatDestRoleUpdate
            $destRoleWarn = $WarnVar
            $destRoleMembersAfter = @((Invoke-DbaQuery @splatDestRoleState -EnableException).name)
            $splatDestRoleAfter = @{
                SqlInstance     = $TestConfig.InstanceCopy2
                ServerRole      = $destRoleName
                EnableException = $true
            }
            $destRoleAfter = Get-DbaServerRole @splatDestRoleAfter
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $splatRemoveSourceLogin = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Login       = $destRoleLoginName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaLogin @splatRemoveSourceLogin
            # The logins first: SQL Server drops no server role that still has members.
            $splatRemoveDestLogin = @{
                SqlInstance = $TestConfig.InstanceCopy2
                Login       = $destRoleLoginName, $destRoleOtherName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaLogin @splatRemoveDestLogin
            $splatRemoveDestRole = @{
                SqlInstance = $TestConfig.InstanceCopy2
                ServerRole  = $destRoleName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaServerRole @splatRemoveDestRole

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "updates the login in place" {
            $destRoleWarn | Should -BeNullOrEmpty
            $destRoleResult.Status | Should -Be "Successful"
            $destRoleResult.Name | Should -Be $destRoleLoginName
        }

        It "takes the login out of the server role the source does not have" {
            $destRoleMembersAfter | Should -Not -Contain $destRoleLoginName
        }

        It "leaves the server role and its other member on the destination" {
            $destRoleAfter | Should -Not -BeNullOrEmpty
            $destRoleMembersAfter | Should -Contain $destRoleOtherName
        }
    }

    Context "The server roles are synced from the server, also when the server objects of the caller loaded their roles before (#10772)" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $staleRandom = Get-Random
            $staleLoginName = "dbatoolsci_staleroles_$staleRandom"
            $staleSharedRoleName = "dbatoolsci_staleshared_$staleRandom"
            $staleDestOnlyRoleName = "dbatoolsci_staledestonly_$staleRandom"

            $splatSourceLogin = @{
                SqlInstance    = $TestConfig.InstanceCopy1
                Login          = $staleLoginName
                SecurePassword = (ConvertTo-SecureString -String "dbatools.IO.Source10" -AsPlainText -Force)
            }
            $staleSourceLogin = New-DbaLogin @splatSourceLogin
            $splatDestLogin = @{
                SqlInstance    = $TestConfig.InstanceCopy2
                Login          = $staleLoginName
                SecurePassword = (ConvertTo-SecureString -String "dbatools.IO.Dest10" -AsPlainText -Force)
                Sid            = $staleSourceLogin.Sid
            }
            $null = New-DbaLogin @splatDestLogin

            # On the destination, the login is a member of a role that the source gets only after the caller loaded its
            # roles.
            $null = New-DbaServerRole -SqlInstance $TestConfig.InstanceCopy2 -ServerRole $staleSharedRoleName
            $splatDestSharedMember = @{
                SqlInstance = $TestConfig.InstanceCopy2
                ServerRole  = $staleSharedRoleName
                Login       = $staleLoginName
                Confirm     = $false
            }
            $null = Add-DbaServerRoleMember @splatDestSharedMember

            # The caller loads the roles of both instances.
            $staleSourceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -NonPooledConnection
            $staleDestServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -NonPooledConnection
            $null = $staleSourceServer.Roles.Count
            $null = $staleDestServer.Roles.Count

            # Then, through other connections, the source gets the shared role with the login, and the destination gets
            # a role of its own with the login, which has CONTROL SERVER.
            $null = New-DbaServerRole -SqlInstance $TestConfig.InstanceCopy1 -ServerRole $staleSharedRoleName
            $splatSourceSharedMember = @{
                SqlInstance = $TestConfig.InstanceCopy1
                ServerRole  = $staleSharedRoleName
                Login       = $staleLoginName
                Confirm     = $false
            }
            $null = Add-DbaServerRoleMember @splatSourceSharedMember
            $null = New-DbaServerRole -SqlInstance $TestConfig.InstanceCopy2 -ServerRole $staleDestOnlyRoleName
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Query "GRANT CONTROL SERVER TO [$staleDestOnlyRoleName]"
            $splatDestOnlyMember = @{
                SqlInstance = $TestConfig.InstanceCopy2
                ServerRole  = $staleDestOnlyRoleName
                Login       = $staleLoginName
                Confirm     = $false
            }
            $null = Add-DbaServerRoleMember @splatDestOnlyMember

            $splatStaleRoleState = @{
                SqlInstance  = $TestConfig.InstanceCopy2
                Query        = "SELECT r.name FROM sys.server_role_members AS rm INNER JOIN sys.server_principals AS r ON r.principal_id = rm.role_principal_id WHERE rm.member_principal_id = SUSER_ID(@loginName)"
                SqlParameter = @{
                    loginName = $staleLoginName
                }
            }
            $splatStaleUpdate = @{
                Source         = $staleSourceServer
                Destination    = $staleDestServer
                Login          = $staleLoginName
                UpdateExisting = $true
            }

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $staleResult = Copy-DbaLogin @splatStaleUpdate
            $staleWarn = $WarnVar
            $staleRolesAfter = @((Invoke-DbaQuery @splatStaleRoleState -EnableException).name)
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            foreach ($staleServer in $staleSourceServer, $staleDestServer) {
                if ($staleServer) {
                    $null = $staleServer | Disconnect-DbaInstance
                }
            }
            # The logins first: SQL Server drops no server role that still has members.
            $splatRemoveLogin = @{
                SqlInstance = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
                Login       = $staleLoginName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaLogin @splatRemoveLogin
            $splatRemoveRole = @{
                SqlInstance = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
                ServerRole  = $staleSharedRoleName, $staleDestOnlyRoleName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaServerRole @splatRemoveRole

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "updates the login in place" {
            $staleWarn | Should -BeNullOrEmpty
            $staleResult.Status | Should -Be "Successful"
            $staleResult.Name | Should -Be $staleLoginName
        }

        It "keeps the login in the role that the source login is in, which the roles of the source server object do not know" {
            $staleRolesAfter | Should -Contain $staleSharedRoleName
        }

        It "takes the login out of the role of the destination, which the roles of the destination server object do not know" {
            $staleRolesAfter | Should -Not -Contain $staleDestOnlyRoleName
        }
    }

    Context "Permissions that several logins granted, and the grants passed on with a grant option, are revoked from the login updated in place (#10772)" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $grantorRandom = Get-Random
            $grantorLoginName = "dbatoolsci_grantorlogin_$grantorRandom"
            $grantorOtherName = "dbatoolsci_grantorother_$grantorRandom"
            $grantorPassedName = "dbatoolsci_grantorpassed_$grantorRandom"
            $grantorTargetName = "dbatoolsci_grantortarget_$grantorRandom"
            $grantorPassword = ConvertTo-SecureString -String "dbatools.IO.Grantor12" -AsPlainText -Force

            # On the source, the login has VIEW ANY DEFINITION without the grant option.
            $splatSourceLogin = @{
                SqlInstance    = $TestConfig.InstanceCopy1
                Login          = $grantorLoginName
                SecurePassword = (ConvertTo-SecureString -String "dbatools.IO.Source12" -AsPlainText -Force)
            }
            $grantorSourceLogin = New-DbaLogin @splatSourceLogin
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Query "GRANT VIEW ANY DEFINITION TO [$grantorLoginName]"

            # On the destination, the login has the same SID. It has VIEW SERVER STATE and IMPERSONATE on a login from the
            # sysadmin and from another login that holds them with grant option, and VIEW ANY DEFINITION with grant option,
            # which it passed on to a third login. That third login has VIEW ANY DEFINITION from the sysadmin as well.
            $splatDestLogin = @{
                SqlInstance    = $TestConfig.InstanceCopy2
                Login          = $grantorLoginName
                SecurePassword = (ConvertTo-SecureString -String "dbatools.IO.Dest12" -AsPlainText -Force)
                Sid            = $grantorSourceLogin.Sid
            }
            $null = New-DbaLogin @splatDestLogin
            $splatDestOthers = @{
                SqlInstance    = $TestConfig.InstanceCopy2
                Login          = $grantorOtherName, $grantorPassedName, $grantorTargetName
                SecurePassword = $grantorPassword
            }
            $null = New-DbaLogin @splatDestOthers
            $grantorSetup = @(
                "GRANT VIEW SERVER STATE TO [$grantorOtherName] WITH GRANT OPTION",
                "GRANT IMPERSONATE ON LOGIN::[$grantorTargetName] TO [$grantorOtherName] WITH GRANT OPTION",
                "EXECUTE AS LOGIN = N'$grantorOtherName'",
                "GRANT VIEW SERVER STATE TO [$grantorLoginName]",
                "GRANT IMPERSONATE ON LOGIN::[$grantorTargetName] TO [$grantorLoginName]",
                "REVERT",
                "GRANT VIEW SERVER STATE TO [$grantorLoginName]",
                "GRANT IMPERSONATE ON LOGIN::[$grantorTargetName] TO [$grantorLoginName]",
                "GRANT VIEW ANY DEFINITION TO [$grantorLoginName] WITH GRANT OPTION",
                "EXECUTE AS LOGIN = N'$grantorLoginName'",
                "GRANT VIEW ANY DEFINITION TO [$grantorPassedName]",
                "REVERT",
                "GRANT VIEW ANY DEFINITION TO [$grantorPassedName]"
            )
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Query ($grantorSetup -join "; ")

            # The columns are put together in PowerShell: the names and the descriptions have different collations.
            $splatGrantorPermState = @{
                SqlInstance  = $TestConfig.InstanceCopy2
                Query        = "SELECT SUSER_NAME(p.grantee_principal_id) AS grantee, p.permission_name, p.state_desc, SUSER_NAME(p.grantor_principal_id) AS grantor FROM sys.server_permissions AS p WHERE p.grantee_principal_id IN (SUSER_ID(@login), SUSER_ID(@other), SUSER_ID(@passed)) AND p.permission_name IN (N'VIEW SERVER STATE', N'IMPERSONATE', N'VIEW ANY DEFINITION')"
                SqlParameter = @{
                    login  = $grantorLoginName
                    other  = $grantorOtherName
                    passed = $grantorPassedName
                }
            }
            $grantorPermsBefore = @(Invoke-DbaQuery @splatGrantorPermState | ForEach-Object { "$($PSItem.grantee) $($PSItem.permission_name) $($PSItem.state_desc) $($PSItem.grantor)" })
            # SQL Server records sa, principal 1, as the grantor of a server permission that a sysadmin grants.
            $grantorSaName = (Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Query "SELECT SUSER_NAME(1) AS name").name
            $splatGrantorUpdate = @{
                Source         = $TestConfig.InstanceCopy1
                Destination    = $TestConfig.InstanceCopy2
                Login          = $grantorLoginName
                UpdateExisting = $true
            }

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $grantorResult = Copy-DbaLogin @splatGrantorUpdate
            $grantorWarn = $WarnVar
            $grantorPermsAfter = @(Invoke-DbaQuery @splatGrantorPermState -EnableException | ForEach-Object { "$($PSItem.grantee) $($PSItem.permission_name) $($PSItem.state_desc) $($PSItem.grantor)" })
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # SQL Server drops no login that granted a permission, and the grantor of IMPERSONATE on a login is that login,
            # or the login that holds it with grant option. So the grantees go first, in the order of the chain.
            $splatRemoveSourceLogin = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Login       = $grantorLoginName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaLogin @splatRemoveSourceLogin
            foreach ($grantorCleanupName in $grantorPassedName, $grantorLoginName, $grantorOtherName, $grantorTargetName) {
                $splatRemoveDestLogin = @{
                    SqlInstance = $TestConfig.InstanceCopy2
                    Login       = $grantorCleanupName
                    ErrorAction = "SilentlyContinue"
                }
                $null = Remove-DbaLogin @splatRemoveDestLogin
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "has the permissions from two grantors and the passed on grant before the update" {
            $grantorPermsBefore | Should -Contain "$grantorLoginName VIEW SERVER STATE GRANT $grantorSaName"
            $grantorPermsBefore | Should -Contain "$grantorLoginName VIEW SERVER STATE GRANT $grantorOtherName"
            $grantorPermsBefore | Should -Contain "$grantorLoginName IMPERSONATE GRANT $grantorTargetName"
            $grantorPermsBefore | Should -Contain "$grantorLoginName IMPERSONATE GRANT $grantorOtherName"
            $grantorPermsBefore | Should -Contain "$grantorPassedName VIEW ANY DEFINITION GRANT $grantorLoginName"
        }

        It "updates the login in place" {
            $grantorWarn | Should -BeNullOrEmpty
            $grantorResult.Status | Should -Be "Successful"
            $grantorResult.Name | Should -Be $grantorLoginName
        }

        It "revokes the server permission that the source login does not have from both grantors" {
            $grantorPermsAfter | Should -Not -Contain "$grantorLoginName VIEW SERVER STATE GRANT $grantorSaName"
            $grantorPermsAfter | Should -Not -Contain "$grantorLoginName VIEW SERVER STATE GRANT $grantorOtherName"
        }

        It "revokes the permission on a login that the source login does not have from both grantors" {
            $grantorPermsAfter | Should -Not -Contain "$grantorLoginName IMPERSONATE GRANT $grantorTargetName"
            $grantorPermsAfter | Should -Not -Contain "$grantorLoginName IMPERSONATE GRANT $grantorOtherName"
        }

        It "takes the grant option away and with it the grant the login passed on, but keeps the permission itself" {
            $grantorPermsAfter | Should -Contain "$grantorLoginName VIEW ANY DEFINITION GRANT $grantorSaName"
            $grantorPermsAfter | Should -Not -Contain "$grantorPassedName VIEW ANY DEFINITION GRANT $grantorLoginName"
        }

        It "leaves the grant that the third login has from the sysadmin" {
            $grantorPermsAfter | Should -Contain "$grantorPassedName VIEW ANY DEFINITION GRANT $grantorSaName"
        }

        It "leaves the permissions of the other grantor" {
            $grantorPermsAfter | Should -Contain "$grantorOtherName VIEW SERVER STATE GRANT_WITH_GRANT_OPTION $grantorSaName"
            $grantorPermsAfter | Should -Contain "$grantorOtherName IMPERSONATE GRANT_WITH_GRANT_OPTION $grantorTargetName"
        }
    }

    Context "The result of a login updated in place comes after its permissions are synced (#10772)" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $resultRandom = Get-Random
            $resultChangedName = "dbatoolsci_resultchanged_$resultRandom"
            $resultIdenticalName = "dbatoolsci_resultidentical_$resultRandom"
            $resultFailedName = "dbatoolsci_resultfailed_$resultRandom"
            $resultTriggerName = "dbatoolsci_result_trigger_$resultRandom"
            $dropResultTriggerQuery = "IF EXISTS (SELECT * FROM sys.server_triggers WHERE name = N'$resultTriggerName') DROP TRIGGER [$resultTriggerName] ON ALL SERVER"

            # The logins are copied first, so they are identical on the destination, with the same SID. Then the first
            # gets another password on the source, and all three get CONTROL SERVER on the destination.
            $splatSourceLogins = @{
                SqlInstance    = $TestConfig.InstanceCopy1
                Login          = $resultChangedName, $resultIdenticalName, $resultFailedName
                SecurePassword = (ConvertTo-SecureString -String "dbatools.IO.Source13" -AsPlainText -Force)
            }
            $null = New-DbaLogin @splatSourceLogins
            $splatFirstCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Login       = $resultChangedName, $resultIdenticalName, $resultFailedName
            }
            $null = Copy-DbaLogin @splatFirstCopy
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Query "ALTER LOGIN [$resultChangedName] WITH PASSWORD = N'dbatools.IO.Changed13'"
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Query "GRANT CONTROL SERVER TO [$resultChangedName]; GRANT CONTROL SERVER TO [$resultIdenticalName]; GRANT CONTROL SERVER TO [$resultFailedName]"

            # Refuses the revoke of CONTROL SERVER from the third login only.
            $createResultTriggerQuery = @"
CREATE TRIGGER [$resultTriggerName] ON ALL SERVER FOR REVOKE_SERVER AS
IF EVENTDATA().value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'nvarchar(max)') LIKE N'%CONTROL SERVER%$resultFailedName%'
BEGIN
    THROW 50000, N'dbatoolsci: refused by the test trigger', 1;
END
"@
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Query $createResultTriggerQuery

            $splatControlState = @{
                SqlInstance = $TestConfig.InstanceCopy2
                Query       = "SELECT SUSER_NAME(p.grantee_principal_id) AS grantee FROM sys.server_permissions AS p WHERE p.class = 100 AND p.permission_name = N'CONTROL SERVER' AND p.grantee_principal_id IN (SUSER_ID(@changed), SUSER_ID(@identical), SUSER_ID(@failed))"
                SqlParameter = @{
                    changed   = $resultChangedName
                    identical = $resultIdenticalName
                    failed    = $resultFailedName
                }
            }
            $controlBefore = @((Invoke-DbaQuery @splatControlState).grantee)
            $splatResultUpdate = @{
                Source         = $TestConfig.InstanceCopy1
                Destination    = $TestConfig.InstanceCopy2
                UpdateExisting = $true
            }

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            # The pipeline stops at the first object, so the command runs only as far as its first result.
            $changedResult = Copy-DbaLogin @splatResultUpdate -Login $resultChangedName | Select-Object -First 1
            $identicalResult = Copy-DbaLogin @splatResultUpdate -Login $resultIdenticalName | Select-Object -First 1
            $failedResult = Copy-DbaLogin @splatResultUpdate -Login $resultFailedName -WarningAction SilentlyContinue
            $failedWarn = $WarnVar
            $controlAfter = @((Invoke-DbaQuery @splatControlState -EnableException).grantee)
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Query $dropResultTriggerQuery
            $splatRemoveLogin = @{
                SqlInstance = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
                Login       = $resultChangedName, $resultIdenticalName, $resultFailedName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaLogin @splatRemoveLogin

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "has CONTROL SERVER for all three logins on the destination before the update" {
            $controlBefore | Should -Contain $resultChangedName
            $controlBefore | Should -Contain $resultIdenticalName
            $controlBefore | Should -Contain $resultFailedName
        }

        It "revokes CONTROL SERVER from an updated login before its result, so a pipeline that stops at the result does not stop the sync" {
            $changedResult.Status | Should -Be "Successful"
            $changedResult.Notes | Should -Be "Updated in place: password"
            $controlAfter | Should -Not -Contain $resultChangedName
        }

        It "revokes CONTROL SERVER from an identical login before its result, so a pipeline that stops at the result does not stop the sync" {
            $identicalResult.Status | Should -Be "Skipped"
            $identicalResult.Notes | Should -Be "Login is identical on source and destination"
            $controlAfter | Should -Not -Contain $resultIdenticalName
        }

        It "fails the login whose permission could not be revoked and says so" {
            $failedResult.Status | Should -Be "Failed"
            $failedResult.Notes | Should -BeLike "Login is identical on source and destination. Syncing the permissions failed: *CONTROL SERVER*"
            ($failedWarn -join " ") | Should -Match "Failed to revoke CONTROL SERVER from $resultFailedName"
            $controlAfter | Should -Contain $resultFailedName
        }
    }

    Context "A login of another type on the destination is not updated in place (#10772)" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $typeRandom = Get-Random
            $typeLoginName = "dbatoolsci_typelogin_$typeRandom"
            $typeCertName = "dbatoolsci_typecert_$typeRandom"

            # On the source, a certificate login with CONTROL SERVER.
            $splatSourceCertLogin = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Database    = "master"
                Query       = "CREATE CERTIFICATE [$typeCertName] ENCRYPTION BY PASSWORD = N'dbatools.IO.Cert14' WITH SUBJECT = N'dbatoolsci login type'; CREATE LOGIN [$typeLoginName] FROM CERTIFICATE [$typeCertName]; GRANT CONTROL SERVER TO [$typeLoginName]"
            }
            $null = Invoke-DbaQuery @splatSourceCertLogin

            # On the destination, a SQL login of the same name, which has a password, a SID of its own and no CONTROL SERVER.
            $splatDestLogin = @{
                SqlInstance    = $TestConfig.InstanceCopy2
                Login          = $typeLoginName
                SecurePassword = (ConvertTo-SecureString -String "dbatools.IO.Dest14" -AsPlainText -Force)
            }
            $null = New-DbaLogin @splatDestLogin

            $splatTypeState = @{
                SqlInstance  = $TestConfig.InstanceCopy2
                Query        = "SELECT sp.principal_id, sp.type_desc, CONVERT(VARCHAR(514), sp.sid, 1) AS sid, (SELECT COUNT(*) FROM sys.server_permissions AS p WHERE p.grantee_principal_id = sp.principal_id AND p.class = 100 AND p.permission_name = N'CONTROL SERVER') AS control_server FROM sys.server_principals AS sp WHERE sp.name = @loginName"
                SqlParameter = @{
                    loginName = $typeLoginName
                }
            }
            $splatSourceType = @{
                SqlInstance  = $TestConfig.InstanceCopy1
                Query        = $splatTypeState.Query
                SqlParameter = $splatTypeState.SqlParameter
            }
            $typeSourceState = Invoke-DbaQuery @splatSourceType
            $typeStateBefore = Invoke-DbaQuery @splatTypeState
            $splatNewSidUpdate = @{
                Source         = $TestConfig.InstanceCopy1
                Destination    = $TestConfig.InstanceCopy2
                Login          = $typeLoginName
                UpdateExisting = $true
                NewSid         = $true
                WarningAction  = "SilentlyContinue"
            }
            $splatNewSidForceUpdate = @{
                Source         = $TestConfig.InstanceCopy1
                Destination    = $TestConfig.InstanceCopy2
                Login          = $typeLoginName
                UpdateExisting = $true
                NewSid         = $true
                Force          = $true
                WarningAction  = "SilentlyContinue"
            }

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $typeNewSidResult = Copy-DbaLogin @splatNewSidUpdate
            $typeNewSidWarn = $WarnVar
            $typeStateAfterNewSid = Invoke-DbaQuery @splatTypeState -EnableException
            $typeForceResult = Copy-DbaLogin @splatNewSidForceUpdate
            $typeForceWarn = $WarnVar
            $typeStateAfterForce = Invoke-DbaQuery @splatTypeState -EnableException
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $splatRemoveLogin = @{
                SqlInstance = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
                Login       = $typeLoginName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaLogin @splatRemoveLogin
            # The certificate after its login, which depends on it.
            $splatDropCert = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Database    = "master"
                Query       = "IF EXISTS (SELECT * FROM sys.certificates WHERE name = N'$typeCertName') DROP CERTIFICATE [$typeCertName]"
            }
            $null = Invoke-DbaQuery @splatDropCert

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "has a certificate login with CONTROL SERVER on the source and a SQL login without it on the destination" {
            $typeSourceState.type_desc | Should -Be "CERTIFICATE_MAPPED_LOGIN"
            $typeSourceState.control_server | Should -Be 1
            $typeStateBefore.type_desc | Should -Be "SQL_LOGIN"
            $typeStateBefore.control_server | Should -Be 0
        }

        It "skips the login with -UpdateExisting -NewSid and leaves the SQL login without the permissions of the certificate login" {
            $typeNewSidResult.Status | Should -Be "Skipped"
            $typeNewSidResult.Notes | Should -Be "Different login type on destination"
            ($typeNewSidWarn -join " ") | Should -Match "Login $typeLoginName is a SqlLogin login on .* and a Certificate login on"
            $typeStateAfterNewSid.principal_id | Should -Be $typeStateBefore.principal_id
            $typeStateAfterNewSid.type_desc | Should -Be "SQL_LOGIN"
            $typeStateAfterNewSid.control_server | Should -Be 0
        }

        It "skips the login with -UpdateExisting -NewSid -Force as well and does not drop the SQL login" {
            $typeForceResult.Status | Should -Be "Skipped"
            $typeForceResult.Notes | Should -Be "Different login type on destination"
            ($typeForceWarn -join " ") | Should -Match "Login $typeLoginName is a SqlLogin login on"
            $typeStateAfterForce.principal_id | Should -Be $typeStateBefore.principal_id
            $typeStateAfterForce.sid | Should -Be $typeStateBefore.sid
            $typeStateAfterForce.type_desc | Should -Be "SQL_LOGIN"
            $typeStateAfterForce.control_server | Should -Be 0
        }
    }

    Context "A direct server permission is revoked from the login updated in place when the source login has none (#10772)" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $directPermRandom = Get-Random
            $directPermLoginName = "dbatoolsci_directperm_$directPermRandom"
            $directPermRoleName = "dbatoolsci_connectrole_$directPermRandom"
            $directPermPassword = "dbatools.IO.Source6"

            # On the source, the login connects through a user-defined server role and has no direct server permission:
            # the role has CONNECT SQL, and the CONNECT SQL that CREATE LOGIN granted to the login is revoked.
            $splatSourceLogin = @{
                SqlInstance    = $TestConfig.InstanceCopy1
                Login          = $directPermLoginName
                SecurePassword = (ConvertTo-SecureString -String $directPermPassword -AsPlainText -Force)
            }
            $sourceLogin = New-DbaLogin @splatSourceLogin
            $null = New-DbaServerRole -SqlInstance $TestConfig.InstanceCopy1 -ServerRole $directPermRoleName
            $splatSourceRoleMember = @{
                SqlInstance = $TestConfig.InstanceCopy1
                ServerRole  = $directPermRoleName
                Login       = $directPermLoginName
                Confirm     = $false
            }
            $null = Add-DbaServerRoleMember @splatSourceRoleMember
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Query "GRANT CONNECT SQL TO [$directPermRoleName]; REVOKE CONNECT SQL FROM [$directPermLoginName]"

            # On the destination, the login has the same SID and CONNECT SQL and CONTROL SERVER granted directly. The
            # role exists there as well, with CONNECT SQL, but without the login.
            $splatDestLogin = @{
                SqlInstance    = $TestConfig.InstanceCopy2
                Login          = $directPermLoginName
                SecurePassword = (ConvertTo-SecureString -String "dbatools.IO.Dest6" -AsPlainText -Force)
                Sid            = $sourceLogin.Sid
            }
            $null = New-DbaLogin @splatDestLogin
            $null = New-DbaServerRole -SqlInstance $TestConfig.InstanceCopy2 -ServerRole $directPermRoleName
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Query "GRANT CONNECT SQL TO [$directPermRoleName]; GRANT CONTROL SERVER TO [$directPermLoginName]"

            $splatSourcePermState = @{
                SqlInstance  = $TestConfig.InstanceCopy1
                Query        = "SELECT p.permission_name FROM sys.server_permissions AS p INNER JOIN sys.server_principals AS sp ON sp.principal_id = p.grantee_principal_id WHERE sp.name = @loginName AND p.class = 100"
                SqlParameter = @{
                    loginName = $directPermLoginName
                }
            }
            $sourcePerms = @((Invoke-DbaQuery @splatSourcePermState).permission_name)
            $splatDestPermState = @{
                SqlInstance  = $TestConfig.InstanceCopy2
                Query        = $splatSourcePermState.Query
                SqlParameter = $splatSourcePermState.SqlParameter
            }
            $splatDestRoleState = @{
                SqlInstance  = $TestConfig.InstanceCopy2
                Query        = "SELECT m.name FROM sys.server_role_members AS rm INNER JOIN sys.server_principals AS r ON r.principal_id = rm.role_principal_id INNER JOIN sys.server_principals AS m ON m.principal_id = rm.member_principal_id WHERE r.name = @roleName"
                SqlParameter = @{
                    roleName = $directPermRoleName
                }
            }
            $splatDirectPermUpdate = @{
                Source         = $TestConfig.InstanceCopy1
                Destination    = $TestConfig.InstanceCopy2
                Login          = $directPermLoginName
                UpdateExisting = $true
            }

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $directPermResult = Copy-DbaLogin @splatDirectPermUpdate
            $directPermWarn = $WarnVar
            $destPermsAfter = @((Invoke-DbaQuery @splatDestPermState -EnableException).permission_name)
            $directPermMembersAfter = @((Invoke-DbaQuery @splatDestRoleState -EnableException).name)
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # The logins first: SQL Server drops no server role that still has members.
            $splatRemoveLogin = @{
                SqlInstance = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
                Login       = $directPermLoginName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaLogin @splatRemoveLogin
            $splatRemoveRole = @{
                SqlInstance = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
                ServerRole  = $directPermRoleName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaServerRole @splatRemoveRole

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "updates the login in place" {
            $directPermWarn | Should -BeNullOrEmpty
            $directPermResult.Status | Should -Be "Successful"
            $directPermResult.Name | Should -Be $directPermLoginName
        }

        It "revokes the direct server permissions the source login does not have" {
            $sourcePerms | Should -BeNullOrEmpty
            $destPermsAfter | Should -Not -Contain "CONTROL SERVER"
            $destPermsAfter | Should -Not -Contain "CONNECT SQL"
        }

        It "adds the login to the server role it connects through" {
            $directPermMembersAfter | Should -Contain $directPermLoginName
        }

        It "lets the login connect to the destination through the server role" {
            $splatConnect = @{
                SqlInstance         = $TestConfig.InstanceCopy2
                SqlCredential       = New-Object System.Management.Automation.PSCredential ($directPermLoginName, (ConvertTo-SecureString -String $directPermPassword -AsPlainText -Force))
                NonPooledConnection = $true
            }
            $loginServer = Connect-DbaInstance @splatConnect
            try {
                $loginServer.ConnectionContext.ExecuteScalar("SELECT SUSER_SNAME()") | Should -Be $directPermLoginName
            } finally {
                # An open session would keep AfterAll from removing the login.
                $null = $loginServer | Disconnect-DbaInstance
            }
        }
    }

    Context "An existing login is not dropped when the password hash of the source login cannot be read (#10772)" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $hashRandom = Get-Random
            $hashLoginName = "dbatoolsci_hashcopy_$hashRandom"
            $hashReaderName = "dbatoolsci_hashreader_$hashRandom"
            $hashReaderPassword = ConvertTo-SecureString -String "dbatools.IO.Reader7" -AsPlainText -Force

            # The source connection belongs to a login that can see every login but has no CONTROL SERVER, which
            # LOGINPROPERTY requires for the password hash.
            $splatReaderLogin = @{
                SqlInstance    = $TestConfig.InstanceCopy1
                Login          = $hashReaderName
                SecurePassword = $hashReaderPassword
            }
            $null = New-DbaLogin @splatReaderLogin
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Query "GRANT VIEW ANY DEFINITION TO [$hashReaderName]"
            $splatSourceLogin = @{
                SqlInstance    = $TestConfig.InstanceCopy1
                Login          = $hashLoginName
                SecurePassword = (ConvertTo-SecureString -String "dbatools.IO.Source7" -AsPlainText -Force)
            }
            $hashSourceLogin = New-DbaLogin @splatSourceLogin
            $hashSourceSid = [System.BitConverter]::ToString($hashSourceLogin.Sid)

            # The destination login has a SID of its own, so -UpdateExisting -Force drops and recreates it as well.
            $splatDestLogin = @{
                SqlInstance    = $TestConfig.InstanceCopy2
                Login          = $hashLoginName
                SecurePassword = (ConvertTo-SecureString -String "dbatools.IO.Dest7" -AsPlainText -Force)
            }
            $hashDestLogin = New-DbaLogin @splatDestLogin
            $hashDestSidBefore = [System.BitConverter]::ToString($hashDestLogin.Sid)

            $splatReaderConnection = @{
                SqlInstance         = $TestConfig.InstanceCopy1
                SqlCredential       = New-Object System.Management.Automation.PSCredential ($hashReaderName, $hashReaderPassword)
                NonPooledConnection = $true
            }
            $hashReaderServer = Connect-DbaInstance @splatReaderConnection
            $readerHash = $hashReaderServer.ConnectionContext.ExecuteScalar("SELECT LOGINPROPERTY(N'$hashLoginName', 'PasswordHash')")

            $splatForceCopy = @{
                Source        = $hashReaderServer
                Destination   = $TestConfig.InstanceCopy2
                Login         = $hashLoginName
                Force         = $true
                WarningAction = "SilentlyContinue"
            }
            $splatUpdateForceCopy = @{
                Source         = $hashReaderServer
                Destination    = $TestConfig.InstanceCopy2
                Login          = $hashLoginName
                UpdateExisting = $true
                Force          = $true
                WarningAction  = "SilentlyContinue"
            }
            $splatDestLoginState = @{
                SqlInstance = $TestConfig.InstanceCopy2
                Login       = $hashLoginName
            }

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $forceResult = Copy-DbaLogin @splatForceCopy
            $forceWarn = $WarnVar
            $destLoginAfterForce = Get-DbaLogin @splatDestLoginState -EnableException
            $updateForceResult = Copy-DbaLogin @splatUpdateForceCopy
            $updateForceWarn = $WarnVar
            $destLoginAfterUpdateForce = Get-DbaLogin @splatDestLoginState -EnableException
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # An open session would keep the reader login from being removed.
            if ($hashReaderServer) {
                $null = $hashReaderServer | Disconnect-DbaInstance
            }
            $splatRemoveSourceLogin = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Login       = $hashLoginName, $hashReaderName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaLogin @splatRemoveSourceLogin
            $splatRemoveDestLogin = @{
                SqlInstance = $TestConfig.InstanceCopy2
                Login       = $hashLoginName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaLogin @splatRemoveDestLogin

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "reads no password hash through the source connection" {
            $readerHash | Should -BeOfType System.DBNull
        }

        It "fails the login with -Force and leaves the destination login as it was" {
            $forceResult.Status | Should -Be "Failed"
            $forceResult.Notes | Should -Be "Could not read the password hash"
            ($forceWarn -join " ") | Should -Match "Could not read the password hash"
            $destLoginAfterForce | Should -Not -BeNullOrEmpty
            [System.BitConverter]::ToString($destLoginAfterForce.Sid) | Should -Be $hashDestSidBefore
        }

        It "fails the login with -UpdateExisting -Force and a different SID and leaves the destination login as it was" {
            $hashDestSidBefore | Should -Not -Be $hashSourceSid
            $updateForceResult.Status | Should -Be "Failed"
            $updateForceResult.Notes | Should -Be "Could not read the password hash"
            ($updateForceWarn -join " ") | Should -Match "Could not read the password hash"
            $destLoginAfterUpdateForce | Should -Not -BeNullOrEmpty
            [System.BitConverter]::ToString($destLoginAfterUpdateForce.Sid) | Should -Be $hashDestSidBefore
        }
    }

    Context "A server permission the login updated in place has with grant option is synced to the state of the source (#10772)" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $grantOptionRandom = Get-Random
            $grantOptionLoginName = "dbatoolsci_grantoption_$grantOptionRandom"
            $grantOptionPassword = "dbatools.IO.Source8"

            # On the source, the login has CONNECT SQL from CREATE LOGIN and VIEW SERVER STATE, both without the grant
            # option, and ALTER TRACE is denied to it.
            $splatSourceLogin = @{
                SqlInstance    = $TestConfig.InstanceCopy1
                Login          = $grantOptionLoginName
                SecurePassword = (ConvertTo-SecureString -String $grantOptionPassword -AsPlainText -Force)
            }
            $grantOptionSourceLogin = New-DbaLogin @splatSourceLogin
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Query "GRANT VIEW SERVER STATE TO [$grantOptionLoginName]; DENY ALTER TRACE TO [$grantOptionLoginName]"

            # On the destination, the login has the same SID and all three permissions with the grant option.
            $splatDestLogin = @{
                SqlInstance    = $TestConfig.InstanceCopy2
                Login          = $grantOptionLoginName
                SecurePassword = (ConvertTo-SecureString -String "dbatools.IO.Dest8" -AsPlainText -Force)
                Sid            = $grantOptionSourceLogin.Sid
            }
            $null = New-DbaLogin @splatDestLogin
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Query "GRANT CONNECT SQL TO [$grantOptionLoginName] WITH GRANT OPTION; GRANT VIEW SERVER STATE TO [$grantOptionLoginName] WITH GRANT OPTION; GRANT ALTER TRACE TO [$grantOptionLoginName] WITH GRANT OPTION"

            $splatDestPermState = @{
                SqlInstance  = $TestConfig.InstanceCopy2
                Query        = "SELECT p.permission_name + ' ' + p.state_desc AS permission FROM sys.server_permissions AS p INNER JOIN sys.server_principals AS sp ON sp.principal_id = p.grantee_principal_id WHERE sp.name = @loginName AND p.class = 100"
                SqlParameter = @{
                    loginName = $grantOptionLoginName
                }
            }
            $splatGrantOptionUpdate = @{
                Source         = $TestConfig.InstanceCopy1
                Destination    = $TestConfig.InstanceCopy2
                Login          = $grantOptionLoginName
                UpdateExisting = $true
            }

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $grantOptionResult = Copy-DbaLogin @splatGrantOptionUpdate
            $grantOptionWarn = $WarnVar
            $grantOptionPermsAfter = @((Invoke-DbaQuery @splatDestPermState -EnableException).permission)
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $splatRemoveLogin = @{
                SqlInstance = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
                Login       = $grantOptionLoginName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaLogin @splatRemoveLogin

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "updates the login in place" {
            $grantOptionWarn | Should -BeNullOrEmpty
            $grantOptionResult.Status | Should -Be "Successful"
            $grantOptionResult.Name | Should -Be $grantOptionLoginName
        }

        It "takes only the grant option away when the source login has the permission without it" {
            $grantOptionPermsAfter | Should -Contain "CONNECT SQL GRANT"
            $grantOptionPermsAfter | Should -Contain "VIEW SERVER STATE GRANT"
            $grantOptionPermsAfter | Should -Not -Contain "CONNECT SQL GRANT_WITH_GRANT_OPTION"
            $grantOptionPermsAfter | Should -Not -Contain "VIEW SERVER STATE GRANT_WITH_GRANT_OPTION"
        }

        It "denies the permission that the source login is denied, although the login had it with grant option" {
            $grantOptionPermsAfter | Should -Contain "ALTER TRACE DENY"
            $grantOptionPermsAfter | Should -Not -Contain "ALTER TRACE GRANT_WITH_GRANT_OPTION"
        }

        It "lets the login connect to the destination" {
            $splatConnect = @{
                SqlInstance         = $TestConfig.InstanceCopy2
                SqlCredential       = New-Object System.Management.Automation.PSCredential ($grantOptionLoginName, (ConvertTo-SecureString -String $grantOptionPassword -AsPlainText -Force))
                NonPooledConnection = $true
            }
            $loginServer = Connect-DbaInstance @splatConnect
            try {
                $loginServer.ConnectionContext.ExecuteScalar("SELECT SUSER_SNAME()") | Should -Be $grantOptionLoginName
            } finally {
                # An open session would keep AfterAll from removing the login.
                $null = $loginServer | Disconnect-DbaInstance
            }
        }
    }

    Context "Permissions on logins and server roles that the source login does not have are revoked from the login updated in place (#10772)" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $securableRandom = Get-Random
            $securableLoginName = "dbatoolsci_securable_$securableRandom"
            $securableTargetName = "dbatoolsci_securabletarget_$securableRandom"
            $securableOtherName = "dbatoolsci_securableother_$securableRandom"
            $securableRoleName = "dbatoolsci_securablerole_$securableRandom"

            # On the source, the login has VIEW DEFINITION on the target login and CONTROL on the server role.
            $splatSourceLogin = @{
                SqlInstance    = $TestConfig.InstanceCopy1
                Login          = $securableLoginName
                SecurePassword = (ConvertTo-SecureString -String "dbatools.IO.Source9" -AsPlainText -Force)
            }
            $securableSourceLogin = New-DbaLogin @splatSourceLogin
            $splatSourceTarget = @{
                SqlInstance    = $TestConfig.InstanceCopy1
                Login          = $securableTargetName
                SecurePassword = (ConvertTo-SecureString -String "dbatools.IO.Target9" -AsPlainText -Force)
            }
            $null = New-DbaLogin @splatSourceTarget
            $null = New-DbaServerRole -SqlInstance $TestConfig.InstanceCopy1 -ServerRole $securableRoleName
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Query "GRANT VIEW DEFINITION ON LOGIN::[$securableTargetName] TO [$securableLoginName]; GRANT CONTROL ON SERVER ROLE::[$securableRoleName] TO [$securableLoginName]"

            # On the destination, the login has the same SID, IMPERSONATE on the target login in addition, CONTROL on the
            # server role with grant option, and CONNECT on an endpoint. Another login has IMPERSONATE on the target login.
            $splatDestLogin = @{
                SqlInstance    = $TestConfig.InstanceCopy2
                Login          = $securableLoginName
                SecurePassword = (ConvertTo-SecureString -String "dbatools.IO.Dest9" -AsPlainText -Force)
                Sid            = $securableSourceLogin.Sid
            }
            $null = New-DbaLogin @splatDestLogin
            $splatDestTarget = @{
                SqlInstance    = $TestConfig.InstanceCopy2
                Login          = $securableTargetName, $securableOtherName
                SecurePassword = (ConvertTo-SecureString -String "dbatools.IO.Target9" -AsPlainText -Force)
            }
            $null = New-DbaLogin @splatDestTarget
            $null = New-DbaServerRole -SqlInstance $TestConfig.InstanceCopy2 -ServerRole $securableRoleName
            $destGrants = @(
                "GRANT IMPERSONATE ON LOGIN::[$securableTargetName] TO [$securableLoginName]",
                "GRANT VIEW DEFINITION ON LOGIN::[$securableTargetName] TO [$securableLoginName]",
                "GRANT CONTROL ON SERVER ROLE::[$securableRoleName] TO [$securableLoginName] WITH GRANT OPTION",
                "GRANT CONNECT ON ENDPOINT::[TSQL Default TCP] TO [$securableLoginName]",
                "GRANT IMPERSONATE ON LOGIN::[$securableTargetName] TO [$securableOtherName]"
            )
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Query ($destGrants -join "; ")

            # The columns are put together in PowerShell: the names and the descriptions have different collations.
            $securablePermQuery = @"
SELECT p.class_desc, ISNULL(sp.name, e.name) AS securable, p.permission_name, p.state_desc
FROM sys.server_permissions AS p
INNER JOIN sys.server_principals AS g ON g.principal_id = p.grantee_principal_id
LEFT JOIN sys.server_principals AS sp ON p.class = 101 AND sp.principal_id = p.major_id
LEFT JOIN sys.endpoints AS e ON p.class = 105 AND e.endpoint_id = p.major_id
WHERE g.name = @loginName AND p.class IN (101, 105)
"@
            $splatDestPermState = @{
                SqlInstance  = $TestConfig.InstanceCopy2
                Query        = $securablePermQuery
                SqlParameter = @{
                    loginName = $securableLoginName
                }
            }
            $splatOtherPermState = @{
                SqlInstance  = $TestConfig.InstanceCopy2
                Query        = $securablePermQuery
                SqlParameter = @{
                    loginName = $securableOtherName
                }
            }
            $splatSecurableUpdate = @{
                Source         = $TestConfig.InstanceCopy1
                Destination    = $TestConfig.InstanceCopy2
                Login          = $securableLoginName
                UpdateExisting = $true
            }

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $securableResult = Copy-DbaLogin @splatSecurableUpdate
            $securableWarn = $WarnVar
            $securablePermsAfter = @(Invoke-DbaQuery @splatDestPermState -EnableException | ForEach-Object { "$($PSItem.class_desc) $($PSItem.securable) $($PSItem.permission_name) $($PSItem.state_desc)" })
            $otherPermsAfter = @(Invoke-DbaQuery @splatOtherPermState -EnableException | ForEach-Object { "$($PSItem.class_desc) $($PSItem.securable) $($PSItem.permission_name) $($PSItem.state_desc)" })
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # The grantees first: the grantor of IMPERSONATE on a login is that login, and SQL Server drops no login that
            # granted a permission, and no server role that still has permissions on it.
            $splatRemoveSourceGrantee = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Login       = $securableLoginName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaLogin @splatRemoveSourceGrantee
            $splatRemoveDestGrantee = @{
                SqlInstance = $TestConfig.InstanceCopy2
                Login       = $securableLoginName, $securableOtherName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaLogin @splatRemoveDestGrantee
            $splatRemoveTarget = @{
                SqlInstance = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
                Login       = $securableTargetName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaLogin @splatRemoveTarget
            $splatRemoveRole = @{
                SqlInstance = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
                ServerRole  = $securableRoleName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaServerRole @splatRemoveRole

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "updates the login in place" {
            $securableWarn | Should -BeNullOrEmpty
            $securableResult.Status | Should -Be "Successful"
            $securableResult.Name | Should -Be $securableLoginName
        }

        It "revokes the permission on a login that the source login does not have" {
            $securablePermsAfter | Should -Not -Contain "SERVER_PRINCIPAL $securableTargetName IMPERSONATE GRANT"
        }

        It "keeps the permission on a login that the source login has" {
            $securablePermsAfter | Should -Contain "SERVER_PRINCIPAL $securableTargetName VIEW DEFINITION GRANT"
        }

        It "takes only the grant option of the permission on a server role away" {
            $securablePermsAfter | Should -Contain "SERVER_PRINCIPAL $securableRoleName CONTROL GRANT"
            $securablePermsAfter | Should -Not -Contain "SERVER_PRINCIPAL $securableRoleName CONTROL GRANT_WITH_GRANT_OPTION"
        }

        It "keeps the permission on an endpoint, which belongs to the replica" {
            $securablePermsAfter | Should -Contain "ENDPOINT TSQL Default TCP CONNECT GRANT"
        }

        It "leaves the permissions of another login on the same login" {
            $otherPermsAfter | Should -Contain "SERVER_PRINCIPAL $securableTargetName IMPERSONATE GRANT"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeDiscovery {
        # SQL Server 2022 knows the password hash format of SQL Server 2025 (0x0300) only from CU12 on. No CI
        # environment has an older build of SQL Server 2022, so the check that skips such a login before -Force drops
        # anything can only be covered against a real one, which a lab configuration supplies through
        # InstanceSql2022BeforeCU12. Everywhere else these tests skip themselves. The value decides a Skip, so it has
        # to exist at discovery time.
        $hasSql2022BeforeCU12 = -not [string]::IsNullOrWhiteSpace($TestConfig.InstanceSql2022BeforeCU12)
        # Logins and server roles whose names differ only in case exist on a case sensitive instance only, and a name
        # that matches another one but for accents only on an accent insensitive instance. No CI environment has such
        # an instance, so InstanceCaseSensitive comes from a lab configuration as well.
        $hasCaseSensitive = -not [string]::IsNullOrWhiteSpace($TestConfig.InstanceCaseSensitive)
    }

    Context "Logins and server roles are matched by the collation of the destination (#10772)" -Skip:(-not $hasCaseSensitive) {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $csRandom = Get-Random
            $csDestination = $TestConfig.InstanceCaseSensitive
            $csGranteeName = "dbatoolsci_csgrantee_$csRandom"
            # Two logins and two server roles on the destination that differ only in case. The source, which is case
            # insensitive, has the first of each.
            $csTargetName = "dbatoolsci_CsTarget_$csRandom"
            $csTargetLowerName = $csTargetName.ToLowerInvariant()
            $csRoleName = "dbatoolsci_CsRole_$csRandom"
            $csRoleLowerName = $csRoleName.ToLowerInvariant()
            # A login whose name on the source has accents, and on the destination has none. The test file stays ASCII,
            # because Windows PowerShell reads a file without BOM in the code page of the system.
            $csAccentSourceName = "dbatoolsci_csr" + [char]0x00E9 + "sum" + [char]0x00E9 + "_$csRandom"
            $csAccentDestName = "dbatoolsci_csresume_$csRandom"
            $csPassword = ConvertTo-SecureString -String "dbatools.IO.Target11" -AsPlainText -Force

            $csBehaviourQuery = "SELECT CASE WHEN N'A' = N'a' THEN 0 ELSE 1 END AS IsCaseSensitive, CASE WHEN N'R' + NCHAR(233) + N'sum' + NCHAR(233) = N'Resume' THEN 1 ELSE 0 END AS IsAccentInsensitive"
            $csBehaviour = Invoke-DbaQuery -SqlInstance $csDestination -Query $csBehaviourQuery

            $splatSourceGrantee = @{
                SqlInstance    = $TestConfig.InstanceCopy1
                Login          = $csGranteeName
                SecurePassword = (ConvertTo-SecureString -String "dbatools.IO.Source11" -AsPlainText -Force)
            }
            $csSourceGrantee = New-DbaLogin @splatSourceGrantee
            $splatSourceTargets = @{
                SqlInstance    = $TestConfig.InstanceCopy1
                Login          = $csTargetName, $csAccentSourceName
                SecurePassword = $csPassword
            }
            $null = New-DbaLogin @splatSourceTargets
            $null = New-DbaServerRole -SqlInstance $TestConfig.InstanceCopy1 -ServerRole $csRoleName
            $splatSourceRoleMember = @{
                SqlInstance = $TestConfig.InstanceCopy1
                ServerRole  = $csRoleName
                Login       = $csGranteeName
                Confirm     = $false
            }
            $null = Add-DbaServerRoleMember @splatSourceRoleMember
            $sourceGrants = @(
                "GRANT IMPERSONATE ON LOGIN::[$csTargetName] TO [$csGranteeName]",
                "GRANT VIEW DEFINITION ON LOGIN::[$csAccentSourceName] TO [$csGranteeName]",
                "GRANT VIEW DEFINITION ON SERVER ROLE::[$csRoleName] TO [$csGranteeName]"
            )
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Query ($sourceGrants -join "; ")

            # On the destination, the grantee has the same SID and everything the source login has, on the login and the
            # role with the name of the source, and on the login without accents. In addition it has the same
            # permissions on the login and the role whose names differ only in case, and it is a member of that role,
            # which has CONTROL SERVER.
            $splatDestGrantee = @{
                SqlInstance    = $csDestination
                Login          = $csGranteeName
                SecurePassword = (ConvertTo-SecureString -String "dbatools.IO.Dest11" -AsPlainText -Force)
                Sid            = $csSourceGrantee.Sid
            }
            $null = New-DbaLogin @splatDestGrantee
            $splatDestTargets = @{
                SqlInstance    = $csDestination
                Login          = $csTargetName, $csTargetLowerName, $csAccentDestName
                SecurePassword = $csPassword
            }
            $null = New-DbaLogin @splatDestTargets
            # Through T-SQL: New-DbaServerRole and Add-DbaServerRoleMember compare role names in PowerShell, which ignores
            # case, so they take the second role for the first.
            $csDestSetup = @(
                "CREATE SERVER ROLE [$csRoleName]",
                "CREATE SERVER ROLE [$csRoleLowerName]",
                "GRANT CONTROL SERVER TO [$csRoleLowerName]",
                "ALTER SERVER ROLE [$csRoleName] ADD MEMBER [$csGranteeName]",
                "ALTER SERVER ROLE [$csRoleLowerName] ADD MEMBER [$csGranteeName]",
                "GRANT IMPERSONATE ON LOGIN::[$csTargetName] TO [$csGranteeName]",
                "GRANT IMPERSONATE ON LOGIN::[$csTargetLowerName] TO [$csGranteeName]",
                "GRANT VIEW DEFINITION ON LOGIN::[$csAccentDestName] TO [$csGranteeName]",
                "GRANT VIEW DEFINITION ON SERVER ROLE::[$csRoleName] TO [$csGranteeName]",
                "GRANT VIEW DEFINITION ON SERVER ROLE::[$csRoleLowerName] TO [$csGranteeName]"
            )
            $null = Invoke-DbaQuery -SqlInstance $csDestination -Query ($csDestSetup -join "; ")

            # The assertions compare the principal_id on the destination, so they depend neither on the case insensitive
            # comparison of Pester nor on a name.
            $splatPrincipalIds = @{
                SqlInstance  = $csDestination
                Query        = "SELECT name, principal_id FROM sys.server_principals WHERE name IN (@target, @targetLower, @accent, @role, @roleLower)"
                SqlParameter = @{
                    target      = $csTargetName
                    targetLower = $csTargetLowerName
                    accent      = $csAccentDestName
                    role        = $csRoleName
                    roleLower   = $csRoleLowerName
                }
            }
            # Keys compared by ordinal, as the names on the destination are. A hashtable of PowerShell ignores case.
            $csIdOf = New-Object System.Collections.Hashtable ([System.StringComparer]::Ordinal)
            foreach ($row in (Invoke-DbaQuery @splatPrincipalIds)) {
                $csIdOf[$row.name] = "$($row.principal_id)"
            }
            $splatDestPermState = @{
                SqlInstance  = $csDestination
                Query        = "SELECT p.major_id, p.permission_name FROM sys.server_permissions AS p WHERE p.grantee_principal_id = SUSER_ID(@grantee) AND p.class = 101"
                SqlParameter = @{
                    grantee = $csGranteeName
                }
            }
            $splatDestRoleState = @{
                SqlInstance  = $csDestination
                Query        = "SELECT rm.role_principal_id FROM sys.server_role_members AS rm WHERE rm.member_principal_id = SUSER_ID(@grantee)"
                SqlParameter = @{
                    grantee = $csGranteeName
                }
            }
            $splatCsUpdate = @{
                Source         = $TestConfig.InstanceCopy1
                Destination    = $csDestination
                Login          = $csGranteeName
                UpdateExisting = $true
            }

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $csResult = Copy-DbaLogin @splatCsUpdate
            $csWarn = $WarnVar
            $csPermsAfter = @(Invoke-DbaQuery @splatDestPermState -EnableException | ForEach-Object { "$($PSItem.permission_name) $($PSItem.major_id)" })
            $csRolesAfter = @(Invoke-DbaQuery @splatDestRoleState -EnableException | ForEach-Object { "$($PSItem.role_principal_id)" })
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # The grantee first: the grantor of a permission on a login is that login, and SQL Server drops no login that
            # granted a permission, and no server role that still has members or permissions on it.
            $splatRemoveSourceGrantee = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Login       = $csGranteeName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaLogin @splatRemoveSourceGrantee
            $splatRemoveDestGrantee = @{
                SqlInstance = $csDestination
                Login       = $csGranteeName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaLogin @splatRemoveDestGrantee
            $splatRemoveSourceTargets = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Login       = $csTargetName, $csAccentSourceName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaLogin @splatRemoveSourceTargets
            $splatRemoveDestTargets = @{
                SqlInstance = $csDestination
                Login       = $csTargetName, $csTargetLowerName, $csAccentDestName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaLogin @splatRemoveDestTargets
            $splatRemoveSourceRole = @{
                SqlInstance = $TestConfig.InstanceCopy1
                ServerRole  = $csRoleName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaServerRole @splatRemoveSourceRole
            $splatRemoveDestRole = @{
                SqlInstance = $csDestination
                ServerRole  = $csRoleName, $csRoleLowerName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaServerRole @splatRemoveDestRole

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "points at a case sensitive and accent insensitive instance" {
            # Pointed at another collation, the logins and roles that differ only in case could not be created, or the
            # login without accents would be another login than the one of the source.
            $csBehaviour.IsCaseSensitive | Should -Be 1
            $csBehaviour.IsAccentInsensitive | Should -Be 1
            $csIdOf.Count | Should -Be 5
        }

        It "updates the login in place" {
            $csWarn | Should -BeNullOrEmpty
            $csResult.Status | Should -Be "Successful"
            $csResult.Name | Should -Be $csGranteeName
        }

        It "revokes the permission on the login whose name differs only in case and keeps the one on the login of the source" {
            $csPermsAfter | Should -Contain "IMPERSONATE $($csIdOf[$csTargetName])"
            $csPermsAfter | Should -Not -Contain "IMPERSONATE $($csIdOf[$csTargetLowerName])"
        }

        It "revokes the permission on the role whose name differs only in case and keeps the one on the role of the source" {
            $csPermsAfter | Should -Contain "VIEW DEFINITION $($csIdOf[$csRoleName])"
            $csPermsAfter | Should -Not -Contain "VIEW DEFINITION $($csIdOf[$csRoleLowerName])"
        }

        It "keeps the permission on the login that the destination takes for the login of the source, accents aside" {
            $csPermsAfter | Should -Contain "VIEW DEFINITION $($csIdOf[$csAccentDestName])"
        }

        It "takes the login out of the role whose name differs only in case and leaves it in the role of the source" {
            $csRolesAfter | Should -Contain $csIdOf[$csRoleName]
            $csRolesAfter | Should -Not -Contain $csIdOf[$csRoleLowerName]
        }
    }

    Context "An existing login is not dropped when SQL Server 2022 before CU12 cannot take the password hash of the source login (#10772)" -Skip:(-not $hasSql2022BeforeCU12) {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $cu12Random = Get-Random
            $cu12LoginName = "dbatoolsci_cu12hash_$cu12Random"
            $cu12Destination = $TestConfig.InstanceSql2022BeforeCU12
            $cu12HashQuery = @"
SELECT CONVERT(VARCHAR(514), CAST(LOGINPROPERTY(N'$cu12LoginName', 'PasswordHash') AS VARBINARY(256)), 1)
"@

            $cu12DestVersion = (Connect-DbaInstance -SqlInstance $cu12Destination).Version

            # The password hash of "dbatools.IO.Source9" in the format of SQL Server 2025, made by SQL Server 2025. The
            # source login is created from it, so the source can be any instance that knows the format: SQL Server
            # 2022 from CU12 on, or SQL Server 2025. InstanceCopy2 is one of them wherever this context runs.
            $cu12SourceHash = "0x03001C3F1BAA67E7F8C500997103B0E68A42875FD3797BCA099FF16DC9746C9265CF1413389A57972AFBE2419E6B8B13340A43B21B078A28EAC386EB08E4D52042E5E0DACBF6"
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Query "CREATE LOGIN [$cu12LoginName] WITH PASSWORD = $cu12SourceHash HASHED, CHECK_POLICY = OFF"
            $splatSourceHash = @{
                SqlInstance = $TestConfig.InstanceCopy2
                Query       = $cu12HashQuery
                As          = "SingleValue"
            }
            $cu12StoredSourceHash = Invoke-DbaQuery @splatSourceHash
            $cu12SourceLogin = Get-DbaLogin -SqlInstance $TestConfig.InstanceCopy2 -Login $cu12LoginName
            $cu12SourceSid = [System.BitConverter]::ToString($cu12SourceLogin.Sid)

            # The destination login has a SID of its own, so -Force and -UpdateExisting -Force drop and recreate it.
            $splatDestLogin = @{
                SqlInstance    = $cu12Destination
                Login          = $cu12LoginName
                SecurePassword = (ConvertTo-SecureString -String "dbatools.IO.Dest9" -AsPlainText -Force)
            }
            $cu12DestLogin = New-DbaLogin @splatDestLogin
            $cu12DestSidBefore = [System.BitConverter]::ToString($cu12DestLogin.Sid)
            $splatDestHash = @{
                SqlInstance = $cu12Destination
                Query       = $cu12HashQuery
                As          = "SingleValue"
            }
            $cu12DestHashBefore = Invoke-DbaQuery @splatDestHash

            $splatForceCopy = @{
                Source        = $TestConfig.InstanceCopy2
                Destination   = $cu12Destination
                Login         = $cu12LoginName
                Force         = $true
                WarningAction = "SilentlyContinue"
            }
            $splatUpdateForceCopy = @{
                Source         = $TestConfig.InstanceCopy2
                Destination    = $cu12Destination
                Login          = $cu12LoginName
                UpdateExisting = $true
                Force          = $true
                WarningAction  = "SilentlyContinue"
            }
            $splatDestLoginState = @{
                SqlInstance = $cu12Destination
                Login       = $cu12LoginName
            }

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $cu12ForceResult = Copy-DbaLogin @splatForceCopy
            $cu12ForceWarn = $WarnVar
            $cu12DestLoginAfterForce = Get-DbaLogin @splatDestLoginState -EnableException
            $cu12DestHashAfterForce = Invoke-DbaQuery @splatDestHash -EnableException
            $cu12UpdateForceResult = Copy-DbaLogin @splatUpdateForceCopy
            $cu12UpdateForceWarn = $WarnVar
            $cu12DestLoginAfterUpdateForce = Get-DbaLogin @splatDestLoginState -EnableException
            $cu12DestHashAfterUpdateForce = Invoke-DbaQuery @splatDestHash -EnableException
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $splatRemoveSourceLogin = @{
                SqlInstance = $TestConfig.InstanceCopy2
                Login       = $cu12LoginName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaLogin @splatRemoveSourceLogin
            $splatRemoveDestLogin = @{
                SqlInstance = $cu12Destination
                Login       = $cu12LoginName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaLogin @splatRemoveDestLogin

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "points at SQL Server 2022 before CU12" {
            # Pointed at a newer build the tests below would fail, because the login is copied, but pointed at an
            # older version they would pass while saying nothing about SQL Server 2022.
            $cu12DestVersion.Major | Should -Be 16
            $cu12DestVersion | Should -BeLessThan ([version]"16.0.4115")
        }

        It "has a source login with a password hash in the format of SQL Server 2025 and another SID" {
            $cu12StoredSourceHash | Should -Be $cu12SourceHash
            $cu12DestSidBefore | Should -Not -Be $cu12SourceSid
        }

        It "skips the login with -Force and leaves the destination login as it was" {
            $cu12ForceResult.Status | Should -Be "Skipped"
            $cu12ForceResult.Notes | Should -Be "Password hash format of SQL Server 2025 not supported by destination"
            ($cu12ForceWarn -join " ") | Should -Match "has the format of SQL Server 2025, which .* does not support"
            $cu12DestLoginAfterForce | Should -Not -BeNullOrEmpty
            [System.BitConverter]::ToString($cu12DestLoginAfterForce.Sid) | Should -Be $cu12DestSidBefore
            $cu12DestHashAfterForce | Should -Be $cu12DestHashBefore
        }

        It "skips the login with -UpdateExisting -Force and a different SID and leaves the destination login as it was" {
            $cu12UpdateForceResult.Status | Should -Be "Skipped"
            $cu12UpdateForceResult.Notes | Should -Be "Password hash format of SQL Server 2025 not supported by destination"
            ($cu12UpdateForceWarn -join " ") | Should -Match "has the format of SQL Server 2025, which .* does not support"
            $cu12DestLoginAfterUpdateForce | Should -Not -BeNullOrEmpty
            [System.BitConverter]::ToString($cu12DestLoginAfterUpdateForce.Sid) | Should -Be $cu12DestSidBefore
            $cu12DestHashAfterUpdateForce | Should -Be $cu12DestHashBefore
        }
    }
}
