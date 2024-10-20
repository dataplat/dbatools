param($ModuleName = 'dbatools')

Describe "New-DbaAgentAlert" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"

        # Mock Get-DbaAgentAlert at the Describe level
        Mock Get-DbaAgentAlert {
            @(
                [PSCustomObject]@{
                    Name = "Test Alert"
                },
                [PSCustomObject]@{
                    Name = "Another Alert"
                }
            )
        }

        # Mock Remove-DbaAgentAlert at the Describe level
        Mock Remove-DbaAgentAlert {}
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaAgentAlert
        }

        It "has the required parameter: <_>" -ForEach $params {
            $params = @(
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
                "EnableException",
                "WhatIf",
                "Confirm"
            )
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Creating a new SQL Server Agent alert" {
        BeforeAll {
            $instance2 = $global:instance2
            $instance3 = $global:instance3
        }

        It 'Should create a new alert' {
            $parms = @{
                SqlInstance           = $instance2
                Alert                 = "Test Alert"
                DelayBetweenResponses = 60
                Disabled              = $false
                NotifyMethod          = "NotifyEmail"
                NotificationMessage   = "Test Notification"
                Severity              = 17
                EnableException       = $true
            }

            Mock New-DbaAgentAlert {
                [PSCustomObject]@{
                    Name                   = $parms.Alert
                    DelayBetweenResponses  = $parms.DelayBetweenResponses
                    IsEnabled              = -not $parms.Disabled
                    Severity               = $parms.Severity
                }
            }

            $alert = New-DbaAgentAlert @parms

            $alert.Name | Should -Be 'Test Alert'
            $alert.DelayBetweenResponses | Should -Be 60
            $alert.IsEnabled | Should -Be $true
            $alert.Severity | Should -Be 17

            Should -Invoke Get-DbaAgentAlert -Times 1 -Exactly -ParameterFilter {
                $SqlInstance -eq $instance2 -and $Alert -eq $parms.Alert
            }
        }

        It 'Should create another new alert' {
            $parms = @{
                SqlInstance           = $instance3
                Alert                 = "Another Alert"
                DelayBetweenResponses = 60
                NotifyMethod          = "NotifyEmail"
                NotificationMessage   = "Test Notification"
                MessageId             = 826
                EnableException       = $true
            }

            Mock New-DbaAgentAlert {
                [PSCustomObject]@{
                    Name                   = $parms.Alert
                    DelayBetweenResponses  = $parms.DelayBetweenResponses
                    IsEnabled              = $true
                    MessageId              = $parms.MessageId
                    Severity               = 0
                }
            }

            $alert = New-DbaAgentAlert @parms

            $alert.Name | Should -Be "Another Alert"
            $alert.DelayBetweenResponses | Should -Be 60
            $alert.IsEnabled | Should -Be $true
            $alert.MessageId | Should -Be 826
            $alert.Severity | Should -Be 0

            Should -Invoke Get-DbaAgentAlert -Times 1 -Exactly -ParameterFilter {
                $SqlInstance -eq $instance3 -and $Alert -eq $parms.Alert
            }
        }
    }
}
