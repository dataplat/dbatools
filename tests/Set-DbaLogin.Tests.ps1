$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 14
        [object[]]$params = (Get-ChildItem function:\Set-DbaLogin).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Login', 'Password', 'Unlock', 'MustChange', 'NewName', 'Disable', 'Enable', 'DenyLogin', 'GrantLogin', 'AddRole', 'RemoveRole', 'EnableException'
        It "Contains our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
    }
}

Describe "$CommandName Unittests" -Tag 'UnitTests' {
    Context "Change login" {

        BeforeAll {
            # Create the new password
            $password1 = ConvertTo-SecureString -String "password1" -AsPlainText -Force
            $password2 = ConvertTo-SecureString -String "password2" -AsPlainText -Force

            # Create the login
            New-DbaLogin -SqlInstance $script:instance2 -Login testlogin -Password $password1
        }

        It "Does test login exist" {
            $logins = Get-DbaLogin -SqlInstance $script:instance2 | Where-Object {$_.Name -eq "testlogin"} | Select-Object Name
            $logins.Name | Should -Be "testlogin"
        }

        It "Change the password"{
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login testlogin -Password $password2

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

        It "Disables enforcing password policy on login" {
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login testlogin -PasswordPolicyEnforced:$false

            $result.PasswordPolicyEnforced | Should Be $false
        }

        It "Add roles to login" {
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login testlogin -AddRole serveradmin, processadmin

            $result.ServerRole | Should -Be "processadmin,serveradmin"
        }

        It "Remove roles from login" {
            $result = Set-DbaLogin -SqlInstance $script:instance2 -Login testlogin -RemoveRole serveradmin

            $result.ServerRole | Should -Be "processadmin"
        }

        AfterAll {
            Remove-DbaLogin -SqlInstance $script:instance2 -Login testlogin -Confirm:$false
        }
    }
}