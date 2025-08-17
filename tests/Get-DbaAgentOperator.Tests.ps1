#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaAgentOperator",
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
                "Operator",
                "ExcludeOperator",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $sql = "EXEC msdb.dbo.sp_add_operator @name=N'dbatoolsci_operator', @enabled=1, @pager_days=0"
        $server.Query($sql)
        $sql = "EXEC msdb.dbo.sp_add_operator @name=N'dbatoolsci_operator2', @enabled=1, @pager_days=0"
        $server.Query($sql)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        $sql = "EXEC msdb.dbo.sp_delete_operator @name=N'dbatoolsci_operator'"
        $server.Query($sql)
        $sql = "EXEC msdb.dbo.sp_delete_operator @name=N'dbatoolsci_operator2'"
        $server.Query($sql)

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Get back some operators" {
        It "return at least two results" {
            $results = Get-DbaAgentOperator -SqlInstance $TestConfig.instance2
            $results.Count -ge 2 | Should -Be $true
        }

        It "return one result" {
            $results = Get-DbaAgentOperator -SqlInstance $TestConfig.instance2 -Operator dbatoolsci_operator
            $results.Count | Should -BeExactly 1
        }
    }
}