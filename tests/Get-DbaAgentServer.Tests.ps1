#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaAgentServer",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When getting server agent" {
        BeforeAll {
            $agentResults = Get-DbaAgentServer -SqlInstance $TestConfig.InstanceSingle
        }

        It "Should get 1 agent server" {
            $agentResults.Count | Should -BeExactly 1
        }

        It "Returns output of the documented type" {
            $agentResults | Should -Not -BeNullOrEmpty
            $agentResults[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Agent.JobServer"
        }

        It "Has the expected default display properties" {
            $defaultProps = $agentResults[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "AgentDomainGroup",
                "AgentLogLevel",
                "AgentMailType",
                "AgentShutdownWaitTime",
                "ErrorLogFile",
                "IdleCpuDuration",
                "IdleCpuPercentage",
                "IsCpuPollingEnabled",
                "JobServerType",
                "LoginTimeout",
                "JobHistoryIsEnabled",
                "MaximumHistoryRows",
                "MaximumJobHistoryRows",
                "MsxAccountCredentialName",
                "MsxAccountName",
                "MsxServerName",
                "Name",
                "NetSendRecipient",
                "ServiceAccount",
                "ServiceStartMode",
                "SqlAgentAutoStart",
                "SqlAgentMailProfile",
                "SqlAgentRestart",
                "SqlServerRestart",
                "State",
                "SysAdminOnly"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}