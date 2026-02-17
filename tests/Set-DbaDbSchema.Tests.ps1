#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbSchema",
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

        $random = Get-Random
        $splatConnection1 = @{
            SqlInstance = $TestConfig.InstanceMulti1
        }
        $splatConnection2 = @{
            SqlInstance = $TestConfig.InstanceMulti2
        }
        $server1 = Connect-DbaInstance @splatConnection1
        $server2 = Connect-DbaInstance @splatConnection2
        $null = Get-DbaProcess -SqlInstance $server1, $server2 | Where-Object Program -match dbatools | Stop-DbaProcess -WarningAction SilentlyContinue
        $newDbName = "dbatoolsci_newdb_$random"
        $splatNewDb = @{
            SqlInstance = $server1, $server2
            Name        = $newDbName
        }
        $newDbs = New-DbaDatabase @splatNewDb

        $userName = "user_$random"
        $userName2 = "user2_$random"
        $password = "MyV3ry`$ecur3P@ssw0rd"
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $splatLogins = @{
            SqlInstance = $server1, $server2
            Login       = $userName, $userName2
            Password    = $securePassword
            Force       = $true
        }
        $logins = New-DbaLogin @splatLogins

        $splatUser1 = @{
            SqlInstance = $server1, $server2
            Database    = $newDbName
            Login       = $userName
        }
        $null = New-DbaDbUser @splatUser1
        $splatUser2 = @{
            SqlInstance = $server1, $server2
            Database    = $newDbName
            Login       = $userName2
        }
        $null = New-DbaDbUser @splatUser2

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

        It "updates the schema to a different owner" {
            $splatNewSchema = @{
                SqlInstance = $server1
                Database    = $newDbName
                Schema      = "TestSchema1"
                SchemaOwner = $userName
            }
            $schema = New-DbaDbSchema @splatNewSchema
            $schema.Count | Should -Be 1
            $schema.Owner | Should -Be $userName
            $schema.Name | Should -Be "TestSchema1"
            $schema.Parent.Name | Should -Be $newDbName

            $splatUpdateSchema = @{
                SqlInstance = $server1
                Database    = $newDbName
                Schema      = "TestSchema1"
                SchemaOwner = $userName2
            }
            $updatedSchema = Set-DbaDbSchema @splatUpdateSchema -OutVariable "global:dbatoolsciOutput"
            $updatedSchema.Count | Should -Be 1
            $updatedSchema.Owner | Should -Be $userName2
            $updatedSchema.Name | Should -Be "TestSchema1"
            $updatedSchema.Parent.Name | Should -Be $newDbName

            $splatNewSchemas = @{
                SqlInstance = $server1, $server2
                Database    = $newDbName
                Schema      = "TestSchema2", "TestSchema3"
                SchemaOwner = $userName
            }
            $schemas = New-DbaDbSchema @splatNewSchemas
            $schemas.Count | Should -Be 4
            $schemas.Owner | Should -Be $userName, $userName, $userName, $userName
            $schemas.Name | Should -Be "TestSchema2", "TestSchema3", "TestSchema2", "TestSchema3"
            $schemas.Parent.Name | Should -Be $newDbName, $newDbName, $newDbName, $newDbName

            $splatUpdateSchemas = @{
                SqlInstance = $server1, $server2
                Database    = $newDbName
                Schema      = "TestSchema2", "TestSchema3"
                SchemaOwner = $userName2
            }
            $updatedSchemas = Set-DbaDbSchema @splatUpdateSchemas
            $updatedSchemas.Count | Should -Be 4
            $updatedSchemas.Owner | Should -Be $userName2, $userName2, $userName2, $userName2
            $updatedSchemas.Name | Should -Be "TestSchema2", "TestSchema3", "TestSchema2", "TestSchema3"
            $updatedSchemas.Parent.Name | Should -Be $newDbName, $newDbName, $newDbName, $newDbName
        }

        It "supports piping databases" {
            $schema = Get-DbaDatabase -SqlInstance $server1 -Database $newDbName | Set-DbaDbSchema -Schema "TestSchema1" -SchemaOwner $userName
            $schema.Count | Should -Be 1
            $schema.Owner | Should -Be $userName
            $schema.Name | Should -Be "TestSchema1"
            $schema.Parent.Name | Should -Be $newDbName
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