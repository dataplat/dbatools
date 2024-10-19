param($ModuleName = 'dbatools')

Describe "Copy-DbaAgentOperator" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $sql = "EXEC msdb.dbo.sp_add_operator @name=N'dbatoolsci_operator', @enabled=1, @pager_days=0"
        $server.Query($sql)
        $sql = "EXEC msdb.dbo.sp_add_operator @name=N'dbatoolsci_operator2', @enabled=1, @pager_days=0"
        $server.Query($sql)
    }

    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $sql = "EXEC msdb.dbo.sp_delete_operator @name=N'dbatoolsci_operator'"
        $server.Query($sql)
        $sql = "EXEC msdb.dbo.sp_delete_operator @name=N'dbatoolsci_operator2'"
        $server.Query($sql)

        $server = Connect-DbaInstance -SqlInstance $global:instance3
        $sql = "EXEC msdb.dbo.sp_delete_operator @name=N'dbatoolsci_operator'"
        $server.Query($sql)
        $sql = "EXEC msdb.dbo.sp_delete_operator @name=N'dbatoolsci_operator2'"
        $server.Query($sql)
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Copy-DbaAgentOperator
        }
        It "Should have Source as a parameter" {
            $CommandUnderTest | Should -HaveParameter Source
        }
        It "Should have SourceSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SourceSqlCredential
        }
        It "Should have Destination as a parameter" {
            $CommandUnderTest | Should -HaveParameter Destination
        }
        It "Should have DestinationSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential
        }
        It "Should have Operator as a parameter" {
            $CommandUnderTest | Should -HaveParameter Operator
        }
        It "Should have ExcludeOperator as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeOperator
        }
        It "Should have Force as a parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command usage" {
        It "Copies operators" {
            $results = Copy-DbaAgentOperator -Source $global:instance2 -Destination $global:instance3 -Operator dbatoolsci_operator, dbatoolsci_operator2
            $results.Count | Should -Be 2
            $results.Status | Should -Be @("Successful", "Successful")
        }

        It "Returns one result that's skipped" {
            $results = Copy-DbaAgentOperator -Source $global:instance2 -Destination $global:instance3 -Operator dbatoolsci_operator
            $results.Count | Should -Be 1
            $results.Status | Should -Be "Skipped"
        }
    }
}
