#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaAgentJobStep",
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
                "Job",
                "ExcludeJob",
                "InputObject",
                "ExcludeDisabledJobs",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Gets a job step" {
        BeforeAll {
            $jobName = "dbatoolsci_job_$(Get-Random)"
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $jobName -StepName dbatoolsci_jobstep1 -Subsystem TransactSql -Command "select 1"
        }

        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName
        }

        It "Successfully gets job when not using Job param" {
            $results = Get-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle
            $results.Name | Should -Contain "dbatoolsci_jobstep1"
        }

        It "Successfully gets job when using Job param" {
            $results = Get-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $jobName
            $results.Name | Should -Contain "dbatoolsci_jobstep1"
        }

        It "Successfully gets job when excluding some jobs" {
            $results = Get-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -ExcludeJob "syspolicy_purge_history"
            $results.Name | Should -Contain "dbatoolsci_jobstep1"
        }

        It "Successfully excludes disabled jobs" {
            $null = Set-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName -Disabled
            $results = Get-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -ExcludeDisabledJobs
            $results.Name | Should -Not -Contain "dbatoolsci_jobstep1"
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $jobName = "dbatoolsci_output_$(Get-Random)"
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $jobName -StepName dbatoolsci_outputstep -Subsystem TransactSql -Command "select 1"
            $result = Get-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $jobName -EnableException
        }

        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Agent.JobStep]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'AgentJob',
                'Name',
                'SubSystem',
                'LastRunDate',
                'LastRunOutcome',
                'State'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}