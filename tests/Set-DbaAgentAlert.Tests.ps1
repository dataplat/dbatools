param($ModuleName = 'dbatools')

Describe "Set-DbaAgentAlert" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaAgentAlert
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Alert parameter" {
            $CommandUnderTest | Should -HaveParameter Alert -Type Object[]
        }
        It "Should have NewName parameter" {
            $CommandUnderTest | Should -HaveParameter NewName -Type String
        }
        It "Should have Enabled parameter" {
            $CommandUnderTest | Should -HaveParameter Enabled -Type Switch
        }
        It "Should have Disabled parameter" {
            $CommandUnderTest | Should -HaveParameter Disabled -Type Switch
        }
        It "Should have Force parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Alert[]
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Command usage" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2 -Database master
            $server.Query("EXEC msdb.dbo.sp_add_alert @name=N'dbatoolsci test alert',@message_id=0,@severity=6,@enabled=1,@delay_between_responses=0,@include_event_description_in=0,@category_name=N'[Uncategorized]',@job_id=N'00000000-0000-0000-0000-000000000000'")
        }
        AfterAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2 -Database master
            $server.Query("EXEC msdb.dbo.sp_delete_alert @name=N'dbatoolsci test alert NEW'")
        }

        It "changes new alert to disabled" {
            $results = Set-DbaAgentAlert -SqlInstance $global:instance2 -Alert 'dbatoolsci test alert' -Disabled
            $results.IsEnabled | Should -Be 'False'
        }

        It "changes new alert name to dbatoolsci test alert NEW" {
            $results = Set-DbaAgentAlert -SqlInstance $global:instance2 -Alert 'dbatoolsci test alert' -NewName 'dbatoolsci test alert NEW'
            $results.Name | Should -Be 'dbatoolsci test alert NEW'
        }
    }
}
