$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2 -Database master
        $server.Query("EXEC msdb.dbo.sp_add_alert @name=N'dbatoolsci test alert',
        @message_id=0,
        @severity=6,
        @enabled=1,
        @delay_between_responses=0,
        @include_event_description_in=0,
        @category_name=N'[Uncategorized]',
        @job_id=N'00000000-0000-0000-0000-000000000000'")
    }
    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2 -Database master
        $server.Query("EXEC msdb.dbo.sp_delete_alert @name=N'dbatoolsci test alert'")
        $server = Connect-DbaInstance -SqlInstance $script:instance3 -Database master
        $server.Query("EXEC msdb.dbo.sp_delete_alert @name=N'dbatoolsci test alert'")
    }
    
    It "copies the sample alert" {
        $results = Copy-DbaAgentAlert -Source $script:instance2 -Destination $script:instance3 -Alert 'dbatoolsci test alert'
        $results.Name -eq 'dbatoolsci test alert', 'dbatoolsci test alert'
        $results.Status -eq 'Successful', 'Successful'
    }
    
    It "doesn't overwrite existing alerts" {
        $results = Copy-DbaAgentAlert -Source $script:instance2 -Destination $script:instance3 -Alert 'dbatoolsci test alert'
        $results.Name -eq 'dbatoolsci test alert'
        $results.Status -eq 'Skipped'
    }
    
    It "the newly copied alert exists" {
        $results = Get-DbaAgentAlert -SqlInstance $script:instance2
        $results.Name -contains 'dbatoolsci test alert'
    }
}