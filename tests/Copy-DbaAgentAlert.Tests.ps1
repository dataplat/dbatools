#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaAgentAlert",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
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
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Set variables for test alerts and operator
        $alert1 = "dbatoolsci test alert"
        $alert2 = "dbatoolsci test alert 2"
        $outputAlertName = "dbatoolsci output alert"
        $operatorName = "Dan the man Levitan"
        $operatorEmail = "levitan@dbatools.io"

        # Connect to instance and create test objects
        $serverInstanceSingle = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -Database master

        $serverInstanceSingle.Query("EXEC msdb.dbo.sp_add_alert @name=N'$($alert1)',
        @message_id=0,
        @severity=6,
        @enabled=1,
        @delay_between_responses=0,
        @include_event_description_in=0,
        @category_name=N'[Uncategorized]',
        @job_id=N'00000000-0000-0000-0000-000000000000';")

        $serverInstanceSingle.Query("EXEC msdb.dbo.sp_add_alert @name=N'$($alert2)',
        @message_id=0,
        @severity=10,
        @enabled=1,
        @delay_between_responses=0,
        @include_event_description_in=0,
        @job_id=N'00000000-0000-0000-0000-000000000000';")

        $serverInstanceSingle.Query("EXEC msdb.dbo.sp_add_alert @name=N'$($outputAlertName)',
        @message_id=0,
        @severity=7,
        @enabled=1,
        @delay_between_responses=0,
        @include_event_description_in=0,
        @category_name=N'[Uncategorized]',
        @job_id=N'00000000-0000-0000-0000-000000000000';")

        $serverInstanceSingle.Query("EXEC msdb.dbo.sp_add_operator
        @name = N'$operatorName',
        @enabled = 1,
        @email_address = N'$operatorEmail' ;")

        $serverInstanceSingle.Query("EXEC msdb.dbo.sp_add_notification   @alert_name = N'$($alert2)',
        @operator_name = N'$operatorName',
        @notification_method = 1 ;")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Clean up test objects
        $serverCleanup2 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -Database master
        $serverCleanup2.Query("EXEC msdb.dbo.sp_delete_alert @name=N'$($alert1)'")
        $serverCleanup2.Query("EXEC msdb.dbo.sp_delete_alert @name=N'$($alert2)'")
        $serverCleanup2.Query("EXEC msdb.dbo.sp_delete_alert @name=N'$($outputAlertName)'") 2>$null
        $serverCleanup2.Query("EXEC msdb.dbo.sp_delete_operator @name = '$($operatorName)'")

        $serverCleanup3 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -Database master
        $serverCleanup3.Query("EXEC msdb.dbo.sp_delete_alert @name=N'$($alert1)'")
        $serverCleanup3.Query("EXEC msdb.dbo.sp_delete_alert @name=N'$($outputAlertName)'") 2>$null

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When copying alerts" {
        It "Copies the sample alert" {
            $splatCopyAlert = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Alert       = $alert1
            }
            $results = Copy-DbaAgentAlert @splatCopyAlert
            $results.Name | Should -Be "dbatoolsci test alert", "dbatoolsci test alert"
            $results.Type | Should -Be "Agent Alert", "Agent Alert Notification"
            $results.Status | Should -Be "Successful", "Successful"
        }

        It "Skips alerts where destination is missing the operator" {
            $splatCopySkip = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                Alert         = $alert2
                WarningAction = "SilentlyContinue"
            }
            $results = Copy-DbaAgentAlert @splatCopySkip
            $results.Status | Should -Be "Skipped"
            $results.Type | Should -Be "Agent Alert"
        }

        It "Doesn't overwrite existing alerts" {
            $splatCopyExisting = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Alert       = $alert1
            }
            $results = Copy-DbaAgentAlert @splatCopyExisting
            $results.Name | Should -Be "dbatoolsci test alert"
            $results.Status | Should -Be "Skipped"
        }

        It "The newly copied alert exists" {
            $results = Get-DbaAgentAlert -SqlInstance $TestConfig.InstanceCopy1
            $results.Name | Should -Contain "dbatoolsci test alert"
        }

        It "Returns output of the documented type" {
            $splatCopyOutputAlert = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Alert       = $outputAlertName
            }
            $result = Copy-DbaAgentAlert @splatCopyOutputAlert
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.TypeNames | Should -Contain "dbatools.MigrationObject"
        }

        It "Has the expected default display properties" {
            $splatCopyOutputAlert = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Alert       = $outputAlertName
            }
            $result = Copy-DbaAgentAlert @splatCopyOutputAlert
            $result | Should -Not -BeNullOrEmpty
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}