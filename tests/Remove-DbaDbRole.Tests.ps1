#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbRole",
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
                "Database",
                "ExcludeDatabase",
                "Role",
                "ExcludeRole",
                "IncludeSystemDbs",
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

        # Set up test variables
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $role1 = "dbatoolssci_role1_$(Get-Random)"
        $role2 = "dbatoolssci_role2_$(Get-Random)"
        $dbname1 = "dbatoolsci_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $dbname1 -Owner sa

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup created database
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname1 -Confirm:$false

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Functionality" {
        It "Removes Non Fixed Roles" {
            $null = $server.Query("CREATE ROLE $role1", $dbname1)
            $null = $server.Query("CREATE ROLE $role2", $dbname1)
            $result0 = Get-DbaDbRole -SqlInstance $TestConfig.instance2 -Database $dbname1
            Remove-DbaDbRole -SqlInstance $TestConfig.instance2 -Database $dbname1 -Confirm:$false
            $result1 = Get-DbaDbRole -SqlInstance $TestConfig.instance2 -Database $dbname1

            $result0.Count | Should -BeGreaterThan $result1.Count
            $result1.Name -contains $role1 | Should -Be $false
            $result1.Name -contains $role2 | Should -Be $false
        }

        It "Accepts a list of roles" {
            $null = $server.Query("CREATE ROLE $role1", $dbname1)
            $null = $server.Query("CREATE ROLE $role2", $dbname1)
            $result0 = Get-DbaDbRole -SqlInstance $TestConfig.instance2 -Database $dbname1
            Remove-DbaDbRole -SqlInstance $TestConfig.instance2 -Database $dbname1 -Role $role1 -Confirm:$false
            $result1 = Get-DbaDbRole -SqlInstance $TestConfig.instance2 -Database $dbname1

            $result0.Count | Should -BeGreaterThan $result1.Count
            $result1.Name -contains $role1 | Should -Be $false
            $result1.Name -contains $role2 | Should -Be $true
        }
        It "Excludes databases Roles" {
            $null = $server.Query("CREATE ROLE $role1", $dbname1)
            $result0 = Get-DbaDbRole -SqlInstance $TestConfig.instance2 -Database $dbname1
            Remove-DbaDbRole -SqlInstance $TestConfig.instance2 -Database $dbname1 -ExcludeRole $role1 -Confirm:$false
            $result1 = Get-DbaDbRole -SqlInstance $TestConfig.instance2 -Database $dbname1

            $result0.Count | Should -BeGreaterThan $result1.Count
            $result1.Name -contains $role1 | Should -Be $true
            $result1.Name -contains $role2 | Should -Be $false
        }

        It "Excepts input from Get-DbaDbRole" {
            $result0 = Get-DbaDbRole -SqlInstance $TestConfig.instance2 -Database $dbname1 -Role $role2
            $result0 | Remove-DbaDbRole -Confirm:$false
            $result1 = Get-DbaDbRole -SqlInstance $TestConfig.instance2 -Database $dbname1

            $result1.Name -contains $role2 | Should -Be $false
        }

        It "Removes roles in System DB" {
            $null = $server.Query("CREATE ROLE $role1", "msdb")
            $result0 = Get-DbaDbRole -SqlInstance $TestConfig.instance2 -Database msdb
            Remove-DbaDbRole -SqlInstance $TestConfig.instance2 -Database msdb -Role $role1 -IncludeSystemDbs -Confirm:$false
            $result1 = Get-DbaDbRole -SqlInstance $TestConfig.instance2 -Database msdb

            $result0.Count | Should -BeGreaterThan $result1.Count
            $result1.Name -contains $role1 | Should -Be $false
        }
    }
}