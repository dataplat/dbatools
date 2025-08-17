#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Start-DbaAgentJob",
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
                "ExcludeJob",
                "InputObject",
                "AllJobs",
                "Wait",
                "Parallel",
                "WaitPeriod",
                "SleepPeriod",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Start a job" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

            $jobNames = "dbatoolsci_job_$(Get-Random)", "dbatoolsci_job_$(Get-Random)", "dbatoolsci_job_$(Get-Random)"
            $jobName1, $jobName2, $jobName3 = $jobNames
            foreach ($jobName in $jobNames) {
                $null = New-DbaAgentJob -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Job $jobName
                $null = New-DbaAgentJobStep -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Job $jobName -StepName "step1_$(Get-Random)" -Subsystem TransactSql -Command "WAITFOR DELAY '00:05:00'"
                $null = New-DbaAgentJobStep -SqlInstance $TestConfig.instance2 -Job $jobName -StepName "step2" -StepId 2 -Subsystem TransactSql -Command "WAITFOR DELAY '00:00:01'"
                $null = New-DbaAgentJobStep -SqlInstance $TestConfig.instance2 -Job $jobName -StepName "step3" -StepId 3 -Subsystem TransactSql -Command "SELECT 1"
            }

            $global:startJobResults = Get-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job $jobName1 | Start-DbaAgentJob

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
        }
        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Job $jobNames -Confirm:$false
        }

        It "returns a CurrentRunStatus of not Idle and supports pipe" {
            $global:startJobResults.CurrentRunStatus -ne "Idle" | Should -Be $true
        }

        It "returns a CurrentRunStatus of not null and supports pipe" {
            $global:startJobResults.CurrentRunStatus -ne $null | Should -Be $true
        }

        It "does not run all jobs" {
            $null = Start-DbaAgentJob -SqlInstance $TestConfig.instance2 -WarningAction SilentlyContinue -WarningVariable warn
            $warn -match "use one of the job" | Should -Be $true
        }

        It "returns on multiple server inputs" {
            $multiServerResults = Start-DbaAgentJob -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Job $jobName2
            ($multiServerResults.SqlInstance).Count | Should -Be 2
        }

        It "starts job at specified step" {
            $null = Start-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job $jobName3 -StepName "step3"
            $stepResults = Get-DbaAgentJobHistory -SqlInstance $TestConfig.instance2 -Job $jobName3
            ($stepResults.SqlInstance).Count | Should -Be 2
        }

        It "do not start job if the step does not exist" {
            $nonExistentStepResults = Start-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job $jobName3 -StepName "stepdoesnoteexist"
            ($nonExistentStepResults.SqlInstance).Count | Should -Be 0
        }
    }
}