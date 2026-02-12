#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaServerRoleMember",
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
                "ExcludeServerRole",
                "Login",
                "ExcludeFixedRole",
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

        $server2 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2

        $password1 = ConvertTo-SecureString "password1" -AsPlainText -Force
        $testLogin = "getDbaInstanceRoleMemberLogin"
        $null = New-DbaLogin -SqlInstance $server2 -Login $testLogin -Password $password1
        $null = Set-DbaLogin -SqlInstance $server2 -Login $testLogin -AddRole "dbcreator"

        $server1 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
        $null = New-DbaLogin -SqlInstance $server1 -Login $testLogin -Password $password1
        $null = Set-DbaLogin -SqlInstance $server1 -Login $testLogin -AddRole "dbcreator"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Functionality" {
        It "Returns all role membership for server roles" {
            $result = Get-DbaServerRoleMember -SqlInstance $server2

            # should have at least $testLogin and a sysadmin
            $result.Count | Should -BeGreaterOrEqual 2
        }

        It "Accepts a list of roles" {
            $result = Get-DbaServerRoleMember -SqlInstance $server2 -ServerRole "sysadmin"

            $uniqueRoles = $result.Role | Select-Object -Unique
            $uniqueRoles | Should -Be "sysadmin"
        }

        It "Excludes roles" {
            $result = Get-DbaServerRoleMember -SqlInstance $server2 -ExcludeServerRole "dbcreator"

            $uniqueRoles = $result.Role | Select-Object -Unique
            $uniqueRoles | Should -Not -Contain "dbcreator"
            $uniqueRoles | Should -Contain "sysadmin"
        }

        It "Excludes fixed roles" {
            $result = Get-DbaServerRoleMember -SqlInstance $server2 -ExcludeFixedRole
            $uniqueRoles = $result.Role | Select-Object -Unique
            $uniqueRoles | Should -Not -Contain "sysadmin"
        }

        It "Filters by a specific login" {
            $result = Get-DbaServerRoleMember -SqlInstance $server2 -Login $testLogin

            $uniqueLogins = $result.Name | Select-Object -Unique
            $uniqueLogins.Count | Should -BeExactly 1
            $uniqueLogins | Should -Contain $testLogin
        }

        It "Returns results for all instances" {
            $result = Get-DbaServerRoleMember -SqlInstance $server2, $server1 -Login $testLogin

            $uniqueInstances = $result.SqlInstance | Select-Object -Unique
            $uniqueInstances.Count | Should -BeExactly 2
        }

        It "Returns output of the expected type" {
            $result = Get-DbaServerRoleMember -SqlInstance $server2
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            $result = Get-DbaServerRoleMember -SqlInstance $server2
            $result | Should -Not -BeNullOrEmpty
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Role",
                "Name",
                "SmoRole",
                "SmoLogin"
            )
            foreach ($prop in $expectedProperties) {
                $result[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaLogin -SqlInstance $server2 -Login $testLogin -Force -ErrorAction SilentlyContinue
        Remove-DbaLogin -SqlInstance $server1 -Login $testLogin -Force -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
}
