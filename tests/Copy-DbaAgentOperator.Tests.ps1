#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaAgentOperator",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Operator",
                "ExcludeOperator",
                "Force",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $sqlAddOperator1 = "EXEC msdb.dbo.sp_add_operator @name=N'dbatoolsci_operator', @enabled=1, @pager_days=0"
        $sourceServer.Query($sqlAddOperator1)
        $sqlAddOperator2 = "EXEC msdb.dbo.sp_add_operator @name=N'dbatoolsci_operator2', @enabled=1, @pager_days=0"
        $sourceServer.Query($sqlAddOperator2)
    }

    AfterAll {
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        $sourceCleanupServer = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $sqlDeleteOp1Source = "EXEC msdb.dbo.sp_delete_operator @name=N'dbatoolsci_operator'"
        $sourceCleanupServer.Query($sqlDeleteOp1Source)
        $sqlDeleteOp2Source = "EXEC msdb.dbo.sp_delete_operator @name=N'dbatoolsci_operator2'"
        $sourceCleanupServer.Query($sqlDeleteOp2Source)

        $destCleanupServer = Connect-DbaInstance -SqlInstance $TestConfig.instance3
        $sqlDeleteOp1Dest = "EXEC msdb.dbo.sp_delete_operator @name=N'dbatoolsci_operator'"
        $destCleanupServer.Query($sqlDeleteOp1Dest)
        $sqlDeleteOp2Dest = "EXEC msdb.dbo.sp_delete_operator @name=N'dbatoolsci_operator2'"
        $destCleanupServer.Query($sqlDeleteOp2Dest)
    }

    Context "When copying operators" {
        It "Returns two copied operators" {
            $splatCopyOperators = @{
                Source      = $TestConfig.instance2
                Destination = $TestConfig.instance3
                Operator    = "dbatoolsci_operator", "dbatoolsci_operator2"
            }
            $results = Copy-DbaAgentOperator @splatCopyOperators
            $results.Status.Count | Should -Be 2
            $results.Status | Should -Be "Successful", "Successful"
        }

        It "Returns one result that's skipped when copying an existing operator" {
            $splatCopyExisting = @{
                Source      = $TestConfig.instance2
                Destination = $TestConfig.instance3
                Operator    = "dbatoolsci_operator"
            }
            (Copy-DbaAgentOperator @splatCopyExisting).Status | Should -Be "Skipped"
        }
    }
}
