#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbIdentity",
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
                        "Checking identity information: current identity value '5', current column value '5'."
                    }
                }
                Mock Connect-DbaInstance { $script:mockServer }
            }

            It "escapes closing brackets in normalized table names" {
                $script:lastQuery = $null

                $result = Get-DbaDbIdentity -SqlInstance "sql1" -Database "db1" -Table "[dbo].[Bad]]Name]"

                $script:lastQuery | Should -Be "DBCC CHECKIDENT('[dbo].[Bad]]Name]', NORESEED)"
                $result.Cmd | Should -Be "DBCC CHECKIDENT('[dbo].[Bad]]Name]', NORESEED)"
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $db = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database tempdb
        $null = $db.Query("CREATE TABLE dbo.dbatoolsci_example (Id int NOT NULL IDENTITY (125, 1), Value varchar(5));
        INSERT INTO dbo.dbatoolsci_example(Value) Select 1;
        CREATE TABLE dbo.dbatoolsci_example2 (Id int NOT NULL IDENTITY (5, 1), Value varchar(5));
        INSERT INTO dbo.dbatoolsci_example2(Value) Select 1;")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = $db.Query("DROP TABLE dbo.dbatoolsci_example;
        DROP TABLE dbo.dbatoolsci_example2")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Validate standard output" {
        BeforeAll {
            $props = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Table",
                "Cmd",
                "IdentityValue",
                "ColumnValue",
                "Output"
            )
            $result = Get-DbaDbIdentity -SqlInstance $TestConfig.InstanceSingle -Database tempdb -Table "dbo.dbatoolsci_example", "dbo.dbatoolsci_example2"
        }

        It "Should return all expected properties" {
            foreach ($prop in $props) {
                $result[0].PSObject.Properties[$prop].Name | Should -Be $prop
            }
        }

        It "Returns results for each table" {
            $result.Count | Should -BeExactly 2
        }

        It "Returns correct results" {
            $result[0].IdentityValue | Should -BeExactly 125
        }
    }
}