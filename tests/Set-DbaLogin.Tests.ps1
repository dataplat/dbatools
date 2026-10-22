#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaLogin",
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
                "Login",
                "SecurePassword",
                "PasswordHash",
                "DefaultDatabase",
                "Unlock",
                "PasswordMustChange",
                "NewName",
                "Disable",
                "Enable",
                "DenyLogin",
                "GrantLogin",
                "PasswordPolicyEnforced",
                "PasswordExpirationEnabled",
                "AddRole",
                "RemoveRole",
                "Force",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Parameter validation" {
        BeforeDiscovery {
            # -TestCases is read while Pester discovers the tests. Built in the BeforeAll below, as it
            # was before, this list was still empty at discovery, so neither of the role tests existed
            # at all - and with Pester 6 the empty list fails the whole file during discovery.
            $systemRoles = @(
                @{role = "bulkadmin" },
                @{role = "dbcreator" },
                @{role = "diskadmin" },
                @{role = "processadmin" },
                @{role = "public" },
                @{role = "securityadmin" },
                @{role = "serveradmin" },
                @{role = "setupadmin" },
                @{role = "sysadmin" }
            )

            # The parameter checks that used Stop-Function -Continue in the begin block, one case each.
            $invalidCombinations = @(
                @{
                    Check      = "-NewName equals -Login"
                    Parameters = @{ Login = "testlogin"; NewName = "testlogin" }
                    Message    = "Login name is the same as the value in -NewName"
                },
                @{
                    Check      = "-Enable with -Disable"
                    Parameters = @{ Login = "testlogin"; Enable = $true; Disable = $true }
                    Message    = "You cannot use both -Enable and -Disable together"
                },
                @{
                    Check      = "-GrantLogin with -DenyLogin"
                    Parameters = @{ Login = "testlogin"; GrantLogin = $true; DenyLogin = $true }
                    Message    = "You cannot use both -GrantLogin and -DenyLogin together"
                },
                @{
                    Check      = "-SecurePassword with -PasswordHash"
                    Parameters = @{ Login = "testlogin"; SecurePassword = (ConvertTo-SecureString -String "dbatools.IO" -AsPlainText -Force); PasswordHash = "0x0200" }
                    Message    = "You cannot use both -SecurePassword and -PasswordHash together"
                },
                @{
                    Check      = "-PasswordHash with -PasswordMustChange"
                    Parameters = @{ Login = "testlogin"; PasswordHash = "0x0200"; PasswordMustChange = $true }
                    Message    = "You cannot use -PasswordHash with -PasswordMustChange"
                },
                @{
                    Check      = "-PasswordHash not hexadecimal"
                    Parameters = @{ Login = "testlogin"; PasswordHash = "nothex" }
                    Message    = "PasswordHash must be in hexadecimal format starting with 0x"
                }
            )
        }

        BeforeAll {
            $command = Get-Command $CommandName
        }

        It "Validates -AddRole contains <role>" -TestCases $systemRoles {
            param ($role)
            $command.Parameters['AddRole'].Attributes.ValidValues | Should -Contain $role
        }

        It "Validates -RemoveRole contains <role>" -TestCases $systemRoles {
            param ($role)
            $command.Parameters['RemoveRole'].Attributes.ValidValues | Should -Contain $role
        }

        It "Validates -Login and -NewName aren't the same" {
            { Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login testlogin -NewName testLogin -EnableException } | Should -Throw 'Login name is the same as the value in -NewName'
        }

        It "Validates -Enable and -Disable aren't used together" {
            { Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login testlogin -Enable -Disable -EnableException } | Should -Throw 'You cannot use both -Enable and -Disable together'
        }

        It "Validates -GrantLogin and -DenyLogin aren't used together" {
            { Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login testlogin -GrantLogin -DenyLogin -EnableException } | Should -Throw 'You cannot use both -GrantLogin and -DenyLogin together'
        }

        It "Validates -Login is required when using -SqlInstance" {
            { Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -EnableException } | Should -Throw 'You must specify a Login when using SqlInstance'
        }

        It "Validates -Password is a SecureString or PSCredential" {
            { Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login 'testLogin' -Password 'password' -EnableException } | Should -Throw 'Password must be a PSCredential or SecureString'
        }

        It "Warns about <Check> without eating an iteration of the caller loop" -ForEach $invalidCombinations {
            # These checks used Stop-Function -Continue in the begin block, where no loop encloses it - the
            # continue escaped the command and consumed an iteration of this very loop, so the counter stayed at zero.
            $loopCount = 0
            foreach ($i in 1..3) {
                $null = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle @Parameters -WarningAction SilentlyContinue
                $loopCount++
            }
            $loopCount | Should -Be 3
            $WarnVar | Should -BeLike "*$Message*"
        }
    }
}

Describe "$CommandName Integration Tests" -Tag 'IntegrationTests' {
    Context "verify command functions" {
        BeforeAll {
            $random = Get-Random

            # Create the new password
            $password1 = ConvertTo-SecureString -String "password1A@" -AsPlainText -Force
            $password2 = ConvertTo-SecureString -String "password2A@" -AsPlainText -Force

            # Create the login
            New-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random", "testlogin2_$random" -Password $password1

            New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name "testdb1_$random"
        }

        AfterAll {
            Remove-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random", "testlogin2_$random" -Force
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database "testdb1_$random"
        }

        It "Does test login exist" {
            $logins = Get-DbaLogin -SqlInstance $TestConfig.InstanceSingle | Where-Object { $_.Name -eq "testlogin1_$random" } | Select-Object Name
            $logins.Name | Should -Be "testlogin1_$random"
        }

        It "Verifies -NewName doesn't already exist when renaming a login" {
            $result = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -NewName 'sa' -EnableException

            $result.Notes | Should -Be 'New login name already exists'
        }

        It 'Change the password from a SecureString' {
            $result = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -Password $password2

            $result.PasswordChanged | Should -Be $true
        }

        It 'Changes the password from a PSCredential' {
            $cred = New-Object System.Management.Automation.PSCredential ("testlogin1_$random", $password2)
            $result = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -Password $cred

            $result.PasswordChanged | Should -Be $true
        }

        It "Verifies -NewName doesn't already exist when renaming a piped login" {
            # A piped login has no entry in the list of the logins of -SqlInstance, which the check used before.
            $login = Get-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random"
            $result = $login | Set-DbaLogin -NewName "testlogin2_$random"

            $WarnVar | Should -BeNullOrEmpty
            $result.Name | Should -Be "testlogin1_$random"
            $result.Notes | Should -Be "New login name already exists"
        }

        It "Change the password from piped Login" {
            $login = Get-DbaLogin -Sqlinstance $TestConfig.InstanceSingle -Login "testlogin1_$random"

            $result = $login | Set-DbaLogin -Password $password2
            $result.PasswordChanged | Should -Be $true
        }

        It "Change the password from InputObject" {
            $login = Get-DbaLogin -Sqlinstance $TestConfig.InstanceSingle -Login "testlogin1_$random"

            $result = Set-DbaLogin -InputObject $login -Password $password2
            $result.PasswordChanged | Should -Be $true
        }

        It "Disable the login" {
            $result = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -Disable
            $result.IsDisabled | Should -Be $true
        }

        It "Enable the login" {
            $result = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -Enable
            $result.IsDisabled | Should -Be $false
        }

        It "Deny access to login" {
            $result = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -DenyLogin

            $result.DenyLogin | Should -Be $true
        }

        It "Grant access to login" {
            $result = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -GrantLogin

            $result.DenyLogin | Should -Be $false
        }

        It "Enforces password policy on login" {
            $result = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -PasswordPolicyEnforced

            $result.PasswordPolicyEnforced | Should -Be $true
        }

        It "Catches errors when password can't be changed" {
            # enforce password policy
            $result = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -PasswordPolicyEnforced -EnableException
            $result.PasswordPolicyEnforced | Should -Be $true

            # violate policy
            $invalidPassword = ConvertTo-SecureString -String "password1" -AsPlainText -Force

            $result = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -Password $invalidPassword -WarningAction 'SilentlyContinue'
            $result | Should -Be $null

            { Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -Password $invalidPassword -EnableException } | Should -Throw
        }

        It "Disables enforcing password policy on login" {
            $result = Get-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random"
            $result.PasswordPolicyEnforced | Should -Be $true

            $result = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -PasswordPolicyEnforced:$false
            $result.PasswordPolicyEnforced | Should -Be $false
        }

        It "Add roles to login" {
            $result = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -AddRole serveradmin, processadmin

            $result.ServerRole | Should -Be "processadmin, serveradmin"
        }

        It "Remove roles from login" {
            $result = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -RemoveRole serveradmin

            $result.ServerRole | Should -Be "processadmin"
        }

        It "Results include multiple changed objects" {
            $results = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random", "testlogin2_$random" -DenyLogin
            $results.Count | Should -Be 2
            foreach ($r in $results) {
                $r.DenyLogin | Should -Be $true
            }
        }

        It "DefaultDatabase" {
            $results = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -DefaultDatabase "testdb1_$random"
            $results.DefaultDatabase | Should -Be "testdb1_$random"
        }

        It "PasswordExpirationEnabled" {
            $result = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin2_$random" -PasswordPolicyEnforced
            $result.PasswordPolicyEnforced | Should -Be $true

            # testlogin1_$random will get skipped since it does not have PasswordPolicyEnforced set to true (check_policy = ON)
            $result = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random", "testlogin2_$random" -PasswordExpirationEnabled -WarningAction SilentlyContinue
            $WarnVar | Should -Match "Couldn't set check_expiration = ON because check_policy = OFF for \[testlogin1_$random\]"
            $result.Count | Should -Be 1
            $result.Name | Should -Be "testlogin2_$random"
            $result.PasswordExpirationEnabled | Should -Be $true

            # set both params for this login
            $result = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -PasswordPolicyEnforced -PasswordExpirationEnabled
            $result.PasswordExpirationEnabled | Should -Be $true
            $result.PasswordPolicyEnforced | Should -Be $true

            # disable the setting for this login
            $result = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -PasswordExpirationEnabled:$false
            $result.PasswordExpirationEnabled | Should -Be $false
        }

        It "Ensure both password policy settings can be disabled at the same time" {
            $result = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -PasswordPolicyEnforced -PasswordExpirationEnabled
            $result.PasswordExpirationEnabled | Should -Be $true
            $result.PasswordPolicyEnforced | Should -Be $true

            $result = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -PasswordPolicyEnforced:$false -PasswordExpirationEnabled:$false
            $result.PasswordExpirationEnabled | Should -Be $false
            $result.PasswordPolicyEnforced | Should -Be $false
        }

        # A login can only be locked out when the host running the instance has an account lockout
        # threshold, so this test needs one that is not higher than the number of failed logons below.
        It "unlocks a login that was locked out" {
            $results = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -PasswordPolicyEnforced -EnableException
            $results.PasswordPolicyEnforced | Should -Be $true

            # simulate a lockout
            $invalidPassword = ConvertTo-SecureString -String 'invalid' -AsPlainText -Force
            $invalidSqlCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "testlogin1_$random", $invalidPassword

            # exceed the lockout count
            for (($i = 0); $i -le 4; $i++) {
                try {
                    # NonPooledConnection, because after a failed logon SqlClient blocks the pool for a
                    # growing number of seconds and answers the following attempts itself. Those never
                    # reach the instance, so the bad password count stops climbing before it reaches the
                    # lockout threshold and the login is never locked.
                    $null = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -SqlCredential $invalidSqlCredential -NonPooledConnection
                } catch {
                    # Verbose, not a warning: the failed logon is on purpose and a test run must not print warnings.
                    Write-Verbose -Message "invalid login credentials used on purpose to lock out account"
                }
            }

            $results = Get-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random"
            $results.IsLocked | Should -Be $true

            # this will generate a warning since neither the password or the -force param is specified
            $results = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -Unlock -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
            ($WarnVar -join " ") | Should -Match "Force"

            # this will use the workaround solution to turn off/on the check_policy
            $results = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -Unlock -Force
            $results.IsLocked | Should -Be $false

            # exceed the lockout count again
            for (($i = 0); $i -le 4; $i++) {
                try {
                    # NonPooledConnection, because after a failed logon SqlClient blocks the pool for a
                    # growing number of seconds and answers the following attempts itself. Those never
                    # reach the instance, so the bad password count stops climbing before it reaches the
                    # lockout threshold and the login is never locked.
                    $null = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -SqlCredential $invalidSqlCredential -NonPooledConnection
                } catch {
                    # Verbose, not a warning: the failed logon is on purpose and a test run must not print warnings.
                    Write-Verbose -Message "invalid login credentials used on purpose to lock out account"
                }
            }

            # unlock by resetting the password
            $results = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -Unlock -SecurePassword $password1
            $results.IsLocked | Should -Be $false
        }

        It "PasswordMustChange" {
            # password is required
            $changeResult = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -PasswordMustChange -WarningAction SilentlyContinue
            $WarnVar | Should -Match "You must specify a password when using the -PasswordMustChange parameter"
            $changeResult | Should -BeNullOrEmpty

            # ensure the policy settings are off
            $result = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -PasswordPolicyEnforced:$false -PasswordExpirationEnabled:$false
            $result.PasswordExpirationEnabled | Should -Be $false
            $result.PasswordPolicyEnforced | Should -Be $false

            # set the policy options separately for testlogin2
            $changeResult = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin2_$random" -PasswordPolicyEnforced -PasswordExpirationEnabled
            $changeResult.PasswordPolicyEnforced | Should -Be $true
            $changeResult.PasswordExpirationEnabled | Should -Be $true

            # check_policy and check_expiration must be set on the login
            $changeResult = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random", "testlogin2_$random" -PasswordMustChange -Password $password1 -WarningAction SilentlyContinue
            $WarnVar | Should -Match "Unable to change the password and set the must_change option for \[testlogin1_$random\] because check_policy = False and check_expiration = False"
            $changeResult.Count | Should -Be 1
            $changeResult.Name | Should -Be "testlogin2_$random"

            $changeResult = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -PasswordMustChange -Password $password1 -PasswordPolicyEnforced -PasswordExpirationEnabled
            $changeResult.MustChangePassword | Should -Be $true
            $changeResult.PasswordChanged | Should -Be $true
            $changeResult.PasswordPolicyEnforced | Should -Be $true
            $changeResult.PasswordExpirationEnabled | Should -Be $true

            # now change the password and set the must_change
            $changeResult = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin2_$random" -PasswordMustChange -Password $password1
            $changeResult.MustChangePassword | Should -Be $true
            $changeResult.PasswordChanged | Should -Be $true

            # get a listing of the logins that must change their password
            $result = Get-DbaLogin -SqlInstance $TestConfig.InstanceSingle -MustChangePassword
            $result.Name | Should -Contain "testlogin1_$random"
            $result.Name | Should -Contain "testlogin2_$random"
        }
    }

    Context "Sets the password from a hash" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $hashRandom = Get-Random
            $hashSourceName = "dbatoolsci_hashsource_$hashRandom"
            $hashPolicyName = "dbatoolsci_hashpolicy_$hashRandom"
            # A quote and a closing bracket, which the name has to survive in the ALTER LOGIN statement.
            $hashQuoteName = "dbatoolsci_hash'quote]_$hashRandom"
            $hashPassword = "dbatools.IO.Hash1"

            # The source of the hash, with a password the tests can log in with.
            $splatSourceLogin = @{
                SqlInstance    = $TestConfig.InstanceSingle
                Login          = $hashSourceName
                SecurePassword = (ConvertTo-SecureString -String $hashPassword -AsPlainText -Force)
            }
            $null = New-DbaLogin @splatSourceLogin

            # Password policy and expiration on, as a login can have them. SQL Server refuses a hashed password for
            # such a login with error 33020.
            $splatPolicyLogin = @{
                SqlInstance               = $TestConfig.InstanceSingle
                Login                     = $hashPolicyName
                SecurePassword            = (ConvertTo-SecureString -String "dbatools.IO.Other1" -AsPlainText -Force)
                PasswordPolicyEnforced    = $true
                PasswordExpirationEnabled = $true
            }
            $null = New-DbaLogin @splatPolicyLogin

            # New-DbaLogin takes the brackets out of a name, so this one is created with T-SQL.
            $quoteLoginQuery = "CREATE LOGIN [$($hashQuoteName.Replace("]", "]]"))] WITH PASSWORD = N'dbatools.IO.Other1', CHECK_POLICY = OFF"
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query $quoteLoginQuery

            # Read from sys.sql_logins, so the assertions don't depend on cached SMO objects.
            $loginStateQuery = "SELECT CONVERT(VARCHAR(514), password_hash, 1) AS password_hash, is_policy_checked, is_expiration_checked FROM sys.sql_logins WHERE name = @name"
            $splatSourceState = @{
                SqlInstance  = $TestConfig.InstanceSingle
                Query        = $loginStateQuery
                SqlParameter = @{ name = $hashSourceName }
            }
            $splatPolicyState = @{
                SqlInstance  = $TestConfig.InstanceSingle
                Query        = $loginStateQuery
                SqlParameter = @{ name = $hashPolicyName }
            }
            $splatQuoteState = @{
                SqlInstance  = $TestConfig.InstanceSingle
                Query        = $loginStateQuery
                SqlParameter = @{ name = $hashQuoteName }
            }
            $sourceHash = (Invoke-DbaQuery @splatSourceState).password_hash

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $splatRemoveLogin = @{
                SqlInstance = $TestConfig.InstanceSingle
                Login       = $hashSourceName, $hashPolicyName, $hashQuoteName
                Force       = $true
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaLogin @splatRemoveLogin

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "sets the hash on a login with password policy and expiration on, and keeps both on" {
            $result = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $hashPolicyName -PasswordHash $sourceHash

            $WarnVar | Should -BeNullOrEmpty
            $result.PasswordChanged | Should -BeTrue
            $state = Invoke-DbaQuery @splatPolicyState
            $state.password_hash | Should -Be $sourceHash
            $state.is_policy_checked | Should -BeTrue
            $state.is_expiration_checked | Should -BeTrue
        }

        It "lets the login connect with the password the hash came from" {
            $splatConnect = @{
                SqlInstance         = $TestConfig.InstanceSingle
                SqlCredential       = New-Object System.Management.Automation.PSCredential ($hashPolicyName, (ConvertTo-SecureString -String $hashPassword -AsPlainText -Force))
                NonPooledConnection = $true
            }
            $loginServer = Connect-DbaInstance @splatConnect
            try {
                $loginServer.ConnectionContext.ExecuteScalar("SELECT SUSER_SNAME()") | Should -Be $hashPolicyName
            } finally {
                # An open session would keep AfterAll from removing the login.
                $null = $loginServer | Disconnect-DbaInstance
            }
        }

        It "sets the hash on a login whose name contains a quote and a closing bracket" {
            $result = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $hashQuoteName -PasswordHash $sourceHash

            $WarnVar | Should -BeNullOrEmpty
            $result.PasswordChanged | Should -BeTrue
            (Invoke-DbaQuery @splatQuoteState).password_hash | Should -Be $sourceHash
        }
    }

    Context "Sets the password from a hash inside a transaction of the caller" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $tranRandom = Get-Random
            $tranSourceName = "dbatoolsci_transource_$tranRandom"
            $tranPolicyName = "dbatoolsci_tranpolicy_$tranRandom"

            $splatTranSource = @{
                SqlInstance    = $TestConfig.InstanceSingle
                Login          = $tranSourceName
                SecurePassword = (ConvertTo-SecureString -String "dbatools.IO.Hash2" -AsPlainText -Force)
            }
            $null = New-DbaLogin @splatTranSource
            # Password policy on, so the command turns it off before it sets the hash and has to turn it back on.
            $splatTranPolicy = @{
                SqlInstance            = $TestConfig.InstanceSingle
                Login                  = $tranPolicyName
                SecurePassword         = (ConvertTo-SecureString -String "dbatools.IO.Other2" -AsPlainText -Force)
                PasswordPolicyEnforced = $true
            }
            $null = New-DbaLogin @splatTranPolicy
            $splatTranSourceHash = @{
                SqlInstance  = $TestConfig.InstanceSingle
                Query        = "SELECT CONVERT(VARCHAR(514), password_hash, 1) AS password_hash FROM sys.sql_logins WHERE name = @name"
                SqlParameter = @{ name = $tranSourceName }
            }
            $tranSourceHash = (Invoke-DbaQuery @splatTranSourceHash).password_hash

            # The caller opens a transaction and does work of its own in it, which a rollback of the whole transaction
            # would take back. The connection is not pooled, so the transaction stays on its session between the
            # commands. A piped login brings the connection of its server, so the command works in that transaction.
            $callerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection
            $callerServer.ConnectionContext.BeginTransaction()
            $null = $callerServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE #dbatoolsci_callerwork (id INT)")
            $tranLogin = Get-DbaLogin -SqlInstance $callerServer -Login $tranPolicyName

            # Read on the connection of the caller, which sees the uncommitted changes of its own transaction and is not
            # blocked by them.
            $callerStateQuery = @"
SELECT @@TRANCOUNT AS tran_count,
       CASE WHEN OBJECT_ID(N'tempdb..#dbatoolsci_callerwork') IS NULL THEN 0 ELSE 1 END AS caller_work,
       CONVERT(VARCHAR(514), password_hash, 1) AS password_hash,
       is_policy_checked
FROM sys.sql_logins
WHERE name = N'$tranPolicyName'
"@
            $stateBefore = $callerServer.Query($callerStateQuery)

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            # A valid binary value, but no password hash. SQL Server refuses it after the policy was turned off.
            $failedResult = $tranLogin | Set-DbaLogin -PasswordHash 0x1234 -WarningAction SilentlyContinue
            $failedWarn = $WarnVar
            $stateAfterFailure = $callerServer.Query($callerStateQuery)

            $successResult = $tranLogin | Set-DbaLogin -PasswordHash $tranSourceHash
            $successWarn = $WarnVar
            $stateAfterSuccess = $callerServer.Query($callerStateQuery)
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # The caller takes its transaction back, with the hash that was set in it.
            if ($callerServer.ConnectionContext.ExecuteScalar("SELECT @@TRANCOUNT") -gt 0) {
                $callerServer.ConnectionContext.RollBackTransaction()
            }
            $null = $callerServer | Disconnect-DbaInstance
            $splatRemoveTranLogin = @{
                SqlInstance = $TestConfig.InstanceSingle
                Login       = $tranSourceName, $tranPolicyName
                Force       = $true
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaLogin @splatRemoveTranLogin

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "warns about the refused hash" {
            $failedResult | Should -BeNullOrEmpty
            ($failedWarn -join " ") | Should -BeLike "*Something went wrong setting the password hash for*$tranPolicyName*"
        }

        It "keeps the transaction of the caller and the work done in it when the hash is refused" {
            $stateAfterFailure.tran_count | Should -Be 1
            $stateAfterFailure.caller_work | Should -Be 1
        }

        It "takes back its own statements when the hash is refused, so the policy is on again" {
            $stateAfterFailure.password_hash | Should -Be $stateBefore.password_hash
            $stateAfterFailure.is_policy_checked | Should -BeTrue
        }

        It "sets the hash inside the transaction of the caller and leaves the transaction open" {
            $successWarn | Should -BeNullOrEmpty
            $successResult.PasswordChanged | Should -BeTrue
            $stateAfterSuccess.tran_count | Should -Be 1
            $stateAfterSuccess.caller_work | Should -Be 1
            $stateAfterSuccess.password_hash | Should -Be $tranSourceHash
            $stateAfterSuccess.is_policy_checked | Should -BeTrue
        }
    }
}