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
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Alert parameter" {
            $CommandUnderTest | Should -HaveParameter Alert
        }
        It "Should have Category parameter" {
            $CommandUnderTest | Should -HaveParameter Category
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have Operator parameter" {
            $CommandUnderTest | Should -HaveParameter Operator
        }
        It "Should have DelayBetweenResponses parameter" {
            $CommandUnderTest | Should -HaveParameter DelayBetweenResponses
        }
        It "Should have Disabled parameter" {
            $CommandUnderTest | Should -HaveParameter Disabled
        }
        It "Should have EventDescriptionKeyword parameter" {
            $CommandUnderTest | Should -HaveParameter EventDescriptionKeyword
        }
        It "Should have EventSource parameter" {
            $CommandUnderTest | Should -HaveParameter EventSource
        }
        It "Should have JobId parameter" {
            $CommandUnderTest | Should -HaveParameter JobId
        }
        It "Should have Severity parameter" {
            $CommandUnderTest | Should -HaveParameter Severity
        }
        It "Should have MessageId parameter" {
            $CommandUnderTest | Should -HaveParameter MessageId
        }
        It "Should have NotificationMessage parameter" {
            $CommandUnderTest | Should -HaveParameter NotificationMessage
        }
        It "Should have PerformanceCondition parameter" {
            $CommandUnderTest | Should -HaveParameter PerformanceCondition
        }
        It "Should have WmiEventNamespace parameter" {
            $CommandUnderTest | Should -HaveParameter WmiEventNamespace
        }
        It "Should have WmiEventQuery parameter" {
            $CommandUnderTest | Should -HaveParameter WmiEventQuery
        }
        It "Should have NotifyMethod parameter" {
            $CommandUnderTest | Should -HaveParameter NotifyMethod
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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
