#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Set-DbaDbIdentity",
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
                "Table",
                "ReSeedValue",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        Context "Table name normalization" {
            BeforeAll {
                $script:lastQuery = $null
                $script:mockDatabase = [PSCustomObject]@{
                    Name         = "db1"
                    IsAccessible = $true
                }
                $script:mockServer = [PSCustomObject]@{
                    Name               = "sql1"
                    ComputerName       = "sql1"
                    ServiceName        = "MSSQLSERVER"
                    DomainInstanceName = "sql1"
                    Databases          = @($script:mockDatabase)
                }

                function Invoke-DbaQuery {
                    param(
                        [Parameter(ValueFromPipeline)]
                        $InputObject,
                        $Query,
                        $Database,
                        [switch]$MessagesToOutput
                    )

                    process {
                        $script:lastQuery = $Query
                        "Checking identity information: current identity value '5'."
                    }
                }
                Mock Connect-DbaInstance { $script:mockServer }
            }

            It "escapes closing brackets in normalized table names for reseed" {
                $script:lastQuery = $null

                $result = Set-DbaDbIdentity -SqlInstance "sql1" -Database "db1" -Table "[dbo].[Bad]]Name]" -ReSeedValue 400

                $script:lastQuery | Should -Be "DBCC CHECKIDENT('[dbo].[Bad]]Name]', RESEED, 400)"
                $result.Cmd | Should -Be "DBCC CHECKIDENT('[dbo].[Bad]]Name]', RESEED, 400)"
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $random = Get-Random
        $tableName1 = "dbatools_getdbtbl1"
        $tableName2 = "dbatools_getdbtbl2"

        $dbname = "dbatoolsci_getdbUsage$random"
        $null = $server.Query("CREATE DATABASE $dbname")
        $null = $server.Query("CREATE TABLE $tableName1 (Id int NOT NULL IDENTITY (125, 1), Value varchar(5))", $dbname)
        $null = $server.Query("CREATE TABLE $tableName2 (Id int NOT NULL IDENTITY (  5, 1), Value varchar(5))", $dbname)

        $null = $server.Query("INSERT $tableName1(Value) SELECT 1", $dbname)
        $null = $server.Query("INSERT $tableName2(Value) SELECT 2", $dbname)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname | Remove-DbaDatabase

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Validate standard output" {
        BeforeAll {
            $props = "ComputerName", "InstanceName", "SqlInstance", "Database", "Table", "Cmd", "IdentityValue", "ColumnValue", "Output"
            $result = Set-DbaDbIdentity -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Table $tableName1, $tableName2
        }

        It "Should return property: <_>" -ForEach $props {
            $p = $result[0].PSObject.Properties[$PSItem]
            $p.Name | Should -Be $PSItem
        }

        It "Returns results for each table" {
            $result.Count | Should -Be 2
        }

        It "Returns correct results" {
            $result[1].IdentityValue | Should -Be 5
        }
    }

    Context "Reseed option returns correct results" {
        It "Returns correct results" {
            $result = Set-DbaDbIdentity -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Table $tableName2 -ReSeedValue 400
            $result.cmd | Should -Be "DBCC CHECKIDENT('[$tableName2]', RESEED, 400)"
            $result.IdentityValue | Should -Be "5."
        }
    }
}