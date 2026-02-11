#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaDbSchema",
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

        # Explain what needs to be set up for the test:
        # To create a database schema, we need a database and optionally a user to act as schema owner.
        # For testing schema creation, we need databases and users.

        # Set variables. They are available in all the It blocks.
        $random = Get-Random
        $server1 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
        $server2 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2
        $null = Get-DbaProcess -SqlInstance $server1, $server2 | Where-Object Program -match dbatools | Stop-DbaProcess -WarningAction SilentlyContinue
        $newDbName = "dbatoolsci_newdb_$random"
        $newDbs = New-DbaDatabase -SqlInstance $server1, $server2 -Name $newDbName

        $userName = "user_$random"
        $password = "MyV3ry`$ecur3P@ssw0rd"
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $logins = New-DbaLogin -SqlInstance $server1, $server2 -Login $userName -Password $securePassword -Force

        $null = New-DbaDbUser -SqlInstance $server1, $server2 -Database $newDbName -Login $userName

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = $newDbs | Remove-DbaDatabase
        $null = $logins | Remove-DbaLogin

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "commands work as expected" {

        It "validates required Schema" {
            $schema = New-DbaDbSchema -SqlInstance $server1 -WarningAction SilentlyContinue
            $WarnVar | Should -Match "Schema is required"
            $schema | Should -BeNullOrEmpty
        }

        It "validates required Database param" {
            $schema = New-DbaDbSchema -SqlInstance $server1 -Schema TestSchema1 -WarningAction SilentlyContinue
            $WarnVar | Should -Match "Database is required when SqlInstance is specified"
            $schema | Should -BeNullOrEmpty
        }

        It "creates a new schema" {
            $schema = New-DbaDbSchema -SqlInstance $server1 -Database $newDbName -Schema TestSchema1 -SchemaOwner $userName
            $schema.Count | Should -Be 1
            $schema.Owner | Should -Be $userName
            $schema.Name | Should -Be TestSchema1
            $schema.Parent.Name | Should -Be $newDbName

            $schemas = New-DbaDbSchema -SqlInstance $server1, $server2 -Database $newDbName -Schema TestSchema2, TestSchema3 -SchemaOwner $userName
            $schemas.Count | Should -Be 4
            $schemas.Owner | Should -Be $userName, $userName, $userName, $userName
            $schemas.Name | Should -Be TestSchema2, TestSchema3, TestSchema2, TestSchema3
            $schemas.Parent.Name | Should -Be $newDbName, $newDbName, $newDbName, $newDbName
        }

        It "reports a warning that the schema already exists" {
            $schema = New-DbaDbSchema -SqlInstance $server1 -Database $newDbName -Schema TestSchema1 -SchemaOwner $userName -WarningAction SilentlyContinue
            $WarnVar | Should -Match "Schema TestSchema1 already exists in the database"
            $schema | Should -BeNullOrEmpty
        }

        It "supports piping databases" {
            $schema = Get-DbaDatabase -SqlInstance $server1 -Database $newDbName | New-DbaDbSchema -Schema TestSchema4
            $schema.Count | Should -Be 1
            $schema.Owner | Should -Be dbo
            $schema.Name | Should -Be TestSchema4
            $schema.Parent.Name | Should -Be $newDbName
        }
    }

    Context "Output validation" {
        BeforeAll {
            $outputSchema = New-DbaDbSchema -SqlInstance $server1 -Database $newDbName -Schema "dbatoolsci_outputtest"
        }
        AfterAll {
            $null = Invoke-DbaQuery -SqlInstance $server1 -Database $newDbName -Query "DROP SCHEMA [dbatoolsci_outputtest]" -ErrorAction SilentlyContinue
        }

        It "Returns output of the documented type" {
            $outputSchema | Should -Not -BeNullOrEmpty
            $outputSchema[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Schema"
        }

        It "Has no default display property set since Select-DefaultView is not used" {
            $outputSchema[0].PSStandardMembers.DefaultDisplayPropertySet | Should -BeNullOrEmpty
        }
    }
}