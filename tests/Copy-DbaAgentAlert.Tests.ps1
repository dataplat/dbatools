#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaAgentAlert",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Copy-DbaAgentAlert
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Alert",
                "ExcludeAlert",
                "IncludeDefaults",
                "Force",
                "EnableException",
                "Confirm",
                "WhatIf"
            )
        }

        It "Has parameter: <_>" -TestCases ($expected | ForEach-Object { @{ Parameter = $PSItem } }) {
            param($Parameter)
            $command | Should -HaveParameter $Parameter
        }

        It "Should have exactly the number of expected parameters ($($expected.Count))" {
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $alert1 = "dbatoolsci test alert"
        $alert2 = "dbatoolsci test alert 2"
        $operatorName = "Dan the man Levitan"
        $operatorEmail = "levitan@dbatools.io"
        $serverInstance2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2 -Database master

        $serverInstance2.Query("EXEC msdb.dbo.sp_add_alert @name=N'$($alert1)',
        @message_id=0,
        @severity=6,
        @enabled=1,
        @delay_between_responses=0,
        @include_event_description_in=0,
        @category_name=N'[Uncategorized]',
        @job_id=N'00000000-0000-0000-0000-000000000000';")

        $serverInstance2.Query("EXEC msdb.dbo.sp_add_alert @name=N'$($alert2)',
        @message_id=0,
        @severity=10,
        @enabled=1,
        @delay_between_responses=0,
        @include_event_description_in=0,
        @job_id=N'00000000-0000-0000-0000-000000000000';")

        $serverInstance2.Query("EXEC msdb.dbo.sp_add_operator
        @name = N'$operatorName',
        @enabled = 1,
        @email_address = N'$operatorEmail' ;")
        $serverInstance2.Query("EXEC msdb.dbo.sp_add_notification   @alert_name = N'$($alert2)',
        @operator_name = N'$operatorName',
        @notification_method = 1 ;")
    }

    AfterAll {
        $serverCleanup2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2 -Database master
        $serverCleanup2.Query("EXEC msdb.dbo.sp_delete_alert @name=N'$($alert1)'")
        $serverCleanup2.Query("EXEC msdb.dbo.sp_delete_alert @name=N'$($alert2)'")
        $serverCleanup2.Query("EXEC msdb.dbo.sp_delete_operator @name = '$($operatorName)'")

        $serverCleanup3 = Connect-DbaInstance -SqlInstance $TestConfig.instance3 -Database master
        $serverCleanup3.Query("EXEC msdb.dbo.sp_delete_alert @name=N'$($alert1)'")
    }

    Context "When copying alerts" {
        It "Copies the sample alert" {
            $splatCopyAlert = @{
                Source      = $TestConfig.instance2
                Destination = $TestConfig.instance3
                Alert       = $alert1
            }
            $results = Copy-DbaAgentAlert @splatCopyAlert
            $results.Name | Should -Be "dbatoolsci test alert", "dbatoolsci test alert"
            $results.Type | Should -Be "Agent Alert", "Agent Alert Notification"
            $results.Status | Should -Be "Successful", "Successful"
        }

        It "Skips alerts where destination is missing the operator" {
            $splatCopySkip = @{
                Source        = $TestConfig.instance2
                Destination   = $TestConfig.instance3
                Alert         = $alert2
                WarningAction = "SilentlyContinue"
            }
            $results = Copy-DbaAgentAlert @splatCopySkip
            $results.Status | Should -Be Skipped
            $results.Type | Should -Be "Agent Alert"
        }

        It "Doesn't overwrite existing alerts" {
            $splatCopyExisting = @{
                Source      = $TestConfig.instance2
                Destination = $TestConfig.instance3
                Alert       = $alert1
            }
            $results = Copy-DbaAgentAlert @splatCopyExisting
            $results.Name | Should -Be "dbatoolsci test alert"
            $results.Status | Should -Be "Skipped"
        }

        It "The newly copied alert exists" {
            $results = Get-DbaAgentAlert -SqlInstance $TestConfig.instance2
            $results.Name | Should -Contain "dbatoolsci test alert"
        }
    }
}
