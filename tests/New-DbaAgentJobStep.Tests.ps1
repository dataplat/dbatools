param($ModuleName = 'dbatools')

Describe "New-DbaAgentJobStep" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaAgentJobStep
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Job parameter" {
            $CommandUnderTest | Should -HaveParameter Job -Type Object[]
        }
        It "Should have StepId parameter" {
            $CommandUnderTest | Should -HaveParameter StepId -Type Int32
        }
        It "Should have StepName parameter" {
            $CommandUnderTest | Should -HaveParameter StepName -Type String
        }
        It "Should have Subsystem parameter" {
            $CommandUnderTest | Should -HaveParameter Subsystem -Type String
        }
        It "Should have SubsystemServer parameter" {
            $CommandUnderTest | Should -HaveParameter SubsystemServer -Type String
        }
        It "Should have Command parameter" {
            $CommandUnderTest | Should -HaveParameter Command -Type String
        }
        It "Should have CmdExecSuccessCode parameter" {
            $CommandUnderTest | Should -HaveParameter CmdExecSuccessCode -Type Int32
        }
        It "Should have OnSuccessAction parameter" {
            $CommandUnderTest | Should -HaveParameter OnSuccessAction -Type String
        }
        It "Should have OnSuccessStepId parameter" {
            $CommandUnderTest | Should -HaveParameter OnSuccessStepId -Type Int32
        }
        It "Should have OnFailAction parameter" {
            $CommandUnderTest | Should -HaveParameter OnFailAction -Type String
        }
        It "Should have OnFailStepId parameter" {
            $CommandUnderTest | Should -HaveParameter OnFailStepId -Type Int32
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String
        }
        It "Should have DatabaseUser parameter" {
            $CommandUnderTest | Should -HaveParameter DatabaseUser -Type String
        }
        It "Should have RetryAttempts parameter" {
            $CommandUnderTest | Should -HaveParameter RetryAttempts -Type Int32
        }
        It "Should have RetryInterval parameter" {
            $CommandUnderTest | Should -HaveParameter RetryInterval -Type Int32
        }
        It "Should have OutputFileName parameter" {
            $CommandUnderTest | Should -HaveParameter OutputFileName -Type String
        }
        It "Should have Insert parameter" {
            $CommandUnderTest | Should -HaveParameter Insert -Type Switch
        }
        It "Should have Flag parameter" {
            $CommandUnderTest | Should -HaveParameter Flag -Type String[]
        }
        It "Should have ProxyName parameter" {
            $CommandUnderTest | Should -HaveParameter ProxyName -Type String
        }
        It "Should have Force parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "New Agent Job Step is added properly" {
        BeforeAll {
            $random = Get-Random
            $job = New-DbaAgentJob -SqlInstance $global:instance2 -Job "dbatoolsci_job_1_$random" -Description "Just another job"
            $jobTwo = New-DbaAgentJob -SqlInstance $global:instance2 -Job "dbatoolsci_job_2_$random" -Description "Just another job"
            $jobThree = New-DbaAgentJob -SqlInstance $global:instance2 -Job "dbatoolsci_job_3_$random" -Description "Just another job"
        }

        AfterAll {
            Remove-DbaAgentJob -SqlInstance $global:instance2 -Job "dbatoolsci_job_1_$random", "dbatoolsci_job_2_$random", "dbatoolsci_job_3_$random" -Confirm:$false
        }

        It "Should have the right name and description" {
            $results = New-DbaAgentJobStep -SqlInstance $global:instance2 -Job $job -StepName "Step One"
            $results.Name | Should -Be "Step One"
        }

        It "Should have the right properties" {
            $jobStep = @{
                SqlInstance    = $global:instance2
                Job            = $jobTwo
                StepName       = "Step X"
                Subsystem      = "TransactSql"
                Command        = "select 1"
                Database       = "master"
                RetryAttempts  = 2
                RetryInterval  = 5
                OutputFileName = "log.txt"
            }
            $results = New-DbaAgentJobStep @jobStep
            $results.Name | Should -Be "Step X"
            $results.Subsystem | Should -Be "TransactSql"
            $results.Command | Should -Be "Select 1"
            $results.DatabaseName | Should -Be "master"
            $results.RetryAttempts | Should -Be 2
            $results.RetryInterval | Should -Be 5
            $results.OutputFileName | Should -Be "log.txt"
        }

        It "Should actually for sure exist" {
            $newresults = Get-DbaAgentJob -SqlInstance $global:instance2 -Job "dbatoolsci_job_1_$random"
            $newresults.JobSteps.Name | Should -Be "Step One"
        }

        It "Should not write over existing job steps" {
            $warn = $null
            New-DbaAgentJobStep -SqlInstance $global:instance2 -Job "dbatoolsci_job_1_$random" -StepName "Step One" -WarningAction SilentlyContinue -WarningVariable warn
            $warn -match "already exists" | Should -Be $true
            $newresults = Get-DbaAgentJob -SqlInstance $global:instance2 -Job "dbatoolsci_job_1_$random"
            $newresults.JobSteps.Name | Should -Be "Step One"
            $newresults.JobSteps | Where-Object Id -eq 1 | Select-Object -ExpandProperty Name | Should -Be "Step One"
        }

        It "Force should replace the job step" {
            $results = New-DbaAgentJobStep -SqlInstance $global:instance2 -Job "dbatoolsci_job_1_$random" -StepName "New Step One" -StepId 1 -Force
            $results.Name | Should -Be "New Step One"
            $newresults = Get-DbaAgentJob -SqlInstance $global:instance2 -Job "dbatoolsci_job_1_$random"
            $newresults.JobSteps | Where-Object Id -eq 1 | Select-Object -ExpandProperty Name | Should -Be "New Step One"
        }

        It "Insert should insert jobstep and update IDs" {
            $results = New-DbaAgentJobStep -SqlInstance $global:instance2 -Job "dbatoolsci_job_1_$random" -StepName "New Step Three" -StepId 1 -Insert
            $results.Name | Should -Be "New Step Three"
            $newresults = Get-DbaAgentJob -SqlInstance $global:instance2 -Job "dbatoolsci_job_1_$random"
            $newresults.JobSteps | Where-Object Id -eq 1 | Select-Object -ExpandProperty Name | Should -Be "New Step Three"
            $newresults.JobSteps | Where-Object Id -eq 2 | Select-Object -ExpandProperty Name | Should -Be "New Step One"
        }

        It "Job is refreshed from the server" {
            $agentStep1 = New-DbaAgentJobStep -SqlInstance $global:instance2 -Job $jobThree -StepName "Error collection" -OnFailAction QuitWithFailure -OnSuccessAction QuitWithFailure
            $agentStep2 = New-DbaAgentJobStep -SqlInstance $global:instance2 -Job $jobThree -StepName "Step 1" -OnFailAction GoToStep -OnFailStepId 1 -OnSuccessAction GoToNextStep
            $agentStep3 = New-DbaAgentJobStep -SqlInstance $global:instance2 -Job $jobThree -StepName "Step 2" -OnFailAction GoToStep -OnFailStepId 1 -OnSuccessAction GoToNextStep
            $agentStep4 = New-DbaAgentJobStep -SqlInstance $global:instance2 -Job $jobThree -StepName "Step 3" -OnFailAction GoToStep -OnFailStepId 1 -OnSuccessAction GoToNextStep
            $agentStep5 = New-DbaAgentJobStep -SqlInstance $global:instance2 -Job $jobThree -StepName "Step 4" -OnFailAction GoToStep -OnFailStepId 1 -OnSuccessAction GoToNextStep

            $agentStep1.Name | Should -Be "Error collection"
            $agentStep2.Name | Should -Be "Step 1"
            $agentStep3.Name | Should -Be "Step 2"
            $agentStep4.Name | Should -Be "Step 3"
            $agentStep5.Name | Should -Be "Step 4"

            $results = Get-DbaAgentJob -SqlInstance $global:instance2 -Job $jobThree
            $results.JobSteps | Where-Object Id -eq 1 | Select-Object -ExpandProperty Name | Should -Be "Error collection"
            $results.JobSteps | Where-Object Id -eq 2 | Select-Object -ExpandProperty Name | Should -Be "Step 1"
            $results.JobSteps | Where-Object Id -eq 3 | Select-Object -ExpandProperty Name | Should -Be "Step 2"
            $results.JobSteps | Where-Object Id -eq 4 | Select-Object -ExpandProperty Name | Should -Be "Step 3"
            $results.JobSteps | Where-Object Id -eq 5 | Select-Object -ExpandProperty Name | Should -Be "Step 4"
        }
    }
}
