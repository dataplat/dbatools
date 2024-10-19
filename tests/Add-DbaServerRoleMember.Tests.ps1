param($ModuleName = 'dbatools')

Describe "Add-DbaServerRoleMember" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Add-DbaServerRoleMember
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have ServerRole as a parameter" {
            $CommandUnderTest | Should -HaveParameter ServerRole
        }
        It "Should have Login as a parameter" {
            $CommandUnderTest | Should -HaveParameter Login
        }
        It "Should have Role as a parameter" {
            $CommandUnderTest | Should -HaveParameter Role
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command usage" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $login1 = "dbatoolsci_login1_$(Get-Random)"
            $login2 = "dbatoolsci_login2_$(Get-Random)"
            $customServerRole = "dbatoolsci_customrole_$(Get-Random)"
            $fixedServerRoles = 'dbcreator','processadmin'
            $null = New-DbaLogin -SqlInstance $global:instance2 -Login $login1 -Password ('Password1234!' | ConvertTo-SecureString -asPlainText -Force)
            $null = New-DbaLogin -SqlInstance $global:instance2 -Login $login2 -Password ('Password1234!' | ConvertTo-SecureString -asPlainText -Force)
            $null = New-DbaServerRole -SqlInstance $global:instance2 -ServerRole $customServerRole -Owner sa
        }

        AfterAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $null = Remove-DbaLogin -SqlInstance $global:instance2 -Login $login1, $login2 -Confirm:$false
        }

        It 'Adds Login to Role' {
            Add-DbaServerRoleMember -SqlInstance $global:instance2 -ServerRole $fixedServerRoles[0] -Login $login1 -Confirm:$false
            $roleAfter = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles[0]

            $roleAfter.Role | Should -Be $fixedServerRoles[0]
            $roleAfter.EnumMemberNames().Contains($login1) | Should -Be $true
        }

        It 'Adds Login to Multiple Roles' {
            $serverRoles = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles
            Add-DbaServerRoleMember -SqlInstance $global:instance2 -ServerRole $serverRoles -Login $login1 -Confirm:$false

            $roleDBAfter = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles
            $roleDBAfter.Count | Should -Be $serverRoles.Count
            $roleDBAfter.Login -contains $login1 | Should -Be $true
        }

        It 'Adds Customer Server-Level Role Membership' {
            Add-DbaServerRoleMember -SqlInstance $global:instance2 -ServerRole $customServerRole -Role $fixedServerRoles[-1] -Confirm:$false
            $roleAfter = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles[-1]

            $roleAfter.Role | Should -Be $fixedServerRoles[-1]
            $roleAfter.EnumMemberNames().Contains($customServerRole) | Should -Be $true
        }

        It 'Adds Login to Roles via piped input from Get-DbaServerRole' {
            $serverRole = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles[0]
            $serverRole | Add-DbaServerRoleMember -Login $login2 -Confirm:$false

            $roleAfter = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles[0]
            $roleAfter.EnumMemberNames().Contains($login2) | Should -Be $true
        }
    }
}
