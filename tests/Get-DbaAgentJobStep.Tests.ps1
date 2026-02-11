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

    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $outputJobStepName = "dbatoolsci_outstep_$(Get-Random)"
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $outputJobStepName
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $outputJobStepName -StepName "dbatoolsci_step1" -Subsystem TransactSql -Command "select 1"

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $result = @(Get-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $outputJobStepName)
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $outputJobStepName -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "Returns output" {
            $result | Should -Not -BeNullOrEmpty
        }

        It "Returns output of the documented type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Agent.JobStep"
        }

        It "Has the expected default display properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "InstanceName", "SqlInstance", "AgentJob", "Name", "SubSystem", "LastRunDate", "LastRunOutcome", "State")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}