param($ModuleName = 'dbatools')

Describe "Remove-DbaServerRoleMember" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $login1 = "dbatoolsci_login1_$(Get-Random)"
        $login2 = "dbatoolsci_login2_$(Get-Random)"
        $customServerRole = "dbatoolsci_customrole_$(Get-Random)"
        $fixedServerRoles = 'dbcreator','processadmin'
        $null = New-DbaLogin -SqlInstance $global:instance2 -Login $login1 -Password ('Password1234!' | ConvertTo-SecureString -asPlainText -Force)
        $null = New-DbaLogin -SqlInstance $global:instance2 -Login $login2 -Password ('Password1234!' | ConvertTo-SecureString -asPlainText -Force)
        $null = New-DbaServerRole -SqlInstance $global:instance2 -ServerRole $customServerRole -Owner sa
        Add-DbaServerRoleMember -SqlInstance $server -ServerRole $fixedServerRoles[0] -Login $login1, $login2 -Confirm:$false
    }

    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $null = Remove-DbaLogin -SqlInstance $global:instance2 -Login $login1, $login2 -Confirm:$false
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaServerRoleMember
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "ServerRole",
            "Login",
            "Role",
            "InputObject",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Functionality" {
        It 'Removes Login from Role' {
            Remove-DbaServerRoleMember -SqlInstance $global:instance2 -ServerRole $fixedServerRoles[0] -Login $login1 -Confirm:$false
            $roleAfter = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles[0]

            $roleAfter.Role | Should -Be $fixedServerRoles[0]
            $roleAfter.EnumMemberNames().Contains($login1) | Should -Be $false
            $roleAfter.EnumMemberNames().Contains($login2) | Should -Be $true
        }

        It 'Removes Login from Multiple Roles' {
            $serverRoles = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles
            Remove-DbaServerRoleMember -SqlInstance $global:instance2 -ServerRole $serverRoles -Login $login1 -Confirm:$false

            $roleDBAfter = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles
            $roleDBAfter.Count | Should -Be $serverRoles.Count
            $roleDBAfter.Login -contains $login1 | Should -Be $false
            $roleDBAfter.Login -contains $login2 | Should -Be $true
        }

        It 'Removes Custom Server-Level Role Membership' {
            Remove-DbaServerRoleMember -SqlInstance $global:instance2 -ServerRole $customServerRole -Role $fixedServerRoles[-1] -Confirm:$false
            $roleAfter = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles[-1]

            $roleAfter.Role | Should -Be $fixedServerRoles[-1]
            $roleAfter.EnumMemberNames().Contains($customServerRole) | Should -Be $false
        }

        It 'Removes Login from Roles via piped input from Get-DbaServerRole' {
            $serverRole = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles[0]
            $serverRole | Remove-DbaServerRoleMember -Login $login2 -Confirm:$false

            $roleAfter = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles[0]
            $roleAfter.EnumMemberNames().Contains($login2) | Should -Be $false
        }
    }
}
