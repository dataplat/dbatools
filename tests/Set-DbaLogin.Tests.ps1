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
    # TODO: Fix later
    Context -Skip "???" {
        BeforeAll {
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

        # TODO: The 'locked' test makes assumptions the password policy configuration is enabled for the Windows OS.
        It -Skip "Unlock" {
            $results = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -PasswordPolicyEnforced -EnableException
            $results.PasswordPolicyEnforced | Should -Be $true

            # simulate a lockout
            $invalidPassword = ConvertTo-SecureString -String 'invalid' -AsPlainText -Force
            $invalidSqlCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "testlogin1_$random", $invalidPassword

            # exceed the lockout count
            for (($i = 0); $i -le 4; $i++) {
                try {
                    Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -SqlCredential $invalidSqlCredential
                } catch {
                    Write-Message -Level Warning -Message "invalid login credentials used on purpose to lock out account"
                    Start-Sleep -s 5
                }
            }

            $results = Get-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random"
            $results.IsLocked | Should -Be $true

            # this will generate a warning since neither the password or the -force param is specified
            $results = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -Unlock
            $results | Should -BeNullOrEmpty

            # this will use the workaround solution to turn off/on the check_policy
            $results = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -Unlock -Force
            $results.IsLocked | Should -Be $false

            # exceed the lockout count again
            for (($i = 0); $i -le 4; $i++) {
                try {
                    Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -SqlCredential $invalidSqlCredential
                } catch {
                    Write-Message -Level Warning -Message "invalid login credentials used on purpose to lock out account"
                    Start-Sleep -s 5
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

    Context "Output validation" {
        BeforeAll {
            $outputRandom = Get-Random
            $outputPassword = ConvertTo-SecureString -String "outputTestA1@" -AsPlainText -Force
            New-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "dbatoolsci_outputlogin_$outputRandom" -Password $outputPassword
            $result = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "dbatoolsci_outputlogin_$outputRandom" -Password $outputPassword
        }

        AfterAll {
            Remove-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "dbatoolsci_outputlogin_$outputRandom" -Force -ErrorAction SilentlyContinue
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Login"
        }

        It "Has the expected default display properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Name",
                "DenyLogin",
                "IsDisabled",
                "IsLocked",
                "PasswordPolicyEnforced",
                "PasswordExpirationEnabled",
                "MustChangePassword",
                "PasswordChanged",
                "ServerRole",
                "Notes"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has the expected NoteProperties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].PSObject.Properties["ComputerName"] | Should -Not -BeNullOrEmpty
            $result[0].PSObject.Properties["InstanceName"] | Should -Not -BeNullOrEmpty
            $result[0].PSObject.Properties["SqlInstance"] | Should -Not -BeNullOrEmpty
            $result[0].PSObject.Properties["PasswordChanged"] | Should -Not -BeNullOrEmpty
            $result[0].PSObject.Properties["ServerRole"] | Should -Not -BeNullOrEmpty
        }
    }
}