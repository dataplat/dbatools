#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Invoke-DbaDbDbccUpdateUsage",
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
                "Index",
                "NoInformationalMessages",
                "CountRows",
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
                    ID           = 5
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
                        [switch]$MessagesToOutput
                    )

                    process {
                        $script:lastQuery = $Query
                        @("DBCC execution completed. If DBCC printed error messages, contact your system administrator.")
                    }
                }
                Mock Connect-DbaInstance { $script:mockServer }
            }

            It "escapes closing brackets in normalized table names" {
                $script:lastQuery = $null

                $result = Invoke-DbaDbDbccUpdateUsage -SqlInstance "sql1" -Database "db1" -Table "[dbo].[Bad]]Name]"

                $script:lastQuery | Should -Be "DBCC UPDATEUSAGE('db1', '[dbo].[Bad]]Name]')"
                $result.Cmd | Should -Be "DBCC UPDATEUSAGE('db1', '[dbo].[Bad]]Name]')"
            }
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $random = Get-Random
        $tableName = "dbatools_getdbtbl1"

        $dbname = "dbatoolsci_getdbUsage$random"
        $db = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbname
        $null = $db.Query("CREATE TABLE $tableName (id int)", $dbname)
        $null = $db.Query("CREATE CLUSTERED INDEX [PK_Id] ON $tableName ([id] ASC)", $dbname)
        $null = $db.Query("INSERT $tableName(id) SELECT object_id FROM sys.objects", $dbname)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname | Remove-DbaDatabase

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Validate standard output" {
        BeforeAll {
            $props = "ComputerName", "InstanceName", "SqlInstance", "Database", "Cmd", "Output"
            $result = Invoke-DbaDbDbccUpdateUsage -SqlInstance $TestConfig.InstanceSingle
        }

        It "returns results" {
            $result.Count -gt 0 | Should -BeTrue
        }

        It "Should return all required properties" {
            foreach ($prop in $props) {
                $result[0].PSObject.Properties[$prop].Name | Should -Be $prop
            }
        }
    }

    Context "Validate returns results" {
        It "returns results for table" {
            $result = Invoke-DbaDbDbccUpdateUsage -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Table $tableName
            $result.Output -match "DBCC execution completed. If DBCC printed error messages, contact your system administrator." | Should -BeTrue
        }

        It "returns results for index by id" {
            $result = Invoke-DbaDbDbccUpdateUsage -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Table $tableName -Index 1
            $result.Output -match "DBCC execution completed. If DBCC printed error messages, contact your system administrator." | Should -BeTrue
        }
    }

}