param($ModuleName = 'dbatools')

Describe "Get-DbaAgentOperator" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaAgentOperator
        }

        It "has the required parameter: <_>" -ForEach @(
            "SqlInstance",
            "SqlCredential",
            "Operator",
            "ExcludeOperator",
            "EnableException"
        ) {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $sql = "EXEC msdb.dbo.sp_add_operator @name=N'dbatoolsci_operator', @enabled=1, @pager_days=0"
            $server.Query($sql)
            $sql = "EXEC msdb.dbo.sp_add_operator @name=N'dbatoolsci_operator2', @enabled=1, @pager_days=0"
            $server.Query($sql)
        }

        AfterAll {
            $sql = "EXEC msdb.dbo.sp_delete_operator @name=N'dbatoolsci_operator'"
            $server.Query($sql)
            $sql = "EXEC msdb.dbo.sp_delete_operator @name=N'dbatoolsci_operator2'"
            $server.Query($sql)
        }

        It "Should return at least two results" {
            $results = Get-DbaAgentOperator -SqlInstance $global:instance2
            $results.Count | Should -BeGreaterOrEqual 2
        }

        It "Should return one result when specifying an operator" {
            $results = Get-DbaAgentOperator -SqlInstance $global:instance2 -Operator dbatoolsci_operator
            $results.Count | Should -Be 1
        }
    }
}
