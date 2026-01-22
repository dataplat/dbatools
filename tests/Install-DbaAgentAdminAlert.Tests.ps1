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
        Get-DbaAgentAlert -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 | Remove-DbaAgentAlert
    }

    AfterAll {
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        Get-DbaAgentAlert -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 | Remove-DbaAgentAlert -ErrorAction SilentlyContinue
    }

    Context "Output Validation" {
        BeforeAll {
            $splatAlert = @{
                SqlInstance           = $TestConfig.InstanceMulti1
                DelayBetweenResponses = 60
                Disabled              = $false
                NotifyMethod          = "NotifyEmail"
                NotificationMessage   = "Test Notification"
                Operator              = "Test Operator"
                OperatorEmail         = "dba@ad.local"
                ExcludeSeverity       = 0
                EnableException       = $true
            }
            $result = Install-DbaAgentAdminAlert @splatAlert | Select-Object -First 1
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Agent.Alert]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "ComputerName",
                "SqlInstance",
                "InstanceName",
                "Name",
                "Severity",
                "MessageId",
                "DelayBetweenResponses"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }

    Context "Output with -Category" {
        BeforeAll {
            $splatAlert = @{
                SqlInstance           = $TestConfig.InstanceMulti1
                Category              = "Test Category"
                DelayBetweenResponses = 60
                Disabled              = $false
                NotifyMethod          = "NotifyEmail"
                Operator              = "Test Operator"
                OperatorEmail         = "dba@ad.local"
                ExcludeSeverity       = 0
                EnableException       = $true
            }
            $result = Install-DbaAgentAdminAlert @splatAlert | Select-Object -First 1
        }

        It "Includes CategoryName property when -Category specified" {
            $result.PSObject.Properties.Name | Should -Contain "CategoryName"
        }
    }

    Context "Output with -JobId" {
        BeforeAll {
            $splatJob = @{
                SqlInstance     = $TestConfig.InstanceMulti1
                Job             = "Test Job For Alert"
                EnableException = $true
            }
            $job = New-DbaAgentJob @splatJob

            $splatAlert = @{
                SqlInstance           = $TestConfig.InstanceMulti1
                JobId                 = $job.JobID
                DelayBetweenResponses = 60
                Disabled              = $false
                NotifyMethod          = "NotifyEmail"
                Operator              = "Test Operator"
                OperatorEmail         = "dba@ad.local"
                ExcludeSeverity       = 0
                EnableException       = $true
            }
            $result = Install-DbaAgentAdminAlert @splatAlert | Select-Object -First 1
        }

        AfterAll {
            Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti1 -Job "Test Job For Alert" -Confirm:$false
        }

        It "Includes JobName property when -JobId specified" {
            $result.PSObject.Properties.Name | Should -Contain "JobName"
        }
    }

    Context "Creating a new SQL Server Agent alert" {
        It "Should create a bunch of new alerts with specified parameters" {
            $splatAlert1 = @{
                SqlInstance           = $TestConfig.InstanceMulti1
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
                SqlInstance           = $TestConfig.InstanceMulti2
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

            Get-DbaAgentAlert -SqlInstance $TestConfig.InstanceMulti2 | Should -Not -BeNullOrEmpty
        }
    }
}