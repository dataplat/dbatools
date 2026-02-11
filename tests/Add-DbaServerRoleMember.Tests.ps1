#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Add-DbaServerRoleMember",
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

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $login1 = "dbatoolsci_login1_$(Get-Random)"
        $login2 = "dbatoolsci_login2_$(Get-Random)"
        $customServerRole = "dbatoolsci_customrole_$(Get-Random)"
        $fixedServerRoles = @(
            "dbcreator",
            "processadmin"
        )
        $splatNewLogin = @{
            SqlInstance = $TestConfig.InstanceSingle
            Password    = ("Password1234!" | ConvertTo-SecureString -asPlainText -Force)
        }
        $null = New-DbaLogin @splatNewLogin -Login $login1
        $null = New-DbaLogin @splatNewLogin -Login $login2
        $null = New-DbaServerRole -SqlInstance $TestConfig.InstanceSingle -ServerRole $customServerRole -Owner sa

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $splatRemoveLogin = @{
            SqlInstance = $TestConfig.InstanceSingle
            Login       = $login1, $login2
        }
        $null = Remove-DbaLogin @splatRemoveLogin
        $null = Remove-DbaServerRole -SqlInstance $TestConfig.InstanceSingle -ServerRole $customServerRole -Confirm:$false

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Functionality" {
        It "Adds Login to Role" {
            $splatAddRole = @{
                SqlInstance = $TestConfig.InstanceSingle
                ServerRole  = $fixedServerRoles[0]
                Login       = $login1
            }
            Add-DbaServerRoleMember @splatAddRole
            $roleAfter = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles[0]

            $roleAfter.Role | Should -Be $fixedServerRoles[0]
            $roleAfter.EnumMemberNames() | Should -Contain $login1
        }

        It "Adds Login to Multiple Roles" {
            $serverRoles = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles
            $splatAddRoles = @{
                SqlInstance = $TestConfig.InstanceSingle
                ServerRole  = $serverRoles
                Login       = $login1
            }
            Add-DbaServerRoleMember @splatAddRoles

            $roleDBAfter = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles
            $roleDBAfter.Count | Should -Be $serverRoles.Count
            $roleDBAfter.Login | Should -Contain $login1
        }

        It "Adds Customer Server-Level Role Membership" {
            $splatAddCustomRole = @{
                SqlInstance = $TestConfig.InstanceSingle
                ServerRole  = $customServerRole
                Role        = $fixedServerRoles[-1]
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

    Context "Output validation" {
        BeforeAll {
            $outputTestLogin = "dbatoolsci_outputlogin_$(Get-Random)"
            $outputTestRole = "dbatoolsci_outputrole_$(Get-Random)"
            $splatOutputLogin = @{
                SqlInstance = $TestConfig.InstanceSingle
                Login       = $outputTestLogin
                Password    = ("Password1234!" | ConvertTo-SecureString -AsPlainText -Force)
            }
            $null = New-DbaLogin @splatOutputLogin
            $null = New-DbaServerRole -SqlInstance $TestConfig.InstanceSingle -ServerRole $outputTestRole -Owner sa
        }

        AfterAll {
            $null = Remove-DbaServerRoleMember -SqlInstance $TestConfig.InstanceSingle -ServerRole $outputTestRole -Login $outputTestLogin -Confirm:$false -ErrorAction SilentlyContinue
            $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $outputTestLogin -ErrorAction SilentlyContinue
            $null = Remove-DbaServerRole -SqlInstance $TestConfig.InstanceSingle -ServerRole $outputTestRole -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "Returns no output" {
            $result = Add-DbaServerRoleMember -SqlInstance $TestConfig.InstanceSingle -ServerRole $outputTestRole -Login $outputTestLogin -Confirm:$false
            $result | Should -BeNullOrEmpty
        }
    }
}