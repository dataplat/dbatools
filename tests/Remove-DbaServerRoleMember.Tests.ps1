#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaServerRoleMember",
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
                "ServerRole",
                "Login",
                "Role",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $login1 = "dbatoolsci_login1_$(Get-Random)"
        $login2 = "dbatoolsci_login2_$(Get-Random)"
        $customServerRole = "dbatoolsci_customrole_$(Get-Random)"
        $fixedServerRoles = "dbcreator", "processadmin"

        $splatPassword = @{
            String      = "Password1234!"
            AsPlainText = $true
            Force       = $true
        }
        $password = ConvertTo-SecureString @splatPassword

        $null = New-DbaLogin -SqlInstance $TestConfig.instance2 -Login $login1 -Password $password
        $null = New-DbaLogin -SqlInstance $TestConfig.instance2 -Login $login2 -Password $password
        $null = New-DbaServerRole -SqlInstance $TestConfig.instance2 -ServerRole $customServerRole -Owner sa
        Add-DbaServerRoleMember -SqlInstance $server -ServerRole $fixedServerRoles[0] -Login $login1, $login2 -Confirm:$false

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login $login1, $login2 -Confirm:$false
        $null = Remove-DbaServerRole -SqlInstance $TestConfig.instance2 -ServerRole $customServerRole -Confirm:$false

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Functionality" {
        It "Removes Login from Role" {
            Remove-DbaServerRoleMember -SqlInstance $TestConfig.instance2 -ServerRole $fixedServerRoles[0] -Login $login1 -Confirm:$false
            $roleAfter = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles[0]

            $roleAfter.Role | Should -Be $fixedServerRoles[0]
            $roleAfter.EnumMemberNames().Contains($login1) | Should -Be $false
            $roleAfter.EnumMemberNames().Contains($login2) | Should -Be $true
        }

        It "Removes Login from Multiple Roles" {
            $serverRoles = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles
            Remove-DbaServerRoleMember -SqlInstance $TestConfig.instance2 -ServerRole $serverRoles -Login $login1 -Confirm:$false

            $roleDBAfter = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles
            $roleDBAfter.Count | Should -Be $serverRoles.Count
            $roleDBAfter.Login -contains $login1 | Should -Be $false
            $roleDBAfter.Login -contains $login2 | Should -Be $true
        }

        It "Removes Custom Server-Level Role Membership" {
            Remove-DbaServerRoleMember -SqlInstance $TestConfig.instance2 -ServerRole $customServerRole -Role $fixedServerRoles[-1] -Confirm:$false
            $roleAfter = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles[-1]

            $roleAfter.Role | Should -Be $fixedServerRoles[-1]
            $roleAfter.EnumMemberNames().Contains($customServerRole) | Should -Be $false
        }

        It "Removes Login from Roles via piped input from Get-DbaServerRole" {
            $serverRole = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles[0]
            $serverRole | Remove-DbaServerRoleMember -Login $login2 -Confirm:$false

            $roleAfter = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles[0]
            $roleAfter.EnumMemberNames().Contains($login2) | Should -Be $false
        }
    }
}