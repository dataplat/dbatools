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
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $jobName = "dbatoolsci_removestep_$(Get-Random)"
        $missingJobName = "dbatoolsci_missingjob_$(Get-Random)"
        $stepName = "dbatoolsci_step1"
        $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName
        $splatStep = @{
            SqlInstance = $TestConfig.InstanceSingle
            Job         = $jobName
            StepId      = 1
            StepName    = $stepName
            Subsystem   = "TransactSql"
            Command     = "SELECT 1"
        }
        $null = New-DbaAgentJobStep @splatStep

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    # Both checks used Stop-Function -Continue -ContinueLabel main, and no loop of the command carries that
    # label. A labeled continue that matches no loop leaves the command and ends the whole calling script,
    # so the job after the missing one was never processed and the caller never got control back.
    It "Removes the step of a job listed after a job that does not exist" {
        $null = Remove-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $missingJobName, $jobName -StepName $stepName -WarningAction SilentlyContinue
        $WarnVar | Should -BeLike "*Job $missingJobName doesn't exist*"
        Get-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $jobName | Should -BeNullOrEmpty
    }

    It "Warns about a missing step without ending the caller loop" {
        $loopCount = 0
        foreach ($i in 1..3) {
            $null = Remove-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $jobName -StepName $stepName -WarningAction SilentlyContinue
            $loopCount++
        }
        $loopCount | Should -Be 3
        $WarnVar | Should -BeLike "*Step $stepName doesn't exist for $jobName on*"
    }
}