param($ModuleName = 'dbatools')

Describe "Copy-DbaAgentOperator" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Copy-DbaAgentOperator
        }
        It "Should have Source as a parameter" {
            $CommandUnderTest | Should -HaveParameter Source -Type DbaInstanceParameter
        }
        It "Should have SourceSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SourceSqlCredential -Type PSCredential
        }
        It "Should have Destination as a parameter" {
            $CommandUnderTest | Should -HaveParameter Destination -Type DbaInstanceParameter[]
        }
        It "Should have DestinationSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential -Type PSCredential
        }
        It "Should have Operator as a parameter" {
            $CommandUnderTest | Should -HaveParameter Operator -Type Object[]
        }
        It "Should have ExcludeOperator as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeOperator -Type Object[]
        }
        It "Should have Force as a parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type SwitchParameter
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Command usage" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $sql = "EXEC msdb.dbo.sp_add_operator @name=N'dbatoolsci_operator', @enabled=1, @pager_days=0"
            $server.Query($sql)
            $sql = "EXEC msdb.dbo.sp_add_operator @name=N'dbatoolsci_operator2', @enabled=1, @pager_days=0"
            $server.Query($sql)
        }

        AfterAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $sql = "EXEC msdb.dbo.sp_delete_operator @name=N'dbatoolsci_operator'"
            $server.Query($sql)
            $sql = "EXEC msdb.dbo.sp_delete_operator @name=N'dbatoolsci_operator2'"
            $server.Query($sql)

            $server = Connect-DbaInstance -SqlInstance $script:instance3
            $sql = "EXEC msdb.dbo.sp_delete_operator @name=N'dbatoolsci_operator'"
            $server.Query($sql)
            $sql = "EXEC msdb.dbo.sp_delete_operator @name=N'dbatoolsci_operator2'"
            $server.Query($sql)
        }

        It "Copies operators" {
            $results = Copy-DbaAgentOperator -Source $script:instance2 -Destination $script:instance3 -Operator dbatoolsci_operator, dbatoolsci_operator2
            $results.Count | Should -Be 2
            $results.Status | Should -Be @("Successful", "Successful")
        }

        It "Returns one result that's skipped" {
            $results = Copy-DbaAgentOperator -Source $script:instance2 -Destination $script:instance3 -Operator dbatoolsci_operator
            $results.Status | Should -Be "Skipped"
        }
    }
}
