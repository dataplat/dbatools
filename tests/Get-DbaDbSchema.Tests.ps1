#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbSchema",
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
                "Schema",
                "SchemaOwner",
                "IncludeSystemDatabases",
                "IncludeSystemSchemas",
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

        $random = Get-Random
        $server1 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
        $server2 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2
        $null = Get-DbaProcess -SqlInstance $server1, $server2 | Where-Object Program -match dbatools | Stop-DbaProcess -WarningAction SilentlyContinue
        $newDbName = "dbatoolsci_newdb_$random"
        $newDbs = New-DbaDatabase -SqlInstance $server1, $server2 -Name $newDbName

        $schemaName = "TestSchema"
        $schemaName2 = "TestSchema2"

        $userName = "user_$random"
        $userName2 = "user2_$random"
        $password = 'MyV3ry$ecur3P@ssw0rd'
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $logins = New-DbaLogin -SqlInstance $server1, $server2 -Login $userName, $userName2 -Password $securePassword -Force

        $null = New-DbaDbUser -SqlInstance $server1, $server2 -Database $newDbName -Login $userName
        $null = New-DbaDbUser -SqlInstance $server1, $server2 -Database $newDbName -Login $userName2

        $newDbs[0].Query("CREATE SCHEMA $schemaName AUTHORIZATION [$userName]")
        $newDbs[0].Schemas.Refresh()
        $newDbs[1].Query("CREATE SCHEMA $schemaName2 AUTHORIZATION [$userName2]")
        $newDbs[1].Schemas.Refresh()

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = $newDbs | Remove-DbaDatabase
        $null = $logins | Remove-DbaLogin

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "commands work as expected" {
        It "get all schemas from all databases including system dbs and schemas" {
            $schemas = Get-DbaDbSchema -SqlInstance $server1 -IncludeSystemDatabases -IncludeSystemSchemas
            $schemas.Count | Should -BeGreaterThan 1
            $schemas.Parent.Name | Should -Contain master
            $schemas.Parent.Name | Should -Contain msdb
            $schemas.Parent.Name | Should -Contain model
            $schemas.Parent.Name | Should -Contain tempdb
            $schemas.Name | Should -Contain dbo
            $schemas.Name | Should -Contain $schemaName
        }

        It "get all schemas from user databases including system schemas" {
            $schemas = Get-DbaDbSchema -SqlInstance $server1 -IncludeSystemSchemas
            $schemas.Count | Should -BeGreaterThan 1
            $schemas.Parent.Name | Should -Not -Contain master
            $schemas.Parent.Name | Should -Not -Contain msdb
            $schemas.Parent.Name | Should -Not -Contain model
            $schemas.Parent.Name | Should -Not -Contain tempdb
            $schemas.Name | Should -Contain dbo
            $schemas.Name | Should -Contain $schemaName
        }

        It "get non-system schemas from a user database" {
            $schemas = Get-DbaDbSchema -SqlInstance $server1 -Schema $schemaName
            $schemas.Name | Should -Contain $schemaName
            $schemas.Parent.Name | Should -Contain $newDbName
        }

        It "get a schema by name from a user database" {
            $schemas = Get-DbaDbSchema -SqlInstance $server1 -Database $newDbName -Schema $schemaName -OutVariable "global:dbatoolsciOutput"
            $schemas.Count | Should -Be 1
            $schemas.Name | Should -Be $schemaName
            $schemas.DatabaseName | Should -Be $newDbName
            $schemas.DatabaseId | Should -Be $newDbs[0].Id
            $schemas.ComputerName | Should -Be $server1.ComputerName
        }

        It "get the dbo schema" {
            $schemas = Get-DbaDbSchema -SqlInstance $server1 -Database $newDbName -Schema dbo -IncludeSystemSchemas
            $schemas.Count | Should -Be 1
            $schemas.Name | Should -Be dbo
        }

        It "get schemas by owner from a user database" {
            $schemas = Get-DbaDbSchema -SqlInstance $server1 -SchemaOwner $userName
            $schemas.Count | Should -Be 1
            $schemas.Name | Should -Be $schemaName
            $schemas.Owner | Should -Be $userName
            $schemas.Parent.Name | Should -Be $newDbName

            $schemas = Get-DbaDbSchema -SqlInstance $server1, $server2 -Database $newDbName -SchemaOwner $userName, $userName2
            $schemas.Count | Should -Be 2
            $schemas.Name | Should -Be $schemaName, $schemaName2
            $schemas.Owner | Should -Be $userName, $userName2
            $schemas.Parent.Name | Should -Be $newDbName, $newDbName
        }

        It "supports piping databases" {
            $schemas = $newDbs | Get-DbaDbSchema -Schema $schemaName, $schemaName2
            $schemas.Count | Should -Be 2
            $schemas.Owner | Should -Be $userName, $userName2
            $schemas.Name | Should -Be $schemaName, $schemaName2
            $schemas.Parent.Name | Should -Be $newDbName, $newDbName
        }

        It "get a schema and then change the owner" {
            $schemas = Get-DbaDbSchema -SqlInstance $server1 -Database $newDbName -Schema $schemaName
            $schemas.Count | Should -Be 1
            $schemas.Owner | Should -Be $userName

            $schemas.Owner = $userName2
            $schemas.Alter()

            $schemas = Get-DbaDbSchema -SqlInstance $server1 -Database $newDbName -Schema $schemaName
            $schemas.Count | Should -Be 1
            $schemas.Owner | Should -Be $userName2
        }

        It "get a schema and then drop it (assuming that it does not contain any objects)" {
            $schemas = Get-DbaDbSchema -SqlInstance $server2 -Database $newDbName -Schema $schemaName2
            $schemas.Count | Should -Be 1
            $schemas.Owner | Should -Be $userName2

            $schemas.Drop()

            $schemas = Get-DbaDbSchema -SqlInstance $server2 -Database $newDbName -Schema $schemaName2
            $schemas | Should -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Schema]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Name",
                "IsSystemObject"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.Schema"
        }
    }
}