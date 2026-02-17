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

            $alert = Install-DbaAgentAdminAlert @splatAlert1 -OutVariable "global:dbatoolsciOutput" | Select-Object -First 1

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

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Agent.Alert]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "SqlInstance",
                "InstanceName",
                "Name",
                "Severity",
                "MessageId",
                "DelayBetweenResponses"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.Agent\.Alert"
        }
    }
}