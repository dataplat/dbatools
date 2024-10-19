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
        
        It "has all the required parameters" {
            $requiredParameters = @(
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
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
