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
}
Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $outputJobName = "dbatoolsci_outputtest_$(Get-Random)"
            $outputStepName = "dbatoolsci_step1"
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $outputJobName
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $outputJobName -StepId 1 -StepName $outputStepName -Subsystem TransactSql -Command "select 1"

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $result = Remove-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $outputJobName -StepName $outputStepName
        }

        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $outputJobName -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "Returns no output" {
            $result | Should -BeNullOrEmpty
        }
    }
}