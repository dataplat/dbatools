#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaAgentJobStep",
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
                "StepId",
                "StepName",
                "Subsystem",
                "SubsystemServer",
                "Command",
                "CmdExecSuccessCode",
                "OnSuccessAction",
                "OnSuccessStepId",
                "OnFailAction",
                "OnFailStepId",
                "Database",
                "DatabaseUser",
                "RetryAttempts",
                "RetryInterval",
                "OutputFileName",
                "Insert",
                "Flag",
                "ProxyName",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "New Agent Job Step is added properly" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Create job to add step to
            $random = Get-Random
            $job = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job "dbatoolsci_job_1_$random" -Description "Just another job"
            $jobTwo = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job "dbatoolsci_job_2_$random" -Description "Just another job"
            $jobThree = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job "dbatoolsci_job_3_$random" -Description "Just another job"

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job "dbatoolsci_job_1_$random", "dbatoolsci_job_2_$random", "dbatoolsci_job_3_$random"

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should have the right name and description" {
            $results = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $job -StepName "Step One"
            $results.Name | Should -Be "Step One"
        }

        It "Should have the right properties" {
            $splatJobStep = @{
                SqlInstance    = $TestConfig.InstanceSingle
                Job            = $jobTwo
                StepName       = "Step X"
                Subsystem      = "TransactSql"
                Command        = "select 1"
                Database       = "master"
                RetryAttempts  = 2
                RetryInterval  = 5
                OutputFileName = "log.txt"
            }
            $results = New-DbaAgentJobStep @splatJobStep
            $results.Name | Should -Be "Step X"
            $results.Subsystem | Should -Be "TransactSql"
            $results.Command | Should -Be "Select 1"
            $results.DatabaseName | Should -Be "master"
            $results.RetryAttempts | Should -Be 2
            $results.RetryInterval | Should -Be 5
            $results.OutputFileName | Should -Be "log.txt"
        }


        It "Should actually for sure exist" {
            $newresults = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job "dbatoolsci_job_1_$random"
            $newresults.JobSteps.Name | Should -Be "Step One"
        }

        It "Should not write over existing job steps" {
            New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job "dbatoolsci_job_1_$random" -StepName "Step One" -WarningAction SilentlyContinue -WarningVariable warn
            $warn -match "already exists" | Should -Be $true
            $newresults = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job "dbatoolsci_job_1_$random"
            $newresults.JobSteps.Name | Should -Be "Step One"
            $newresults.JobSteps | Where-Object Id -eq 1 | Select-Object -ExpandProperty Name | Should -Be "Step One"
        }

        It "Force should replace the job step" {
            $results = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job "dbatoolsci_job_1_$random" -StepName "New Step One" -StepId 1 -Force
            $results.Name | Should -Be "New Step One"
            $newresults = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job "dbatoolsci_job_1_$random"
            $newresults.JobSteps | Where-Object Id -eq 1 | Select-Object -ExpandProperty Name | Should -Be "New Step One"
        }

        It "Insert should insert jobstep and update IDs" {
            $results = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job "dbatoolsci_job_1_$random" -StepName "New Step Three" -StepId 1 -Insert
            $results.Name | Should -Be "New Step Three"
            $newresults = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job "dbatoolsci_job_1_$random"
            $newresults.JobSteps | Where-Object Id -eq 1 | Select-Object -ExpandProperty Name | Should -Be "New Step Three"
            $newresults.JobSteps | Where-Object Id -eq 2 | Select-Object -ExpandProperty Name | Should -Be "New Step One"
        }

        # see 7199 and 7200
        It "Job is refreshed from the server" {
            $agentStep1 = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $jobThree -StepName "Error collection" -OnFailAction QuitWithFailure -OnSuccessAction QuitWithFailure
            $agentStep2 = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $jobThree -StepName "Step 1" -OnFailAction GoToStep -OnFailStepId 1 -OnSuccessAction GoToNextStep
            $agentStep3 = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $jobThree -StepName "Step 2" -OnFailAction GoToStep -OnFailStepId 1 -OnSuccessAction GoToNextStep
            $agentStep4 = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $jobThree -StepName "Step 3" -OnFailAction GoToStep -OnFailStepId 1 -OnSuccessAction GoToNextStep
            $agentStep5 = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $jobThree -StepName "Step 4" -OnFailAction GoToStep -OnFailStepId 1 -OnSuccessAction GoToNextStep

            $agentStep1.Name | Should -Be "Error collection"
            $agentStep2.Name | Should -Be "Step 1"
            $agentStep3.Name | Should -Be "Step 2"
            $agentStep4.Name | Should -Be "Step 3"
            $agentStep5.Name | Should -Be "Step 4"

            $results = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobThree
            $results.JobSteps | Where-Object Id -eq 1 | Select-Object -ExpandProperty Name | Should -Be "Error collection"
            $results.JobSteps | Where-Object Id -eq 2 | Select-Object -ExpandProperty Name | Should -Be "Step 1"
            $results.JobSteps | Where-Object Id -eq 3 | Select-Object -ExpandProperty Name | Should -Be "Step 2"
            $results.JobSteps | Where-Object Id -eq 4 | Select-Object -ExpandProperty Name | Should -Be "Step 3"
            $results.JobSteps | Where-Object Id -eq 5 | Select-Object -ExpandProperty Name | Should -Be "Step 4"
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $random = Get-Random
            $outputJob = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job "dbatoolsci_output_$random" -Description "Output validation test"
            $result = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job $outputJob -StepName "ValidateStep" -Command "SELECT 1" -Database "master" -EnableException

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job "dbatoolsci_output_$random"

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Agent.JobStep]
        }

        It "Has the expected SMO JobStep properties" {
            $expectedProps = @(
                'Name',
                'ID',
                'Parent',
                'Subsystem',
                'Command',
                'DatabaseName',
                'DatabaseUserName',
                'OnSuccessAction',
                'OnSuccessStep',
                'OnFailAction',
                'OnFailStep',
                'RetryAttempts',
                'RetryInterval',
                'OutputFileName',
                'ProxyName',
                'JobStepFlags',
                'Server',
                'CommandExecutionSuccessCode'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be available on JobStep object"
            }
        }

        It "Returns a JobStep with correct basic properties" {
            $result.Name | Should -Be "ValidateStep"
            $result.Subsystem | Should -Be "TransactSql"
            $result.DatabaseName | Should -Be "master"
            $result.Command | Should -Be "SELECT 1"
        }
    }
}