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
        It "Should get 1 agent server" {
            $agentResults = Get-DbaAgentServer -SqlInstance $TestConfig.InstanceSingle
            $agentResults.Count | Should -BeExactly 1
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaAgentServer -SqlInstance $TestConfig.instance1 -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Agent.JobServer]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'AgentDomainGroup',
                'AgentLogLevel',
                'AgentMailType',
                'AgentShutdownWaitTime',
                'ErrorLogFile',
                'IdleCpuDuration',
                'IdleCpuPercentage',
                'IsCpuPollingEnabled',
                'JobServerType',
                'LoginTimeout',
                'JobHistoryIsEnabled',
                'MaximumHistoryRows',
                'MaximumJobHistoryRows',
                'MsxAccountCredentialName',
                'MsxAccountName',
                'MsxServerName',
                'Name',
                'NetSendRecipient',
                'ServiceAccount',
                'ServiceStartMode',
                'SqlAgentAutoStart',
                'SqlAgentMailProfile',
                'SqlAgentRestart',
                'SqlServerRestart',
                'State',
                'SysAdminOnly'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has dbatools-added properties" {
            $result.PSObject.Properties.Name | Should -Contain 'ComputerName' -Because "dbatools adds ComputerName via Add-Member"
            $result.PSObject.Properties.Name | Should -Contain 'InstanceName' -Because "dbatools adds InstanceName via Add-Member"
            $result.PSObject.Properties.Name | Should -Contain 'SqlInstance' -Because "dbatools adds SqlInstance via Add-Member"
            $result.PSObject.Properties.Name | Should -Contain 'JobHistoryIsEnabled' -Because "dbatools adds JobHistoryIsEnabled as computed property"
        }
    }
}