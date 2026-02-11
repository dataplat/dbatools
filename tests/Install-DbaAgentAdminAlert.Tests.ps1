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

Describe "$CommandName Output" -Tag IntegrationTests {
    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Get-DbaAgentAlert -SqlInstance $TestConfig.InstanceSingle | ForEach-Object {
                Remove-DbaAgentAlert -SqlInstance $TestConfig.InstanceSingle -Alert $PSItem.Name -Confirm:$false -ErrorAction SilentlyContinue
            }

            $splatOutputTest = @{
                SqlInstance      = $TestConfig.InstanceSingle
                Operator         = "dbatoolsci_OutputOp"
                OperatorEmail    = "dbatoolsci_output@ad.local"
                ExcludeSeverity  = 18, 19, 20, 21, 22, 23, 24, 25
                ExcludeMessageId = 824, 825
                EnableException  = $true
            }
            $resultOutput = Install-DbaAgentAdminAlert @splatOutputTest

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            Get-DbaAgentAlert -SqlInstance $TestConfig.InstanceSingle | ForEach-Object {
                Remove-DbaAgentAlert -SqlInstance $TestConfig.InstanceSingle -Alert $PSItem.Name -Confirm:$false -ErrorAction SilentlyContinue
            }
            Get-DbaAgentOperator -SqlInstance $TestConfig.InstanceSingle -Operator "dbatoolsci_OutputOp" | ForEach-Object {
                Remove-DbaAgentOperator -SqlInstance $TestConfig.InstanceSingle -Operator $PSItem.Name -Confirm:$false -ErrorAction SilentlyContinue
            }
        }

        It "Returns output of the documented type" {
            $resultOutput | Should -Not -BeNullOrEmpty
            $resultOutput[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Agent.Alert"
        }

        It "Has the expected default display properties" {
            if (-not $resultOutput) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $resultOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "SqlInstance", "InstanceName", "Name", "Severity", "MessageId")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}