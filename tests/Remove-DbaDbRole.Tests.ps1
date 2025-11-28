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
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname1

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Functionality" {
        It "Removes Non Fixed Roles" {
            $null = $server.Query("CREATE ROLE $role1", $dbname1)
            $null = $server.Query("CREATE ROLE $role2", $dbname1)
            $result0 = Get-DbaDbRole -SqlInstance $TestConfig.instance2 -Database $dbname1
            Remove-DbaDbRole -SqlInstance $TestConfig.instance2 -Database $dbname1
            $result1 = Get-DbaDbRole -SqlInstance $TestConfig.instance2 -Database $dbname1

            $result0.Count | Should -BeGreaterThan $result1.Count
            $result1.Name -contains $role1 | Should -Be $false
            $result1.Name -contains $role2 | Should -Be $false
        }

        It "Accepts a list of roles" {
            $null = $server.Query("CREATE ROLE $role1", $dbname1)
            $null = $server.Query("CREATE ROLE $role2", $dbname1)
            $result0 = Get-DbaDbRole -SqlInstance $TestConfig.instance2 -Database $dbname1
            Remove-DbaDbRole -SqlInstance $TestConfig.instance2 -Database $dbname1 -Role $role1
            $result1 = Get-DbaDbRole -SqlInstance $TestConfig.instance2 -Database $dbname1

            $result0.Count | Should -BeGreaterThan $result1.Count
            $result1.Name -contains $role1 | Should -Be $false
            $result1.Name -contains $role2 | Should -Be $true
        }
        It "Excludes databases Roles" {
            $null = $server.Query("CREATE ROLE $role1", $dbname1)
            $result0 = Get-DbaDbRole -SqlInstance $TestConfig.instance2 -Database $dbname1
            Remove-DbaDbRole -SqlInstance $TestConfig.instance2 -Database $dbname1 -ExcludeRole $role1
            $result1 = Get-DbaDbRole -SqlInstance $TestConfig.instance2 -Database $dbname1

            $result0.Count | Should -BeGreaterThan $result1.Count
            $result1.Name -contains $role1 | Should -Be $true
            $result1.Name -contains $role2 | Should -Be $false
        }

        It "Excepts input from Get-DbaDbRole" {
            $result0 = Get-DbaDbRole -SqlInstance $TestConfig.instance2 -Database $dbname1 -Role $role2
            $result0 | Remove-DbaDbRole
            $result1 = Get-DbaDbRole -SqlInstance $TestConfig.instance2 -Database $dbname1

            $result1.Name -contains $role2 | Should -Be $false
        }

        It "Removes roles in System DB" {
            $null = $server.Query("CREATE ROLE $role1", "msdb")
            $result0 = Get-DbaDbRole -SqlInstance $TestConfig.instance2 -Database msdb
            Remove-DbaDbRole -SqlInstance $TestConfig.instance2 -Database msdb -Role $role1 -IncludeSystemDbs
            $result1 = Get-DbaDbRole -SqlInstance $TestConfig.instance2 -Database msdb

            $result0.Count | Should -BeGreaterThan $result1.Count
            $result1.Name -contains $role1 | Should -Be $false
        }
    }

    Context "Schema ownership handling" {
        BeforeEach {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $roleWithSchema = "dbatoolssci_rolesch_$(Get-Random)"
            $roleWithDiffSchema = "dbatoolssci_rolediff_$(Get-Random)"
            $diffSchemaName = "dbatoolssci_diffsch_$(Get-Random)"
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Removes role with empty schema of same name" {
            $null = $server.Query("CREATE ROLE $roleWithSchema", $dbname1)
            $null = $server.Query("CREATE SCHEMA $roleWithSchema AUTHORIZATION $roleWithSchema", $dbname1)
            $splatRemove = @{
                SqlInstance = $TestConfig.instance2
                Database    = $dbname1
                Role        = $roleWithSchema
                Confirm     = $false
            }
            Remove-DbaDbRole @splatRemove
            $result = Get-DbaDbRole -SqlInstance $TestConfig.instance2 -Database $dbname1
            $result.Name -contains $roleWithSchema | Should -Be $false
        }

        It "Does not remove role with schema containing objects without -Force" {
            $null = $server.Query("CREATE ROLE $roleWithDiffSchema", $dbname1)
            $null = $server.Query("CREATE SCHEMA $diffSchemaName AUTHORIZATION $roleWithDiffSchema", $dbname1)
            $null = $server.Query("CREATE TABLE $diffSchemaName.TestTable (ID INT)", $dbname1)
            $splatRemove = @{
                SqlInstance     = $TestConfig.instance2
                Database        = $dbname1
                Role            = $roleWithDiffSchema
                Confirm         = $false
                WarningVariable = "warnOutput"
            }
            Remove-DbaDbRole @splatRemove
            $result = Get-DbaDbRole -SqlInstance $TestConfig.instance2 -Database $dbname1
            $result.Name -contains $roleWithDiffSchema | Should -Be $true
            $warnOutput | Should -Not -BeNullOrEmpty
        }

        It "Removes role and reassigns schema ownership with -Force" {
            $null = $server.Query("CREATE ROLE $roleWithDiffSchema", $dbname1)
            $null = $server.Query("CREATE SCHEMA $diffSchemaName AUTHORIZATION $roleWithDiffSchema", $dbname1)
            $null = $server.Query("CREATE TABLE $diffSchemaName.TestTable (ID INT)", $dbname1)
            $splatRemove = @{
                SqlInstance = $TestConfig.instance2
                Database    = $dbname1
                Role        = $roleWithDiffSchema
                Force       = $true
                Confirm     = $false
            }
            Remove-DbaDbRole @splatRemove
            $result = Get-DbaDbRole -SqlInstance $TestConfig.instance2 -Database $dbname1
            $result.Name -contains $roleWithDiffSchema | Should -Be $false
            $db = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname1
            $schema = $db.Schemas | Where-Object Name -eq $diffSchemaName
            $schema.Owner | Should -Be "dbo"
        }

        AfterEach {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $splatCleanup = @{
                SqlInstance = $TestConfig.instance2
                Database    = $dbname1
                Role        = @($roleWithSchema, $roleWithDiffSchema)
                Force       = $true
                Confirm     = $false
            }
            Remove-DbaDbRole @splatCleanup -ErrorAction SilentlyContinue
            $null = $server.Query("IF EXISTS (SELECT * FROM sys.schemas WHERE name = '$diffSchemaName') DROP SCHEMA $diffSchemaName", $dbname1)
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
    }
}