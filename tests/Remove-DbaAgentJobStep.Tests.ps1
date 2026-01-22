#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaAgentJobStep",
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
                "StepName",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" -Tag IntegrationTests {
        BeforeAll {
            $instance = $TestConfig.instance2
            $jobName = "dbatoolsci_test_$(Get-Random)"
            $stepName = "dbatoolsci_step_$(Get-Random)"

            $splatNewJob = @{
                SqlInstance     = $instance
                Job             = $jobName
                EnableException = $true
            }
            $null = New-DbaAgentJob @splatNewJob

            $splatNewStep = @{
                SqlInstance     = $instance
                Job             = $jobName
                StepName        = $stepName
                Subsystem       = "TransactSql"
                Command         = "SELECT 1"
                EnableException = $true
            }
            $null = New-DbaAgentJobStep @splatNewStep
        }

        AfterAll {
            $splatRemoveJob = @{
                SqlInstance     = $instance
                Job             = $jobName
                EnableException = $true
                Confirm         = $false
            }
            $null = Remove-DbaAgentJob @splatRemoveJob
        }

        It "Returns no output by default" {
            $splatRemove = @{
                SqlInstance     = $instance
                Job             = $jobName
                StepName        = $stepName
                EnableException = $true
                Confirm         = $false
            }
            $result = Remove-DbaAgentJobStep @splatRemove
            $result | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>