#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Install-DbaAgentAdminAlert",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Category",
                "Database",
                "Operator",
                "OperatorEmail",
                "DelayBetweenResponses",
                "Disabled",
                "EventDescriptionKeyword",
                "EventSource",
                "JobId",
                "ExcludeSeverity",
                "ExcludeMessageId",
                "NotificationMessage",
                "NotifyMethod",
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

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    BeforeEach {
        # Clean up any existing alerts before each test
        Get-DbaAgentAlert -SqlInstance $TestConfig.instance2, $TestConfig.instance3 | Remove-DbaAgentAlert -Confirm:$false
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Clean up all created alerts
        Get-DbaAgentAlert -SqlInstance $TestConfig.instance2, $TestConfig.instance3 | Remove-DbaAgentAlert -Confirm:$false

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Creating a new SQL Server Agent alert" {
        BeforeAll {
            $splatAlert = @{
                SqlInstance           = $TestConfig.instance2
                DelayBetweenResponses = 60
                Disabled              = $false
                NotifyMethod          = "NotifyEmail"
                NotificationMessage   = "Test Notification"
                Operator              = "Test Operator"
                OperatorEmail         = "dba@ad.local"
                ExcludeSeverity       = 0
                EnableException       = $true
            }
        }

        It "Should create a bunch of new alerts" {
            $alert = Install-DbaAgentAdminAlert @splatAlert | Select-Object -First 1

            # Assert
            $alert.Name | Should -Not -BeNullOrEmpty
            $alert.DelayBetweenResponses | Should -Be 60
            $alert.IsEnabled | Should -Be $true
        }

        It "Should create a bunch of new alerts with ExcludeSeverity" {
            $splatAlertInstance3 = @{
                SqlInstance           = $TestConfig.instance3
                DelayBetweenResponses = 60
                Disabled              = $false
                NotifyMethod          = "NotifyEmail"
                NotificationMessage   = "Test Notification"
                Operator              = "Test Operator"
                OperatorEmail         = "dba@ad.local"
                ExcludeSeverity       = 17
                EnableException       = $true
            }

            $alerts = Install-DbaAgentAdminAlert @splatAlertInstance3

            # Assert
            $alerts.Severity | Should -Not -Contain 17

            Get-DbaAgentAlert -SqlInstance $TestConfig.instance3 | Should -Not -BeNullOrEmpty
        }
    }
}