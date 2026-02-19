#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaAgentJobOutputFile",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag "UnitTests" {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Job",
                "ExcludeJob",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag "IntegrationTests" {
    BeforeAll {
        $TestConfig = Get-TestConfig
        $server = Connect-DbaInstance -SqlInstance $TestConfig.Instance1
        $jobName1 = "dbatoolsci_OutputFileJob1_$(Get-Random)"
        $jobName2 = "dbatoolsci_OutputFileJob2_$(Get-Random)"
        $jobName3 = "dbatoolsci_NoOutputJob_$(Get-Random)"

        # Job 1: two steps, both with output files
        $job1 = New-DbaAgentJob -SqlInstance $server -Job $jobName1 -Force
        $null = New-DbaAgentJobStep -SqlInstance $server -Job $jobName1 -StepName "Step1" -Command "SELECT 1" -OutputFileName "C:\Temp\job1step1.log"
        $null = New-DbaAgentJobStep -SqlInstance $server -Job $jobName1 -StepName "Step2" -Command "SELECT 2" -OutputFileName "C:\Temp\job1step2.log"

        # Job 2: one step with output file, one without
        $job2 = New-DbaAgentJob -SqlInstance $server -Job $jobName2 -Force
        $null = New-DbaAgentJobStep -SqlInstance $server -Job $jobName2 -StepName "Step1" -Command "SELECT 1" -OutputFileName "C:\Temp\job2step1.log"
        $null = New-DbaAgentJobStep -SqlInstance $server -Job $jobName2 -StepName "Step2" -Command "SELECT 2"

        # Job 3: no steps with output files
        $job3 = New-DbaAgentJob -SqlInstance $server -Job $jobName3 -Force
        $null = New-DbaAgentJobStep -SqlInstance $server -Job $jobName3 -StepName "Step1" -Command "SELECT 1"
        $null = New-DbaAgentJobStep -SqlInstance $server -Job $jobName3 -StepName "Step2" -Command "SELECT 2"
    }

    AfterAll {
        $null = Remove-DbaAgentJob -SqlInstance $server -Job $jobName1, $jobName2, $jobName3 -Confirm:$false
    }

    Context "Gets only steps with output files" {
        BeforeAll {
            $global:dbatoolsciResults = @(Get-DbaAgentJobOutputFile -SqlInstance $TestConfig.Instance1 -Job $jobName1, $jobName2, $jobName3)
        }

        AfterAll {
            $global:dbatoolsciResults = $null
        }

        It "Returns only steps that have an output file configured" {
            $global:dbatoolsciResults.Count | Should -BeExactly 3
        }

        It "Does not return steps from the no-output job" {
            $global:dbatoolsciResults.Job | Should -Not -Contain $jobName3
        }

        It "Returns results for jobs that have at least one output file" {
            $global:dbatoolsciResults.Job | Should -Contain $jobName1
            $global:dbatoolsciResults.Job | Should -Contain $jobName2
        }

        It "Populates OutputFileName on each result" {
            $global:dbatoolsciResults.OutputFileName | Should -Not -BeNullOrEmpty
        }

        It "Populates RemoteOutputFileName as a UNC path" {
            foreach ($result in $global:dbatoolsciResults) {
                $result.RemoteOutputFileName | Should -Match "^\\\\"
            }
        }
    }

    Context "Honors the Job parameter" {
        BeforeAll {
            $global:dbatoolsciJobFilter = @(Get-DbaAgentJobOutputFile -SqlInstance $TestConfig.Instance1 -Job $jobName1)
        }

        AfterAll {
            $global:dbatoolsciJobFilter = $null
        }

        It "Returns only results from the specified job" {
            $global:dbatoolsciJobFilter.Job | Should -Not -Contain $jobName2
            $global:dbatoolsciJobFilter.Job | Should -Not -Contain $jobName3
        }

        It "Returns both output-file steps from Job1" {
            $global:dbatoolsciJobFilter.Count | Should -BeExactly 2
        }

        It "Returns the correct step names" {
            $global:dbatoolsciJobFilter.JobStep | Should -Contain "Step1"
            $global:dbatoolsciJobFilter.JobStep | Should -Contain "Step2"
        }
    }

    Context "Honors the ExcludeJob parameter" {
        BeforeAll {
            $global:dbatoolsciExclude = @(Get-DbaAgentJobOutputFile -SqlInstance $TestConfig.Instance1 -Job $jobName1, $jobName2, $jobName3 -ExcludeJob $jobName1)
        }

        AfterAll {
            $global:dbatoolsciExclude = $null
        }

        It "Excludes the specified job" {
            $global:dbatoolsciExclude.Job | Should -Not -Contain $jobName1
        }

        It "Returns only the one output-file step from Job2" {
            $global:dbatoolsciExclude.Count | Should -BeExactly 1
        }

        It "Returns the correct OutputFileName" {
            $global:dbatoolsciExclude[0].OutputFileName | Should -Be "C:\Temp\job2step1.log"
        }

        It "Returns the correct StepId" {
            $global:dbatoolsciExclude[0].StepId | Should -BeExactly 1
        }
    }

    Context "Job with no output files returns nothing" {
        BeforeAll {
            $global:dbatoolsciNoOutput = @(Get-DbaAgentJobOutputFile -SqlInstance $TestConfig.Instance1 -Job $jobName3)
        }

        AfterAll {
            $global:dbatoolsciNoOutput = $null
        }

        It "Returns zero results when the job has no output files configured" {
            $global:dbatoolsciNoOutput.Count | Should -BeExactly 0
        }
    }

}
