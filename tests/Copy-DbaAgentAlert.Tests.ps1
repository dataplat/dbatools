#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaAgentAlert",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
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

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Set variables for test alerts and operator
        $alert1        = "dbatoolsci test alert"
        $alert2        = "dbatoolsci test alert 2"
        $operatorName  = "Dan the man Levitan"
        $operatorEmail = "levitan@dbatools.io"

        # Connect to instance and create test objects
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

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Clean up test objects
        $serverCleanup2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2 -Database master
        $serverCleanup2.Query("EXEC msdb.dbo.sp_delete_alert @name=N'$($alert1)'")
        $serverCleanup2.Query("EXEC msdb.dbo.sp_delete_alert @name=N'$($alert2)'")
        $serverCleanup2.Query("EXEC msdb.dbo.sp_delete_operator @name = '$($operatorName)'")

        $serverCleanup3 = Connect-DbaInstance -SqlInstance $TestConfig.instance3 -Database master
        $serverCleanup3.Query("EXEC msdb.dbo.sp_delete_alert @name=N'$($alert1)'")

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
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
            $results.Status | Should -Be "Skipped"
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