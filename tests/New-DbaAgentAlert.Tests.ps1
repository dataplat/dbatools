#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaAgentAlert",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Alert",
                "Category",
                "Database",
                "Operator",
                "DelayBetweenResponses",
                "Disabled",
                "EventDescriptionKeyword",
                "EventSource",
                "JobId",
                "Severity",
                "MessageId",
                "NotificationMessage",
                "PerformanceCondition",
                "WmiEventNamespace",
                "WmiEventQuery",
                "NotifyMethod",
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

        # Set test alert names for cleanup tracking
        $testAlertNames = @("Test Alert", "Another Alert")

        # Clean up any existing test alerts before starting
        Get-DbaAgentAlert -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Alert $testAlertNames -ErrorAction SilentlyContinue | Remove-DbaAgentAlert -ErrorAction SilentlyContinue

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Clean up all test alerts created during testing
        Get-DbaAgentAlert -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Alert $testAlertNames -ErrorAction SilentlyContinue | Remove-DbaAgentAlert -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Creating a new SQL Server Agent alert" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $outputAlertName = "dbatoolsci_outputalert_$(Get-Random)"
            # Clean up in case it exists from a previous run
            Get-DbaAgentAlert -SqlInstance $TestConfig.InstanceMulti1 -Alert $outputAlertName -ErrorAction SilentlyContinue | Remove-DbaAgentAlert -Confirm:$false -ErrorAction SilentlyContinue
            $splatOutputAlert = @{
                SqlInstance           = $TestConfig.InstanceMulti1
                Alert                 = $outputAlertName
                Severity              = 22
                DelayBetweenResponses = 60
                EnableException       = $true
            }
            $script:outputResult = New-DbaAgentAlert @splatOutputAlert

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        BeforeEach {
            # Clean up alerts before each test to ensure clean state
            Get-DbaAgentAlert -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Alert $testAlertNames -ErrorAction SilentlyContinue | Remove-DbaAgentAlert -ErrorAction SilentlyContinue
        }

        AfterAll {
            Get-DbaAgentAlert -SqlInstance $TestConfig.InstanceMulti1 -Alert $outputAlertName -ErrorAction SilentlyContinue | Remove-DbaAgentAlert -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "Should create a new alert with severity" {
            $splatAlert = @{
                SqlInstance           = $TestConfig.InstanceMulti1
                Alert                 = "Test Alert"
                DelayBetweenResponses = 60
                Disabled              = $false
                NotifyMethod          = "NotifyEmail"
                NotificationMessage   = "Test Notification"
                Severity              = 17
                EnableException       = $true
            }

            $alert = New-DbaAgentAlert @splatAlert

            # Assert
            $alert.Name | Should -Be "Test Alert"
            $alert.DelayBetweenResponses | Should -Be 60
            $alert.IsEnabled | Should -Be $true
            $alert.Severity | Should -Be 17

            Get-DbaAgentAlert -SqlInstance $TestConfig.InstanceMulti1 -Alert $splatAlert.Alert | Should -Not -BeNullOrEmpty
        }

        It "Should create a new alert with MessageId" {
            $splatMessageAlert = @{
                SqlInstance           = $TestConfig.InstanceMulti2
                Alert                 = "Another Alert"
                DelayBetweenResponses = 60
                NotifyMethod          = "NotifyEmail"
                NotificationMessage   = "Test Notification"
                MessageId             = 826
                EnableException       = $true
            }

            $alert = New-DbaAgentAlert @splatMessageAlert

            # Assert
            $alert.Name | Should -Be "Another Alert"
            $alert.DelayBetweenResponses | Should -Be 60
            $alert.IsEnabled | Should -Be $true
            $alert.MessageId | Should -Be 826
            $alert.Severity | Should -Be 0

            Get-DbaAgentAlert -SqlInstance $TestConfig.InstanceMulti2 -Alert $splatMessageAlert.Alert | Should -Not -BeNullOrEmpty
        }

        It "Returns output of the documented type" {
            $script:outputResult | Should -Not -BeNullOrEmpty
            $script:outputResult[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Agent.Alert"
        }

        It "Has the expected default display properties" {
            if (-not $script:outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $script:outputResult[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "SqlInstance", "InstanceName", "Name", "ID", "JobName", "AlertType", "CategoryName", "Severity", "MessageId", "IsEnabled", "DelayBetweenResponses", "LastRaised", "OccurrenceCount")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}