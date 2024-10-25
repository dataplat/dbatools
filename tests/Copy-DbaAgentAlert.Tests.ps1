#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param($ModuleName = "dbatools")
$global:TestConfig = Get-TestConfig

Describe "Copy-DbaAgentAlert" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Copy-DbaAgentAlert
            $expectedParameters = $TestConfig.CommonParameters

            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Alert",
                "ExcludeAlert",
                "IncludeDefaults",
                "Force",
                "EnableException"
            )
        }

        It "Has parameter: <_>" -ForEach $expectedParameters {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters" {
            $actualParameters = $command.Parameters.Keys | Where-Object { $PSItem -notin "WhatIf", "Confirm" }
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $actualParameters | Should -BeNullOrEmpty
        }
    }
}

Describe "Copy-DbaAgentAlert" -Tag "IntegrationTests" {
    BeforeAll {
        $alert1 = 'dbatoolsci test alert'
        $alert2 = 'dbatoolsci test alert 2'
        $operatorName = 'Dan the man Levitan'
        $operatorEmail = 'levitan@dbatools.io'
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2 -Database master

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
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2 -Database master
        $server.Query("EXEC msdb.dbo.sp_delete_alert @name=N'$($alert1)'")
        $server.Query("EXEC msdb.dbo.sp_delete_alert @name=N'$($alert2)'")
        $server.Query("EXEC msdb.dbo.sp_delete_operator @name = '$($operatorName)'")

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance3 -Database master
        $server.Query("EXEC msdb.dbo.sp_delete_alert @name=N'$($alert1)'")
    }

    Context "When copying alerts" {
        It "Copies the sample alert" {
            $results = Copy-DbaAgentAlert -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -Alert $alert1
            $results.Name | Should -Be @('dbatoolsci test alert', 'dbatoolsci test alert')
            $results.Status | Should -Be @('Successful', 'Successful')
        }

        It "Skips alerts where destination is missing the operator" {
            $results = Copy-DbaAgentAlert -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -Alert $alert2 -WarningAction SilentlyContinue
            $results.Status | Should -Be @('Skipped', 'Skipped')
        }

        It "Doesn't overwrite existing alerts" {
            $results = Copy-DbaAgentAlert -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -Alert $alert1
            $results.Name | Should -Be 'dbatoolsci test alert'
            $results.Status | Should -Be 'Skipped'
        }

        It "The newly copied alert exists" {
            $results = Get-DbaAgentAlert -SqlInstance $TestConfig.instance2
            $results.Name | Should -Contain 'dbatoolsci test alert'
        }
    }
}
