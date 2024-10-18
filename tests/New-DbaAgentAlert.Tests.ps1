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
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have Alert parameter" {
            $CommandUnderTest | Should -HaveParameter Alert -Type System.String -Mandatory:$false
        }
        It "Should have Category parameter" {
            $CommandUnderTest | Should -HaveParameter Category -Type System.String -Mandatory:$false
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.String -Mandatory:$false
        }
        It "Should have Operator parameter" {
            $CommandUnderTest | Should -HaveParameter Operator -Type System.String[] -Mandatory:$false
        }
        It "Should have DelayBetweenResponses parameter" {
            $CommandUnderTest | Should -HaveParameter DelayBetweenResponses -Type System.Int32 -Mandatory:$false
        }
        It "Should have Disabled parameter" {
            $CommandUnderTest | Should -HaveParameter Disabled -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have EventDescriptionKeyword parameter" {
            $CommandUnderTest | Should -HaveParameter EventDescriptionKeyword -Type System.String -Mandatory:$false
        }
        It "Should have EventSource parameter" {
            $CommandUnderTest | Should -HaveParameter EventSource -Type System.String -Mandatory:$false
        }
        It "Should have JobId parameter" {
            $CommandUnderTest | Should -HaveParameter JobId -Type System.String -Mandatory:$false
        }
        It "Should have Severity parameter" {
            $CommandUnderTest | Should -HaveParameter Severity -Type System.Int32 -Mandatory:$false
        }
        It "Should have MessageId parameter" {
            $CommandUnderTest | Should -HaveParameter MessageId -Type System.Int32 -Mandatory:$false
        }
        It "Should have NotificationMessage parameter" {
            $CommandUnderTest | Should -HaveParameter NotificationMessage -Type System.String -Mandatory:$false
        }
        It "Should have PerformanceCondition parameter" {
            $CommandUnderTest | Should -HaveParameter PerformanceCondition -Type System.String -Mandatory:$false
        }
        It "Should have WmiEventNamespace parameter" {
            $CommandUnderTest | Should -HaveParameter WmiEventNamespace -Type System.String -Mandatory:$false
        }
        It "Should have WmiEventQuery parameter" {
            $CommandUnderTest | Should -HaveParameter WmiEventQuery -Type System.String -Mandatory:$false
        }
        It "Should have NotifyMethod parameter" {
            $CommandUnderTest | Should -HaveParameter NotifyMethod -Type System.String -Mandatory:$false
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
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
