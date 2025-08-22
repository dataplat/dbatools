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

        $global:server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $global:login1 = "dbatoolsci_login1_$(Get-Random)"
        $global:login2 = "dbatoolsci_login2_$(Get-Random)"
        $global:customServerRole = "dbatoolsci_customrole_$(Get-Random)"
        $global:fixedServerRoles = "dbcreator", "processadmin"

        $splatPassword = @{
            String      = "Password1234!"
            AsPlainText = $true
            Force       = $true
        }
        $password = ConvertTo-SecureString @splatPassword

        $null = New-DbaLogin -SqlInstance $TestConfig.instance2 -Login $global:login1 -Password $password
        $null = New-DbaLogin -SqlInstance $TestConfig.instance2 -Login $global:login2 -Password $password
        $null = New-DbaServerRole -SqlInstance $TestConfig.instance2 -ServerRole $global:customServerRole -Owner sa
        Add-DbaServerRoleMember -SqlInstance $global:server -ServerRole $global:fixedServerRoles[0] -Login $global:login1, $global:login2 -Confirm:$false

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login $global:login1, $global:login2 -Confirm:$false
        $null = Remove-DbaServerRole -SqlInstance $TestConfig.instance2 -ServerRole $global:customServerRole -Confirm:$false

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Functionality" {
        It "Removes Login from Role" {
            Remove-DbaServerRoleMember -SqlInstance $TestConfig.instance2 -ServerRole $global:fixedServerRoles[0] -Login $global:login1 -Confirm:$false
            $roleAfter = Get-DbaServerRole -SqlInstance $global:server -ServerRole $global:fixedServerRoles[0]

            $roleAfter.Role | Should -Be $global:fixedServerRoles[0]
            $roleAfter.EnumMemberNames().Contains($global:login1) | Should -Be $false
            $roleAfter.EnumMemberNames().Contains($global:login2) | Should -Be $true
        }

        It "Removes Login from Multiple Roles" {
            $serverRoles = Get-DbaServerRole -SqlInstance $global:server -ServerRole $global:fixedServerRoles
            Remove-DbaServerRoleMember -SqlInstance $TestConfig.instance2 -ServerRole $serverRoles -Login $global:login1 -Confirm:$false

            $roleDBAfter = Get-DbaServerRole -SqlInstance $global:server -ServerRole $global:fixedServerRoles
            $roleDBAfter.Count | Should -Be $serverRoles.Count
            $roleDBAfter.Login -contains $global:login1 | Should -Be $false
            $roleDBAfter.Login -contains $global:login2 | Should -Be $true
        }

        It "Removes Custom Server-Level Role Membership" {
            Remove-DbaServerRoleMember -SqlInstance $TestConfig.instance2 -ServerRole $global:customServerRole -Role $global:fixedServerRoles[-1] -Confirm:$false
            $roleAfter = Get-DbaServerRole -SqlInstance $global:server -ServerRole $global:fixedServerRoles[-1]

            $roleAfter.Role | Should -Be $global:fixedServerRoles[-1]
            $roleAfter.EnumMemberNames().Contains($global:customServerRole) | Should -Be $false
        }

        It "Removes Login from Roles via piped input from Get-DbaServerRole" {
            $serverRole = Get-DbaServerRole -SqlInstance $global:server -ServerRole $global:fixedServerRoles[0]
            $serverRole | Remove-DbaServerRoleMember -Login $global:login2 -Confirm:$false

            $roleAfter = Get-DbaServerRole -SqlInstance $global:server -ServerRole $global:fixedServerRoles[0]
            $roleAfter.EnumMemberNames().Contains($global:login2) | Should -Be $false
        }
    }
}