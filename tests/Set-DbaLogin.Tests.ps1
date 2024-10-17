param($ModuleName = 'dbatools')

Describe "Set-DbaLogin" {
    BeforeAll {
        $commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $random = Get-Random
        $password1 = ConvertTo-SecureString -String "password1A@" -AsPlainText -Force
        $password2 = ConvertTo-SecureString -String "password2A@" -AsPlainText -Force

        # Create the login
        New-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random", "testlogin2_$random" -Password $password1

        New-DbaDatabase -SqlInstance $script:instance2 -Name "testdb1_$random" -Confirm:$false

        $SkipLocalTest = $true # Change to $false to run the local-only tests on a local instance
    }

    AfterAll {
        Remove-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random", "testlogin2_$random" -Confirm:$false -Force
        Remove-DbaDatabase -SqlInstance $script:instance2 -Database "testdb1_$random" -Confirm:$false
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command $CommandName
            $systemRoles = @('bulkadmin', 'dbcreator', 'diskadmin', 'processadmin', 'public', 'securityadmin', 'serveradmin', 'setupadmin', 'sysadmin')
        }

        It "Should have the correct parameters" {
            $command | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
            $command | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
            $command | Should -HaveParameter Login -Type String[] -Not -Mandatory
            $command | Should -HaveParameter SecurePassword -Type Object -Not -Mandatory
            $command | Should -HaveParameter DefaultDatabase -Type String -Not -Mandatory
            $command | Should -HaveParameter Unlock -Type SwitchParameter -Not -Mandatory
            $command | Should -HaveParameter PasswordMustChange -Type SwitchParameter -Not -Mandatory
            $command | Should -HaveParameter NewName -Type String -Not -Mandatory
            $command | Should -HaveParameter Disable -Type SwitchParameter -Not -Mandatory
            $command | Should -HaveParameter Enable -Type SwitchParameter -Not -Mandatory
            $command | Should -HaveParameter DenyLogin -Type SwitchParameter -Not -Mandatory
            $command | Should -HaveParameter GrantLogin -Type SwitchParameter -Not -Mandatory
            $command | Should -HaveParameter PasswordPolicyEnforced -Type SwitchParameter -Not -Mandatory
            $command | Should -HaveParameter PasswordExpirationEnabled -Type SwitchParameter -Not -Mandatory
            $command | Should -HaveParameter AddRole -Type String[] -Not -Mandatory
            $command | Should -HaveParameter RemoveRole -Type String[] -Not -Mandatory
            $command | Should -HaveParameter InputObject -Type Login[] -Not -Mandatory
            $command | Should -HaveParameter Force -Type SwitchParameter -Not -Mandatory
            $command | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
        }

        It "Validates -AddRole contains <_>" -ForEach $systemRoles {
            $command.Parameters['AddRole'].Attributes.ValidValues | Should -Contain $_
        }

        It "Validates -RemoveRole contains <_>" -ForEach $systemRoles {
            $command.Parameters['RemoveRole'].Attributes.ValidValues | Should -Contain $_
        }
    }

    Context "Validate input" {
        It "Validates -Login and -NewName aren't the same" {
            { Set-DbaLogin -SqlInstance $script:instance2 -Login testlogin -NewName testLogin -EnableException } | Should -Throw 'Login name is the same as the value in -NewName'
        }

        It "Validates -Enable and -Disable aren't used together" {
            { Set-DbaLogin -SqlInstance $script:instance2 -Login testlogin -Enable -Disable -EnableException } | Should -Throw 'You cannot use both -Enable and -Disable together'
        }

        It "Validates -GrantLogin and -DenyLogin aren't used together" {
            { Set-DbaLogin -SqlInstance $script:instance2 -Login testlogin -GrantLogin -DenyLogin -EnableException } | Should -Throw 'You cannot use both -GrantLogin and -DenyLogin together'
        }

        It "Validates -Login is required when using -SqlInstance" {
            { Set-DbaLogin -SqlInstance $script:instance2 -EnableException } | Should -Throw 'You must specify a Login when using SqlInstance'
        }

        It "Validates -Password is a SecureString or PSCredential" {
            { Set-DbaLogin -SqlInstance $script:instance2 -Login 'testLogin' -Password 'password' -EnableException } | Should -Throw 'Password must be a PSCredential or SecureString'
        }
    }

    Context "Verify command functions" {
        It "Does test login exist" {
            $logins = Get-DbaLogin -SqlInstance $script:instance2 | Where-Object { $_.Name -eq "testlogin1_$random" } | Select-Object Name
            $logins.Name | Should -Be "testlogin1_$random"
        }

        It "Verifies -NewName doesn't already exist when renaming a login" {
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -NewName 'sa' -EnableException
            $result.Notes | Should -Be 'New login name already exists'
        }

        It 'Change the password from a SecureString' {
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -SecurePassword $password2
            $result.PasswordChanged | Should -Be $true
        }

        It 'Changes the password from a PSCredential' {
            $cred = New-Object System.Management.Automation.PSCredential ("testlogin1_$random", $password2)
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -SecurePassword $cred
            $result.PasswordChanged | Should -Be $true
        }

        It "Change the password from piped Login" {
            $login = Get-DbaLogin -Sqlinstance $script:instance2 -Login "testlogin1_$random"
            $result = $login | Set-DbaLogin -SecurePassword $password2
            $result.PasswordChanged | Should -Be $true
        }

        It "Change the password from InputObject" {
            $login = Get-DbaLogin -Sqlinstance $script:instance2 -Login "testlogin1_$random"
            $result = Set-DbaLogin -InputObject $login -SecurePassword $password2
            $result.PasswordChanged | Should -Be $true
        }

        It "Disable the login" {
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -Disable
            $result.IsDisabled | Should -Be $true
        }

        It "Enable the login" {
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -Enable
            $result.IsDisabled | Should -Be $false
        }

        It "Deny access to login" {
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -DenyLogin
            $result.DenyLogin | Should -Be $true
        }

        It "Grant access to login" {
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -GrantLogin
            $result.DenyLogin | Should -Be $false
        }

        It "Enforces password policy on login" {
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -PasswordPolicyEnforced
            $result.PasswordPolicyEnforced | Should -Be $true
        }

        It "Catches errors when password can't be changed" {
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -PasswordPolicyEnforced -EnableException
            $result.PasswordPolicyEnforced | Should -Be $true

            $invalidPassword = ConvertTo-SecureString -String "password1" -AsPlainText -Force

            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -SecurePassword $invalidPassword -WarningAction 'SilentlyContinue'
            $result | Should -Be $null

            { Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -SecurePassword $invalidPassword -EnableException } | Should -Throw
        }

        It "Disables enforcing password policy on login" {
            $result = Get-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random"
            $result.PasswordPolicyEnforced | Should -Be $true

            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -PasswordPolicyEnforced:$false
            $result.PasswordPolicyEnforced | Should -Be $false
        }

        It "Add roles to login" {
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -AddRole serveradmin, processadmin
            $result.ServerRole | Should -Be "processadmin, serveradmin"
        }

        It "Remove roles from login" {
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -RemoveRole serveradmin
            $result.ServerRole | Should -Be "processadmin"
        }

        It "Results include multiple changed objects" {
            $results = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random", "testlogin2_$random" -DenyLogin
            $results.Count | Should -Be 2
            foreach ($r in $results) {
                $r.DenyLogin | Should -Be $true
            }
        }

        It "DefaultDatabase" {
            $results = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -DefaultDatabase "testdb1_$random"
            $results.DefaultDatabase | Should -Be "testdb1_$random"
        }

        It "PasswordExpirationEnabled" {
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin2_$random" -PasswordPolicyEnforced
            $result.PasswordPolicyEnforced | Should -Be $true

            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random", "testlogin2_$random" -PasswordExpirationEnabled -ErrorVariable error
            $result.Count | Should -Be 1
            $result.Name | Should -Be "testlogin2_$random"
            $result.PasswordExpirationEnabled | Should -Be $true
            $error.Exception | Should -Match "Couldn't set check_expiration = ON because check_policy = OFF for \[testlogin1_$random\]"

            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -PasswordPolicyEnforced -PasswordExpirationEnabled
            $result.PasswordExpirationEnabled | Should -Be $true
            $result.PasswordPolicyEnforced | Should -Be $true

            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -PasswordExpirationEnabled:$false
            $result.PasswordExpirationEnabled | Should -Be $false
        }

        It "Ensure both password policy settings can be disabled at the same time" {
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -PasswordPolicyEnforced -PasswordExpirationEnabled
            $result.PasswordExpirationEnabled | Should -Be $true
            $result.PasswordPolicyEnforced | Should -Be $true

            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -PasswordPolicyEnforced:$false -PasswordExpirationEnabled:$false
            $result.PasswordExpirationEnabled | Should -Be $false
            $result.PasswordPolicyEnforced | Should -Be $false
        }

        It "Unlock" -Skip:$SkipLocalTest {
            $results = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -PasswordPolicyEnforced -EnableException
            $results.PasswordPolicyEnforced | Should -Be $true

            $invalidPassword = ConvertTo-SecureString -String 'invalid' -AsPlainText -Force
            $invalidSqlCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "testlogin1_$random", $invalidPassword

            for (($i = 0); $i -le 4; $i++) {
                try {
                    Connect-DbaInstance -SqlInstance $script:instance2 -SqlCredential $invalidSqlCredential
                } catch {
                    Write-Message -Level Warning -Message "invalid login credentials used on purpose to lock out account"
                    Start-Sleep -s 5
                }
            }

            $results = Get-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random"
            $results.IsLocked | Should -Be $true

            $results = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -Unlock
            $results | Should -BeNullOrEmpty

            $results = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -Unlock -Force
            $results.IsLocked | Should -Be $false

            for (($i = 0); $i -le 4; $i++) {
                try {
                    Connect-DbaInstance -SqlInstance $script:instance2 -SqlCredential $invalidSqlCredential
                } catch {
                    Write-Message -Level Warning -Message "invalid login credentials used on purpose to lock out account"
                    Start-Sleep -s 5
                }
            }

            $results = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -Unlock -SecurePassword $password1
            $results.IsLocked | Should -Be $false
        }

        It "PasswordMustChange" {
            $changeResult = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -PasswordMustChange -ErrorVariable error
            $changeResult | Should -BeNullOrEmpty
            $error.Exception | Should -Match "You must specify a password when using the -PasswordMustChange parameter"

            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -PasswordPolicyEnforced:$false -PasswordExpirationEnabled:$false
            $result.PasswordExpirationEnabled | Should -Be $false
            $result.PasswordPolicyEnforced | Should -Be $false

            $changeResult = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin2_$random" -PasswordPolicyEnforced -PasswordExpirationEnabled
            $changeResult.PasswordPolicyEnforced | Should -Be $true
            $changeResult.PasswordExpirationEnabled | Should -Be $true

            $changeResult = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random", "testlogin2_$random" -PasswordMustChange -SecurePassword $password1 -ErrorVariable error
            $changeResult.Count | Should -Be 1
            $changeResult.Name | Should -Be "testlogin2_$random"
            $error.Exception | Should -Match "Unable to change the password and set the must_change option for \[testlogin1_$random\] because check_policy = False and check_expiration = False"

            $changeResult = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -PasswordMustChange -SecurePassword $password1 -PasswordPolicyEnforced -PasswordExpirationEnabled
            $changeResult.MustChangePassword | Should -Be $true
            $changeResult.PasswordChanged | Should -Be $true
            $changeResult.PasswordPolicyEnforced | Should -Be $true
            $changeResult.PasswordExpirationEnabled | Should -Be $true

            $changeResult = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin2_$random" -PasswordMustChange -SecurePassword $password1
            $changeResult.MustChangePassword | Should -Be $true
            $changeResult.PasswordChanged | Should -Be $true

            $result = Get-DbaLogin -SqlInstance $script:instance2 -MustChangePassword
            $result.Name | Should -Contain "testlogin1_$random"
            $result.Name | Should -Contain "testlogin2_$random"
        }
    }
}
