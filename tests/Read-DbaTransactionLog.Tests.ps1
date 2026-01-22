#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Read-DbaTransactionLog",
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
                "IgnoreLimit",
                "RowLimit",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1 -EnableException
            $dbName = "dbatoolsci_translog_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $server -Name $dbName -EnableException
            # Perform some operations to generate log entries
            $null = $server.Query("CREATE TABLE dbo.TestTable (ID INT); INSERT INTO dbo.TestTable VALUES (1); DROP TABLE dbo.TestTable;", $dbName)
            $result = Read-DbaTransactionLog -SqlInstance $TestConfig.instance1 -Database $dbName -RowLimit 10 -EnableException
        }

        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbName -Confirm:$false -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType [System.Data.DataRow]
        }

        It "Has common transaction log properties" {
            $expectedProps = @(
                'LSN',
                'Operation'
            )
            $actualProps = $result[0].Table.Columns.ColumnName
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in fn_dblog output"
            }
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>