param($ModuleName = 'dbatools')

Describe "Install-DbaAgentAdminAlert" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Install-DbaAgentAdminAlert
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Category as a parameter" {
            $CommandUnderTest | Should -HaveParameter Category
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have Operator as a parameter" {
            $CommandUnderTest | Should -HaveParameter Operator
        }
        It "Should have OperatorEmail as a parameter" {
            $CommandUnderTest | Should -HaveParameter OperatorEmail
        }
        It "Should have DelayBetweenResponses as a parameter" {
            $CommandUnderTest | Should -HaveParameter DelayBetweenResponses
        }
        It "Should have Disabled as a parameter" {
            $CommandUnderTest | Should -HaveParameter Disabled
        }
        It "Should have EventDescriptionKeyword as a parameter" {
            $CommandUnderTest | Should -HaveParameter EventDescriptionKeyword
        }
        It "Should have EventSource as a parameter" {
            $CommandUnderTest | Should -HaveParameter EventSource
        }
        It "Should have JobId as a parameter" {
            $CommandUnderTest | Should -HaveParameter JobId
        }
        It "Should have ExcludeSeverity as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSeverity
        }
        It "Should have ExcludeMessageId as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeMessageId
        }
        It "Should have NotificationMessage as a parameter" {
            $CommandUnderTest | Should -HaveParameter NotificationMessage
        }
        It "Should have NotifyMethod as a parameter" {
            $CommandUnderTest | Should -HaveParameter NotifyMethod
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $global:instances = @($global:instance2, $global:instance3)
        }

        BeforeEach {
            foreach ($instance in $global:instances) {
                Get-DbaAgentAlert -SqlInstance $instance | Remove-DbaAgentAlert -Confirm:$false
            }
        }

        Context 'Creating a new SQL Server Agent alert' {
            It 'Should create a bunch of new alerts on instance2' {
                $parms = @{
                    SqlInstance           = $global:instance2
                    DelayBetweenResponses = 60
                    Disabled              = $false
                    NotifyMethod          = "NotifyEmail"
                    NotificationMessage   = "Test Notification"
                    Operator              = "Test Operator"
                    OperatorEmail         = "dba@ad.local"
                    ExcludeSeverity       = 0
                    EnableException       = $true
                }

                $alert = Install-DbaAgentAdminAlert @parms | Select-Object -First 1

                $alert.Name | Should -Not -BeNullOrEmpty
                $alert.DelayBetweenResponses | Should -Be 60
                $alert.IsEnabled | Should -Be $true
            }

            It 'Should create a bunch of new alerts on instance3' {
                $parms = @{
                    SqlInstance           = $global:instance3
                    DelayBetweenResponses = 60
                    Disabled              = $false
                    NotifyMethod          = "NotifyEmail"
                    NotificationMessage   = "Test Notification"
                    Operator              = "Test Operator"
                    OperatorEmail         = "dba@ad.local"
                    ExcludeSeverity       = 17
                    EnableException       = $true
                }

                $alerts = Install-DbaAgentAdminAlert @parms

                $alerts.Severity | Should -Not -Contain 17
                Get-DbaAgentAlert -SqlInstance $global:instance3 | Should -Not -BeNullOrEmpty
            }
        }
    }
}
