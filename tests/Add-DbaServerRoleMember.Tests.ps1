#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Add-DbaServerRoleMember",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "ServerRole",
                "Login",
                "Role",
                "InputObject",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $login1 = "dbatoolsci_login1_$(Get-Random)"
        $login2 = "dbatoolsci_login2_$(Get-Random)"
        $customServerRole = "dbatoolsci_customrole_$(Get-Random)"
        $fixedServerRoles = @(
            "dbcreator",
            "processadmin"
        )
        $splatNewLogin = @{
            SqlInstance = $TestConfig.instance2
            Password    = ("Password1234!" | ConvertTo-SecureString -asPlainText -Force)
        }
        $null = New-DbaLogin @splatNewLogin -Login $login1
        $null = New-DbaLogin @splatNewLogin -Login $login2
        $null = New-DbaServerRole -SqlInstance $TestConfig.instance2 -ServerRole $customServerRole -Owner sa
    }
    AfterAll {
        $splatRemoveLogin = @{
            SqlInstance = $TestConfig.instance2
            Login       = $login1, $login2
            Confirm     = $false
        }
        $null = Remove-DbaLogin @splatRemoveLogin
    }

    Context "Functionality" {
        It "Adds Login to Role" {
            $splatAddRole = @{
                SqlInstance = $TestConfig.instance2
                ServerRole  = $fixedServerRoles[0]
                Login       = $login1
                Confirm     = $false
            }
            Add-DbaServerRoleMember @splatAddRole
            $roleAfter = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles[0]

            $roleAfter.Role | Should -Be $fixedServerRoles[0]
            $roleAfter.EnumMemberNames() | Should -Contain $login1
        }

        It "Adds Login to Multiple Roles" {
            $serverRoles = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles
            $splatAddRoles = @{
                SqlInstance = $TestConfig.instance2
                ServerRole  = $serverRoles
                Login       = $login1
                Confirm     = $false
            }
            Add-DbaServerRoleMember @splatAddRoles

            $roleDBAfter = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles
            $roleDBAfter.Count | Should -Be $serverRoles.Count
            $roleDBAfter.Login | Should -Contain $login1
        }

        It "Adds Customer Server-Level Role Membership" {
            $splatAddCustomRole = @{
                SqlInstance = $TestConfig.instance2
                ServerRole  = $customServerRole
                Role        = $fixedServerRoles[-1]
                Confirm     = $false
            }
            Add-DbaServerRoleMember @splatAddCustomRole
            $roleAfter = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles[-1]

            $roleAfter.Role | Should -Be $fixedServerRoles[-1]
            $roleAfter.EnumMemberNames() | Should -Contain $customServerRole
        }

        It "Adds Login to Roles via piped input from Get-DbaServerRole" {
            $serverRole = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles[0]
            $serverRole | Add-DbaServerRoleMember -Login $login2 -Confirm:$false

            $roleAfter = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles[0]
            $roleAfter.EnumMemberNames() | Should -Contain $login2
        }
    }
}