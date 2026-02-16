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
            $agentResults = Get-DbaAgentServer -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"
            $agentResults.Count | Should -BeExactly 1
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Agent.JobServer]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
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
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.Agent\.JobServer"
        }
    }
}