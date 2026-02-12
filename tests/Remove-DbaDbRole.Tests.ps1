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
                "Force",
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
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $role1 = "dbatoolssci_role1_$(Get-Random)"
        $role2 = "dbatoolssci_role2_$(Get-Random)"
        $dbname1 = "dbatoolsci_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbname1 -Owner sa

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup created database
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname1

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Functionality" {
        It "Removes Non Fixed Roles" {
            $null = $server.Query("CREATE ROLE $role1", $dbname1)
            $null = $server.Query("CREATE ROLE $role2", $dbname1)
            $result0 = Get-DbaDbRole -SqlInstance $TestConfig.InstanceSingle -Database $dbname1
            Remove-DbaDbRole -SqlInstance $TestConfig.InstanceSingle -Database $dbname1
            $result1 = Get-DbaDbRole -SqlInstance $TestConfig.InstanceSingle -Database $dbname1

            $result0.Count | Should -BeGreaterThan $result1.Count
            $result1.Name -contains $role1 | Should -Be $false
            $result1.Name -contains $role2 | Should -Be $false
        }

        It "Accepts a list of roles" {
            $null = $server.Query("CREATE ROLE $role1", $dbname1)
            $null = $server.Query("CREATE ROLE $role2", $dbname1)
            $result0 = Get-DbaDbRole -SqlInstance $TestConfig.InstanceSingle -Database $dbname1
            Remove-DbaDbRole -SqlInstance $TestConfig.InstanceSingle -Database $dbname1 -Role $role1
            $result1 = Get-DbaDbRole -SqlInstance $TestConfig.InstanceSingle -Database $dbname1

            $result0.Count | Should -BeGreaterThan $result1.Count
            $result1.Name -contains $role1 | Should -Be $false
            $result1.Name -contains $role2 | Should -Be $true
        }
        It "Excludes databases Roles" {
            $null = $server.Query("CREATE ROLE $role1", $dbname1)
            $result0 = Get-DbaDbRole -SqlInstance $TestConfig.InstanceSingle -Database $dbname1
            Remove-DbaDbRole -SqlInstance $TestConfig.InstanceSingle -Database $dbname1 -ExcludeRole $role1
            $result1 = Get-DbaDbRole -SqlInstance $TestConfig.InstanceSingle -Database $dbname1

            $result0.Count | Should -BeGreaterThan $result1.Count
            $result1.Name -contains $role1 | Should -Be $true
            $result1.Name -contains $role2 | Should -Be $false
        }

        It "Excepts input from Get-DbaDbRole" {
            $result0 = Get-DbaDbRole -SqlInstance $TestConfig.InstanceSingle -Database $dbname1 -Role $role2
            $result0 | Remove-DbaDbRole
            $result1 = Get-DbaDbRole -SqlInstance $TestConfig.InstanceSingle -Database $dbname1

            $result1.Name -contains $role2 | Should -Be $false
        }

        It "Removes roles in System DB" {
            $null = $server.Query("CREATE ROLE $role1", "msdb")
            $result0 = Get-DbaDbRole -SqlInstance $TestConfig.InstanceSingle -Database msdb
            Remove-DbaDbRole -SqlInstance $TestConfig.InstanceSingle -Database msdb -Role $role1 -IncludeSystemDbs
            $result1 = Get-DbaDbRole -SqlInstance $TestConfig.InstanceSingle -Database msdb

            $result0.Count | Should -BeGreaterThan $result1.Count
            $result1.Name -contains $role1 | Should -Be $false
        }

        It "Returns no output" {
            $outputRole = "dbatoolssci_outval_$(Get-Random)"
            $null = $server.Query("CREATE ROLE [$outputRole]", $dbname1)
            $result = Remove-DbaDbRole -SqlInstance $TestConfig.InstanceSingle -Database $dbname1 -Role $outputRole -Confirm:$false
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Schema ownership handling" {
        BeforeEach {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Create a unique role and schema for each test
            $testRole = "dbatoolssci_role_$(Get-Random)"
            $diffSchema = "dbatoolssci_diffsch_$(Get-Random)"
        }

        AfterEach {
            # Cleanup - remove any leftover objects
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Drop any test tables first
            $null = $server.Query("IF EXISTS (SELECT * FROM sys.tables WHERE name = 'TestTable' AND schema_id = SCHEMA_ID('$diffSchema')) DROP TABLE [$diffSchema].[TestTable]", $dbname1)

            # Drop schemas if they exist
            $null = $server.Query("IF EXISTS (SELECT * FROM sys.schemas WHERE name = '$testRole') DROP SCHEMA [$testRole]", $dbname1)
            $null = $server.Query("IF EXISTS (SELECT * FROM sys.schemas WHERE name = '$diffSchema') DROP SCHEMA [$diffSchema]", $dbname1)

            # Drop role if it exists
            $null = $server.Query("IF EXISTS (SELECT * FROM sys.database_principals WHERE name = '$testRole' AND type = 'R') DROP ROLE [$testRole]", $dbname1)

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Removes role with empty schema of same name" {
            # Create role and schema with same name
            $null = $server.Query("CREATE ROLE [$testRole]", $dbname1)
            $null = $server.Query("CREATE SCHEMA [$testRole] AUTHORIZATION [$testRole]", $dbname1)

            # Remove the role (schema should be dropped automatically)
            Remove-DbaDbRole -SqlInstance $TestConfig.InstanceSingle -Database $dbname1 -Role $testRole -Confirm:$false

            # Verify role is removed
            $result = Get-DbaDbRole -SqlInstance $TestConfig.InstanceSingle -Database $dbname1 -Role $testRole
            $result | Should -BeNullOrEmpty

            # Verify schema is also removed
            $splatQuery = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbname1
                Query       = "SELECT name FROM sys.schemas WHERE name = '$testRole'"
            }
            $schemaExists = Invoke-DbaQuery @splatQuery
            $schemaExists | Should -BeNullOrEmpty
        }

        It "Does not remove role with schema containing objects without -Force" {
            # Create role and different schema with objects
            $null = $server.Query("CREATE ROLE [$testRole]", $dbname1)
            $null = $server.Query("CREATE SCHEMA [$diffSchema] AUTHORIZATION [$testRole]", $dbname1)
            $null = $server.Query("CREATE TABLE [$diffSchema].[TestTable] (ID INT)", $dbname1)

            # Try to remove the role without Force (should fail with warning)
            $result = Remove-DbaDbRole -SqlInstance $TestConfig.InstanceSingle -Database $dbname1 -Role $testRole -Confirm:$false -WarningVariable warn -WarningAction SilentlyContinue

            # Verify role still exists
            $roleCheck = Get-DbaDbRole -SqlInstance $TestConfig.InstanceSingle -Database $dbname1 -Role $testRole
            $roleCheck | Should -Not -BeNullOrEmpty
            $roleCheck.Name | Should -Be $testRole
        }

        It "Removes role and reassigns schema ownership with -Force" {
            # Create role and different schema with objects
            $null = $server.Query("CREATE ROLE [$testRole]", $dbname1)
            $null = $server.Query("CREATE SCHEMA [$diffSchema] AUTHORIZATION [$testRole]", $dbname1)
            $null = $server.Query("CREATE TABLE [$diffSchema].[TestTable] (ID INT)", $dbname1)

            # Remove the role with Force (should reassign schema to dbo and remove role)
            Remove-DbaDbRole -SqlInstance $TestConfig.InstanceSingle -Database $dbname1 -Role $testRole -Force -Confirm:$false

            # Verify role is removed
            $roleCheck = Get-DbaDbRole -SqlInstance $TestConfig.InstanceSingle -Database $dbname1 -Role $testRole
            $roleCheck | Should -BeNullOrEmpty

            # Verify schema ownership changed to dbo
            $splatQuery = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbname1
                Query       = "SELECT SCHEMA_NAME(schema_id) AS SchemaName, USER_NAME(principal_id) AS Owner FROM sys.schemas WHERE name = '$diffSchema'"
            }
            $schemaOwner = Invoke-DbaQuery @splatQuery
            $schemaOwner.Owner | Should -Be "dbo"
        }
    }
}