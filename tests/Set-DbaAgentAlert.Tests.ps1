param($ModuleName = 'dbatools')

Describe "Set-DbaAgentAlert" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaAgentAlert
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Alert",
                "NewName",
                "Enabled",
                "Disabled",
                "Force",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
