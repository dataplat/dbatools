#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaAgentLog",
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
                "LogNumber",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command gets agent log" {
        It "Returns results" {
            $results = Get-DbaAgentLog -SqlInstance $TestConfig.InstanceSingle

            $results | Should -Not -BeNullOrEmpty
            ($results | Select-Object -First 1).LogDate | Should -BeOfType DateTime
        }
    }

    Context "Command gets current agent log using LogNumber parameter" {
        BeforeAll {
            $results = Get-DbaAgentLog -SqlInstance $TestConfig.InstanceSingle -LogNumber 0
        }

        It "Results are not empty" {
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaAgentLog -SqlInstance $TestConfig.InstanceSingle -EnableException
        }

        It "Returns the documented output type" {
            $result[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Agent.JobServer+LogFileEntry]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'LogDate',
                'ProcessInfo',
                'Text'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has ComputerName, InstanceName, and SqlInstance added by dbatools" {
            $result[0].ComputerName | Should -Not -BeNullOrEmpty
            $result[0].InstanceName | Should -Not -BeNullOrEmpty
            $result[0].SqlInstance | Should -Not -BeNullOrEmpty
        }
    }
}