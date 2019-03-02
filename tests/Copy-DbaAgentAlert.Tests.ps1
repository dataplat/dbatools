$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'Source', 'SourceSqlCredential', 'Destination', 'DestinationSqlCredential', 'Alert', 'ExcludeAlert', 'IncludeDefaults', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $alert1 = 'dbatoolsci test alert'
        $alert2 = 'dbatoolsci test alert 2'
        $operatorName = 'Dan the man Levitan'
        $operatorEmail = 'levitan@dbatools.io'
        $server = Connect-DbaInstance -SqlInstance $script:instance2 -Database master

        $server.Query("EXEC msdb.dbo.sp_add_alert @name=N'$($alert1)',
        @message_id=0,
        @severity=6,
        @enabled=1,
        @delay_between_responses=0,
        @include_event_description_in=0,
        @category_name=N'[Uncategorized]',
        @job_id=N'00000000-0000-0000-0000-000000000000';")

        $server.Query("EXEC msdb.dbo.sp_add_alert @name=N'$($alert2)',
        @message_id=0,
        @severity=10,
        @enabled=1,
        @delay_between_responses=0,
        @include_event_description_in=0,
        @job_id=N'00000000-0000-0000-0000-000000000000';")

        $server.Query("EXEC msdb.dbo.sp_add_operator
        @name = N'$operatorName',
        @enabled = 1,
        @email_address = N'$operatorEmail' ;")
        $server.Query("EXEC msdb.dbo.sp_add_notification   @alert_name = N'$($alert2)',
        @operator_name = N'$operatorName',
        @notification_method = 1 ;")
    }
    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2 -Database master
        $server.Query("EXEC msdb.dbo.sp_delete_alert @name=N'$($alert1)'")
        $server.Query("EXEC msdb.dbo.sp_delete_alert @name=N'$($alert2)'")
        $server.Query("EXEC msdb.dbo.sp_delete_operator @name = '$($operatorName)'")

        $server = Connect-DbaInstance -SqlInstance $script:instance3 -Database master
        $server.Query("EXEC msdb.dbo.sp_delete_alert @name=N'$($alert1)'")
    }

    It "Copies the sample alert" {
        $results = Copy-DbaAgentAlert -Source $script:instance2 -Destination $script:instance3 -Alert $alert1
        $results.Name -eq 'dbatoolsci test alert', 'dbatoolsci test alert'
        $results.Status -eq 'Successful', 'Successful'
    }

    It "Skips alerts where destination is missing the operator" {
        $results = Copy-DbaAgentAlert -Source $script:instance2 -Destination $script:instance3 -Alert $alert2 -WarningVariable warningInfo -WarningAction SilentlyContinue
        $results.Status -eq 'Skipped', 'Skipped'
    }

    It "Doesn't overwrite existing alerts" {
        $results = Copy-DbaAgentAlert -Source $script:instance2 -Destination $script:instance3 -Alert $alert1
        $results.Name -eq 'dbatoolsci test alert'
        $results.Status -eq 'Skipped'
    }

    It "The newly copied alert exists" {
        $results = Get-DbaAgentAlert -SqlInstance $script:instance2
        $results.Name -contains 'dbatoolsci test alert'
    }
}