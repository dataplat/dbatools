$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('WhatIf', 'Confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Login', 'SecurePassword', 'DefaultDatabase', 'Unlock', 'MustChange', 'NewName', 'Disable', 'Enable', 'DenyLogin', 'GrantLogin', 'PasswordPolicyEnforced', 'PasswordExpirationEnabled', 'AddRole', 'RemoveRole', 'InputObject', 'EnableException'
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
}

Describe "$CommandName Integration Tests" -Tag 'IntegrationTests' {
    Context "verify command functions" {
        BeforeAll {
            $random = Get-Random

            # Create the new password
            $password1 = ConvertTo-SecureString -String "password1A@" -AsPlainText -Force
            $password2 = ConvertTo-SecureString -String "password2A@" -AsPlainText -Force

            # Create the login
            New-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random", "testlogin2_$random" -Password $password1

            New-DbaDatabase -SqlInstance $script:instance2 -Name "testdb1_$random" -Confirm:$false
        }

        AfterAll {
            Remove-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random", "testlogin2_$random" -Confirm:$false -Force
            Remove-DbaDatabase -SqlInstance $script:instance2 -Database "testdb1_$random" -Confirm:$false
        }

        It "Does test login exist" {
            $logins = Get-DbaLogin -SqlInstance $script:instance2 | Where-Object { $_.Name -eq "testlogin1_$random" } | Select-Object Name
            $logins.Name | Should -Be "testlogin1_$random"
        }

        It "Verifies -NewName doesn't already exist when renaming a login" {
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -NewName 'sa' -EnableException

            $result.Notes | Should -Be 'New login name already exists'
        }

        It 'Change the password from a SecureString' {
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -Password $password2

            $result.PasswordChanged | Should -Be $true
        }

        It 'Changes the password from a PSCredential' {
            $cred = New-Object System.Management.Automation.PSCredential ("testlogin1_$random", $password2)
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -Password $cred

            $result.PasswordChanged | Should -Be $true
        }

        It "Change the password from piped Login" {
            $login = Get-DbaLogin -Sqlinstance $script:instance2 -Login "testlogin1_$random"

            $result = $login | Set-DbaLogin -Password $password2
            $result.PasswordChanged | Should -Be $true
        }

        It "Change the password from InputObject" {
            $login = Get-DbaLogin -Sqlinstance $script:instance2 -Login "testlogin1_$random"

            $result = Set-DbaLogin -InputObject $login -Password $password2
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

            $result.PasswordPolicyEnforced | Should Be $true
        }

        It "Catches errors when password can't be changed" {
            # enforce password policy
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -PasswordPolicyEnforced -EnableException
            $result.PasswordPolicyEnforced | Should -Be $true

            # violate policy
            $invalidPassword = ConvertTo-SecureString -String "password1" -AsPlainText -Force

            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -Password $invalidPassword -WarningAction 'SilentlyContinue'
            $result | Should -Be $null

            { Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -Password $invalidPassword -EnableException } | Should -Throw
        }

        It "Disables enforcing password policy on login" {
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -PasswordPolicyEnforced:$false

            $result.PasswordPolicyEnforced | Should Be $false
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

        It "Unlock" {
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -PasswordPolicyEnforced -EnableException
            $result.PasswordPolicyEnforced | Should -Be $true

            # simulate a lockout
            $invalidPassword = ConvertTo-SecureString -String 'invalid' -AsPlainText -Force
            $invalidSqlCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "testlogin1_$random", $invalidPassword

            # exceed the lockout count
            for (($i = 0); $i -le 5; $i++) {
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

            $results = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -Unlock -SecurePassword $password1
            $results.IsLocked | Should -Be $false
        }

        It "MustChange" {
            $changeResult = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -MustChange
            $changeResult | Should -BeNullOrEmpty

            $changeResult = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -MustChange -Password $password1
            $changeResult | Should -BeNullOrEmpty

            $changeResult = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -MustChange -Password $password1 -PasswordPolicyEnforced -PasswordExpirationEnabled
            $changeResult.MustChangePassword | Should -Be $true

            $result = Get-DbaLogin -SqlInstance $script:instance2 -MustChangePassword
            $result.Name | Should -Contain "testlogin1_$random"
        }

        It "PasswordExpirationEnabled" {
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login "testlogin1_$random" -PasswordExpirationEnabled
            $result.PasswordExpirationEnabled | Should Be $true
        }
    }
}