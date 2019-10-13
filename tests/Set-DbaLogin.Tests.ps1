$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('WhatIf', 'Confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Login', 'SecurePassword', 'DefaultDatabase', 'Unlock', 'MustChange', 'NewName', 'Disable', 'Enable', 'DenyLogin', 'GrantLogin', 'PasswordPolicyEnforced', 'AddRole', 'RemoveRole', 'InputObject', 'EnableException'
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
    Context "Change login" {
        BeforeAll {
            # Create the new password
            $password1 = ConvertTo-SecureString -String "password1" -AsPlainText -Force
            $password2 = ConvertTo-SecureString -String "password2" -AsPlainText -Force

            # Create the login
            New-DbaLogin -SqlInstance $script:instance2 -Login testlogin -Password $password1
        }

        It "Does test login exist" {
            $logins = Get-DbaLogin -SqlInstance $script:instance2 | Where-Object { $_.Name -eq "testlogin" } | Select-Object Name
            $logins.Name | Should -Be "testlogin"
        }

        It "Verifies -NewName doesn't already exist when renaming a login" {
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login 'testLogin' -NewName 'sa' -EnableException

            $result.Notes | Should -Be 'New login name already exists'
        }

        It 'Change the password from a SecureString' {
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login testlogin -Password $password2

            $result.PasswordChanged | Should -Be $true
        }

        It 'Changes the password from a PSCredential' {
            $cred = New-Object System.Management.Automation.PSCredential ('testLogin', $password2)
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login 'testLogin' -Password $cred

            $result.PasswordChanged | Should -Be $true
        }

        It "Change the password from piped Login" {
            $login = Get-DbaLogin -Sqlinstance $script:instance2 -Login testLogin

            $result = $login | Set-DbaLogin -Password $password2
            $result.PasswordChanged | Should -Be $true
        }

        It "Change the password from InputObject" {
            $login = Get-DbaLogin -Sqlinstance $script:instance2 -Login testLogin

            $result = Set-DbaLogin -InputObject $login -Password $password2
            $result.PasswordChanged | Should -Be $true
        }

        It "Disable the login" {
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login testlogin -Disable
            $result.IsDisabled | Should -Be $true
        }

        It "Enable the login" {
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login testlogin -Enable
            $result.IsDisabled | Should -Be $false
        }

        It "Deny access to login" {
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login testlogin -DenyLogin

            $result.DenyLogin | Should -Be $true
        }

        It "Grant access to login" {
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login testlogin -GrantLogin

            $result.DenyLogin | Should -Be $false
        }

        It "Enforces password policy on login" {
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login testlogin -PasswordPolicyEnforced

            $result.PasswordPolicyEnforced | Should Be $true
        }

        It "Catches errors when password can't be changed" {
            # enforce password policy
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login 'testLogin' -PasswordPolicyEnforced -EnableException
            $result.PasswordPolicyEnforced | Should -Be $true

            # violate policy
            $invalidPassword = ConvertTo-SecureString -String "password1" -AsPlainText -Force

            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login 'testLogin' -Password $invalidPassword -WarningAction 'SilentlyContinue'
            $result | Should -Be $null

            { Set-DbaLogin -SqlInstance $script:instance2 -Login 'testLogin' -Password $invalidPassword -EnableException } | Should -Throw
        }

        It "Disables enforcing password policy on login" {
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login testlogin -PasswordPolicyEnforced:$false

            $result.PasswordPolicyEnforced | Should Be $false
        }

        It "Add roles to login" {
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login testlogin -AddRole serveradmin, processadmin

            $result.ServerRole | Should -Be "processadmin, serveradmin"
        }

        It "Remove roles from login" {
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login testlogin -RemoveRole serveradmin

            $result.ServerRole | Should -Be "processadmin"
        }

        AfterAll {
            Remove-DbaLogin -SqlInstance $script:instance2 -Login testlogin,testlogin1,testlogin2 -Confirm:$false -Force
        }
    }
    Context "Can handle multiple Logins" {
        BeforeAll {
            # Create the new password
            $password = ConvertTo-SecureString -String "password1" -AsPlainText -Force

            # Create two logins
            New-DbaLogin -SqlInstance $script:instance2 -Login testlogin1, testlogin2 -Password $password
        }
        $results = Set-DbaLogin -SqlInstance $script:instance2 -Login testlogin1, testlogin2 -DenyLogin

        It "Results include multiple objects" {
            $results.Count | Should -Be 2
        }
        if ($results.Count -eq 2) {
            It "Applies change to multiple logins" {
                foreach ($r in $results) {
                    $r.DenyLogin | Should -Be $true
                }
            }
        }

        AfterAll {
            Remove-DbaLogin -SqlInstance $script:instance2 -Login testlogin1,testlogin2 -Confirm:$false -Force
        }
    }
}