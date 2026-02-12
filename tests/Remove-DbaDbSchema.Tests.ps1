#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbSchema",
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

        $randomSuffix = Get-Random
        $server1Instance = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
        $server2Instance = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2
        $null = Get-DbaProcess -SqlInstance $server1Instance, $server2Instance | Where-Object Program -match dbatools | Stop-DbaProcess -WarningAction SilentlyContinue
        $testDbName = "dbatoolsci_newdb_$randomSuffix"
        $testDatabases = New-DbaDatabase -SqlInstance $server1Instance, $server2Instance -Name $testDbName

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = $testDatabases | Remove-DbaDatabase

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When removing database schemas" {
        It "Should drop the schema successfully" {
            $splatNewSchema = @{
                SqlInstance = $server1Instance
                Database    = $testDbName
                Schema      = "TestSchema1"
            }
            $schema = New-DbaDbSchema @splatNewSchema
            $schema.Count | Should -Be 1
            $schema.Name | Should -Be "TestSchema1"
            $schema.Parent.Name | Should -Be $testDbName

            $splatRemoveSchema = @{
                SqlInstance = $server1Instance
                Database    = $testDbName
                Schema      = "TestSchema1"
            }
            Remove-DbaDbSchema @splatRemoveSchema

            $splatGetSchema = @{
                SqlInstance = $server1Instance
                Database    = $testDbName
                Schema      = "TestSchema1"
            }
            (Get-DbaDbSchema @splatGetSchema) | Should -BeNullOrEmpty

            $splatNewMultiSchema = @{
                SqlInstance = $server1Instance, $server2Instance
                Database    = $testDbName
                Schema      = "TestSchema2", "TestSchema3"
            }
            $schemas = New-DbaDbSchema @splatNewMultiSchema
            $schemas.Count | Should -Be 4
            $schemas.Name | Should -Be "TestSchema2", "TestSchema3", "TestSchema2", "TestSchema3"
            $schemas.Parent.Name | Should -Be $testDbName, $testDbName, $testDbName, $testDbName

            $splatRemoveMultiSchema = @{
                SqlInstance = $server1Instance, $server2Instance
                Database    = $testDbName
                Schema      = "TestSchema2", "TestSchema3"
            }
            Remove-DbaDbSchema @splatRemoveMultiSchema

            $splatGetMultiSchema = @{
                SqlInstance = $server1Instance, $server2Instance
                Database    = $testDbName
                Schema      = "TestSchema2", "TestSchema3"
            }
            (Get-DbaDbSchema @splatGetMultiSchema) | Should -BeNullOrEmpty
        }

        It "Should support piping databases" {
            $splatNewPipeSchema = @{
                SqlInstance = $server1Instance
                Database    = $testDbName
                Schema      = "TestSchema1"
            }
            $schema = New-DbaDbSchema @splatNewPipeSchema
            $schema.Count | Should -Be 1
            $schema.Name | Should -Be "TestSchema1"
            $schema.Parent.Name | Should -Be $testDbName

            Get-DbaDatabase -SqlInstance $server1Instance -Database $testDbName | Remove-DbaDbSchema -Schema "TestSchema1"

            $splatGetPipeSchema = @{
                SqlInstance = $server1Instance
                Database    = $testDbName
                Schema      = "TestSchema1"
            }
            (Get-DbaDbSchema @splatGetPipeSchema) | Should -BeNullOrEmpty
        }
    }

}

Describe "$CommandName - Output" -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $outputTestDb = "dbatoolsci_removesch_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $outputTestDb

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $outputTestDb -Confirm:$false -ErrorAction SilentlyContinue
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Output validation" {
        It "Returns no output" {
            $null = New-DbaDbSchema -SqlInstance $TestConfig.InstanceSingle -Database $outputTestDb -Schema "dbatoolsci_OutputSchema"
            $splatRemoveOutputSchema = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $outputTestDb
                Schema      = "dbatoolsci_OutputSchema"
                Confirm     = $false
            }
            $result = Remove-DbaDbSchema @splatRemoveOutputSchema
            $result | Should -BeNullOrEmpty
        }
    }
}