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
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Microsoft.SqlServer.Management.Smo.DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have Category as a parameter" {
            $CommandUnderTest | Should -HaveParameter Category -Type System.String
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.String
        }
        It "Should have Operator as a parameter" {
            $CommandUnderTest | Should -HaveParameter Operator -Type System.String
        }
        It "Should have OperatorEmail as a parameter" {
            $CommandUnderTest | Should -HaveParameter OperatorEmail -Type System.String
        }
        It "Should have DelayBetweenResponses as a parameter" {
            $CommandUnderTest | Should -HaveParameter DelayBetweenResponses -Type System.Int32
        }
        It "Should have Disabled as a parameter" {
            $CommandUnderTest | Should -HaveParameter Disabled -Type System.Management.Automation.SwitchParameter
        }
        It "Should have EventDescriptionKeyword as a parameter" {
            $CommandUnderTest | Should -HaveParameter EventDescriptionKeyword -Type System.String
        }
        It "Should have EventSource as a parameter" {
            $CommandUnderTest | Should -HaveParameter EventSource -Type System.String
        }
        It "Should have JobId as a parameter" {
            $CommandUnderTest | Should -HaveParameter JobId -Type System.String
        }
        It "Should have ExcludeSeverity as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSeverity -Type System.Int32[]
        }
        It "Should have ExcludeMessageId as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeMessageId -Type System.Int32[]
        }
        It "Should have NotificationMessage as a parameter" {
            $CommandUnderTest | Should -HaveParameter NotificationMessage -Type System.String
        }
        It "Should have NotifyMethod as a parameter" {
            $CommandUnderTest | Should -HaveParameter NotifyMethod -Type System.String
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
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
