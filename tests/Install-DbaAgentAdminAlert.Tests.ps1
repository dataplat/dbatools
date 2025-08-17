#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Install-DbaAgentAdminAlert",
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
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
    }

    BeforeEach {
        Get-DbaAgentAlert -SqlInstance $TestConfig.instance2, $TestConfig.instance3 | Remove-DbaAgentAlert -Confirm:$false
    }

    AfterAll {
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        Get-DbaAgentAlert -SqlInstance $TestConfig.instance2, $TestConfig.instance3 | Remove-DbaAgentAlert -Confirm:$false -ErrorAction SilentlyContinue
    }

    Context "Creating a new SQL Server Agent alert" {
        It "Should create a bunch of new alerts with specified parameters" {
            $splatAlert1 = @{
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

            $alert = Install-DbaAgentAdminAlert @splatAlert1 | Select-Object -First 1

            # Assert
            $alert.Name | Should -Not -BeNullOrEmpty
            $alert.DelayBetweenResponses | Should -Be 60
            $alert.IsEnabled | Should -Be $true
        }

        It "Should create alerts excluding specified severity level" {
            $splatAlert2 = @{
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

            $alerts = Install-DbaAgentAdminAlert @splatAlert2

            # Assert
            $alerts.Severity | Should -Not -Contain 17

            Get-DbaAgentAlert -SqlInstance $TestConfig.instance3 | Should -Not -BeNullOrEmpty
        }
    }
}