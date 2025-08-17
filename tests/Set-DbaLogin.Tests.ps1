$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Parameter validation" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('WhatIf', 'Confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Login', 'SecurePassword', 'DefaultDatabase', 'Unlock', 'PasswordMustChange', 'NewName', 'Disable', 'Enable', 'DenyLogin', 'GrantLogin', 'PasswordPolicyEnforced', 'PasswordExpirationEnabled', 'AddRole', 'RemoveRole', 'Force', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }

        $systemRoles = @(
            @{role = 'bulkadmin' },
            @{role = 'dbcreator' },
            @{role = 'diskadmin' },
            @{role = 'processadmin' },
            @{role = 'public' },
            @{role = 'securityadmin' },
            @{role = 'serveradmin' },
            @{role = 'setupadmin' },
            @{role = 'sysadmin' }
        )

        $command = Get-Command $CommandName

        It "Validates -AddRole contains <role>" -TestCases $systemRoles {
            param ($role)
            $command.Parameters['AddRole'].Attributes.ValidValues | Should -Contain $role
        }

        It "Validates -RemoveRole contains <role>" -TestCases $systemRoles {
            param ($role)
            $command.Parameters['RemoveRole'].Attributes.ValidValues | Should -Contain $role
        }

        It "Validates -Login and -NewName aren't the same" {
            { Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login testlogin -NewName testLogin -EnableException } | Should -Throw 'Login name is the same as the value in -NewName'
        }

        It "Validates -Enable and -Disable aren't used together" {
            { Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login testlogin -Enable -Disable -EnableException } | Should -Throw 'You cannot use both -Enable and -Disable together'
        }

        It "Validates -GrantLogin and -DenyLogin aren't used together" {
            { Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login testlogin -GrantLogin -DenyLogin -EnableException } | Should -Throw 'You cannot use both -GrantLogin and -DenyLogin together'
        }

        It "Validates -Login is required when using -SqlInstance" {
            { Set-DbaLogin -SqlInstance $TestConfig.instance2 -EnableException } | Should -Throw 'You must specify a Login when using SqlInstance'
        }

        It "Validates -Password is a SecureString or PSCredential" {
            { Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login 'testLogin' -Password 'password' -EnableException } | Should -Throw 'Password must be a PSCredential or SecureString'
        }
    }
}

Describe "$CommandName Integration Tests" -Tag 'IntegrationTests' {
    Context "verify command functions" {
        BeforeAll {
            $SkipLocalTest = $true # Change to $false to run the local-only tests on a local instance. This is being used because the 'locked' test makes assumptions the password policy configuration is enabled for the Windows OS.
            $random = Get-Random

            # Create the new password
            $password1 = ConvertTo-SecureString -String "password1A@" -AsPlainText -Force
            $password2 = ConvertTo-SecureString -String "password2A@" -AsPlainText -Force

            # Create the login
            New-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random", "testlogin2_$random" -Password $password1

            New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name "testdb1_$random" -Confirm:$false
        }

        AfterAll {
            Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random", "testlogin2_$random" -Confirm:$false -Force
            Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database "testdb1_$random" -Confirm:$false
        }

        It "Does test login exist" {
            $logins = Get-DbaLogin -SqlInstance $TestConfig.instance2 | Where-Object { $_.Name -eq "testlogin1_$random" } | Select-Object Name
            $logins.Name | Should -Be "testlogin1_$random"
        }

        It "Verifies -NewName doesn't already exist when renaming a login" {
            $result = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random" -NewName 'sa' -EnableException

            $result.Notes | Should -Be 'New login name already exists'
        }

        It 'Change the password from a SecureString' {
            $result = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random" -Password $password2

            $result.PasswordChanged | Should -Be $true
        }

        It 'Changes the password from a PSCredential' {
            $cred = New-Object System.Management.Automation.PSCredential ("testlogin1_$random", $password2)
            $result = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random" -Password $cred

            $result.PasswordChanged | Should -Be $true
        }

        It "Change the password from piped Login" {
            $login = Get-DbaLogin -Sqlinstance $TestConfig.instance2 -Login "testlogin1_$random"

            $result = $login | Set-DbaLogin -Password $password2
            $result.PasswordChanged | Should -Be $true
        }

        It "Change the password from InputObject" {
            $login = Get-DbaLogin -Sqlinstance $TestConfig.instance2 -Login "testlogin1_$random"

            $result = Set-DbaLogin -InputObject $login -Password $password2
            $result.PasswordChanged | Should -Be $true
        }

        It "Disable the login" {
            $result = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random" -Disable
            $result.IsDisabled | Should -Be $true
        }

        It "Enable the login" {
            $result = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random" -Enable
            $result.IsDisabled | Should -Be $false
        }

        It "Deny access to login" {
            $result = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random" -DenyLogin

            $result.DenyLogin | Should -Be $true
        }

        It "Grant access to login" {
            $result = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random" -GrantLogin

            $result.DenyLogin | Should -Be $false
        }

        It "Enforces password policy on login" {
            $result = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random" -PasswordPolicyEnforced

            $result.PasswordPolicyEnforced | Should Be $true
        }

        It "Catches errors when password can't be changed" {
            # enforce password policy
            $result = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random" -PasswordPolicyEnforced -EnableException
            $result.PasswordPolicyEnforced | Should -Be $true

            # violate policy
            $invalidPassword = ConvertTo-SecureString -String "password1" -AsPlainText -Force

            $result = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random" -Password $invalidPassword -WarningAction 'SilentlyContinue'
            $result | Should -Be $null

            { Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random" -Password $invalidPassword -EnableException } | Should -Throw
        }

        It "Disables enforcing password policy on login" {
            $result = Get-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random"
            $result.PasswordPolicyEnforced | Should Be $true

            $result = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random" -PasswordPolicyEnforced:$false
            $result.PasswordPolicyEnforced | Should Be $false
        }

        It "Add roles to login" {
            $result = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random" -AddRole serveradmin, processadmin

            $result.ServerRole | Should -Be "processadmin, serveradmin"
        }

        It "Remove roles from login" {
            $result = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random" -RemoveRole serveradmin

            $result.ServerRole | Should -Be "processadmin"
        }

        It "Results include multiple changed objects" {
            $results = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random", "testlogin2_$random" -DenyLogin
            $results.Count | Should -Be 2
            foreach ($r in $results) {
                $r.DenyLogin | Should -Be $true
            }
        }

        It "DefaultDatabase" {
            $results = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random" -DefaultDatabase "testdb1_$random"
            $results.DefaultDatabase | Should -Be "testdb1_$random"
        }

        It "PasswordExpirationEnabled" {
            $result = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin2_$random" -PasswordPolicyEnforced
            $result.PasswordPolicyEnforced | Should Be $true

            # testlogin1_$random will get skipped since it does not have PasswordPolicyEnforced set to true (check_policy = ON)
            $result = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random", "testlogin2_$random" -PasswordExpirationEnabled -WarningAction SilentlyContinue -WarningVariable WarnVar
            $WarnVar | Should -Match "Couldn't set check_expiration = ON because check_policy = OFF for \[testlogin1_$random\]"
            $result.Count | Should -Be 1
            $result.Name | Should -Be "testlogin2_$random"
            $result.PasswordExpirationEnabled | Should Be $true

            # set both params for this login
            $result = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random" -PasswordPolicyEnforced -PasswordExpirationEnabled
            $result.PasswordExpirationEnabled | Should -Be $true
            $result.PasswordPolicyEnforced | Should Be $true

            # disable the setting for this login
            $result = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random" -PasswordExpirationEnabled:$false
            $result.PasswordExpirationEnabled | Should -Be $false
        }

        It "Ensure both password policy settings can be disabled at the same time" {
            $result = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random" -PasswordPolicyEnforced -PasswordExpirationEnabled
            $result.PasswordExpirationEnabled | Should -Be $true
            $result.PasswordPolicyEnforced | Should Be $true

            $result = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random" -PasswordPolicyEnforced:$false -PasswordExpirationEnabled:$false
            $result.PasswordExpirationEnabled | Should -Be $false
            $result.PasswordPolicyEnforced | Should Be $false
        }

        It -Skip:$SkipLocalTest "Unlock" {
            $results = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random" -PasswordPolicyEnforced -EnableException
            $results.PasswordPolicyEnforced | Should -Be $true

            # simulate a lockout
            $invalidPassword = ConvertTo-SecureString -String 'invalid' -AsPlainText -Force
            $invalidSqlCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "testlogin1_$random", $invalidPassword

            # exceed the lockout count
            for (($i = 0); $i -le 4; $i++) {
                try {
                    Connect-DbaInstance -SqlInstance $TestConfig.instance2 -SqlCredential $invalidSqlCredential
                } catch {
                    Write-Message -Level Warning -Message "invalid login credentials used on purpose to lock out account"
                    Start-Sleep -s 5
                }
            }

            $results = Get-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random"
            $results.IsLocked | Should -Be $true

            # this will generate a warning since neither the password or the -force param is specified
            $results = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random" -Unlock
            $results | Should -BeNullOrEmpty

            # this will use the workaround solution to turn off/on the check_policy
            $results = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random" -Unlock -Force
            $results.IsLocked | Should -Be $false

            # exceed the lockout count again
            for (($i = 0); $i -le 4; $i++) {
                try {
                    Connect-DbaInstance -SqlInstance $TestConfig.instance2 -SqlCredential $invalidSqlCredential
                } catch {
                    Write-Message -Level Warning -Message "invalid login credentials used on purpose to lock out account"
                    Start-Sleep -s 5
                }
            }

            # unlock by resetting the password
            $results = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random" -Unlock -SecurePassword $password1
            $results.IsLocked | Should -Be $false
        }

        It "PasswordMustChange" {
            # password is required
            $changeResult = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random" -PasswordMustChange -WarningAction SilentlyContinue -WarningVariable WarnVar
            $WarnVar | Should -Match "You must specify a password when using the -PasswordMustChange parameter"
            $changeResult | Should -BeNullOrEmpty

            # ensure the policy settings are off
            $result = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random" -PasswordPolicyEnforced:$false -PasswordExpirationEnabled:$false
            $result.PasswordExpirationEnabled | Should -Be $false
            $result.PasswordPolicyEnforced | Should Be $false

            # set the policy options separately for testlogin2
            $changeResult = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin2_$random" -PasswordPolicyEnforced -PasswordExpirationEnabled
            $changeResult.PasswordPolicyEnforced | Should Be $true
            $changeResult.PasswordExpirationEnabled | Should Be $true

            # check_policy and check_expiration must be set on the login
            $changeResult = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random", "testlogin2_$random" -PasswordMustChange -Password $password1 -WarningAction SilentlyContinue -WarningVariable WarnVar
            $WarnVar | Should -Match "Unable to change the password and set the must_change option for \[testlogin1_$random\] because check_policy = False and check_expiration = False"
            $changeResult.Count | Should -Be 1
            $changeResult.Name | Should -Be "testlogin2_$random"

            $changeResult = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin1_$random" -PasswordMustChange -Password $password1 -PasswordPolicyEnforced -PasswordExpirationEnabled
            $changeResult.MustChangePassword | Should -Be $true
            $changeResult.PasswordChanged | Should -Be $true
            $changeResult.PasswordPolicyEnforced | Should Be $true
            $changeResult.PasswordExpirationEnabled | Should Be $true

            # now change the password and set the must_change
            $changeResult = Set-DbaLogin -SqlInstance $TestConfig.instance2 -Login "testlogin2_$random" -PasswordMustChange -Password $password1
            $changeResult.MustChangePassword | Should -Be $true
            $changeResult.PasswordChanged | Should -Be $true

            # get a listing of the logins that must change their password
            $result = Get-DbaLogin -SqlInstance $TestConfig.instance2 -MustChangePassword
            $result.Name | Should -Contain "testlogin1_$random"
            $result.Name | Should -Contain "testlogin2_$random"
        }
    }
}