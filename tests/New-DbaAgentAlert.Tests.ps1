param($ModuleName = 'dbatools')

Describe "New-DbaAgentAlert" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaAgentAlert
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Alert parameter" {
            $CommandUnderTest | Should -HaveParameter Alert -Type String -Not -Mandatory
        }
        It "Should have Category parameter" {
            $CommandUnderTest | Should -HaveParameter Category -Type String -Not -Mandatory
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String -Not -Mandatory
        }
        It "Should have Operator parameter" {
            $CommandUnderTest | Should -HaveParameter Operator -Type String[] -Not -Mandatory
        }
        It "Should have DelayBetweenResponses parameter" {
            $CommandUnderTest | Should -HaveParameter DelayBetweenResponses -Type Int32 -Not -Mandatory
        }
        It "Should have Disabled parameter" {
            $CommandUnderTest | Should -HaveParameter Disabled -Type SwitchParameter -Not -Mandatory
        }
        It "Should have EventDescriptionKeyword parameter" {
            $CommandUnderTest | Should -HaveParameter EventDescriptionKeyword -Type String -Not -Mandatory
        }
        It "Should have EventSource parameter" {
            $CommandUnderTest | Should -HaveParameter EventSource -Type String -Not -Mandatory
        }
        It "Should have JobId parameter" {
            $CommandUnderTest | Should -HaveParameter JobId -Type String -Not -Mandatory
        }
        It "Should have Severity parameter" {
            $CommandUnderTest | Should -HaveParameter Severity -Type Int32 -Not -Mandatory
        }
        It "Should have MessageId parameter" {
            $CommandUnderTest | Should -HaveParameter MessageId -Type Int32 -Not -Mandatory
        }
        It "Should have NotificationMessage parameter" {
            $CommandUnderTest | Should -HaveParameter NotificationMessage -Type String -Not -Mandatory
        }
        It "Should have PerformanceCondition parameter" {
            $CommandUnderTest | Should -HaveParameter PerformanceCondition -Type String -Not -Mandatory
        }
        It "Should have WmiEventNamespace parameter" {
            $CommandUnderTest | Should -HaveParameter WmiEventNamespace -Type String -Not -Mandatory
        }
        It "Should have WmiEventQuery parameter" {
            $CommandUnderTest | Should -HaveParameter WmiEventQuery -Type String -Not -Mandatory
        }
        It "Should have NotifyMethod parameter" {
            $CommandUnderTest | Should -HaveParameter NotifyMethod -Type String -Not -Mandatory
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
        }
    }

    Context "Creating a new SQL Server Agent alert" {
        BeforeAll {
            $script:instance2 = "instance2"
            $script:instance3 = "instance3"
        }

        BeforeEach {
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
            Mock Remove-DbaAgentAlert {}
        }

        AfterAll {
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
            Mock Remove-DbaAgentAlert {}
        }

        It 'Should create a new alert' {
            $parms = @{
                SqlInstance           = $script:instance2
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
                $SqlInstance -eq $script:instance2 -and $Alert -eq $parms.Alert
            }
        }

        It 'Should create another new alert' {
            $parms = @{
                SqlInstance           = $script:instance3
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
                $SqlInstance -eq $script:instance3 -and $Alert -eq $parms.Alert
            }
        }
    }
}
