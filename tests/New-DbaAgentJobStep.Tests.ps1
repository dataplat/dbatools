$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Job', 'StepId', 'StepName', 'Subsystem', 'SubsystemServer', 'Command', 'CmdExecSuccessCode', 'OnSuccessAction', 'OnSuccessStepId', 'OnFailAction', 'OnFailStepId', 'Database', 'DatabaseUser', 'RetryAttempts', 'RetryInterval', 'OutputFileName', 'Insert', 'Flag', 'ProxyName', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "New Agent Job Step is added properly" {
        BeforeAll {
            # Create job to add step to
            $random = Get-Random
            $job = New-DbaAgentJob -SqlInstance $script:instance2 -Job "dbatoolsci_job_1_$random" -Description "Just another job"
            $jobTwo = New-DbaAgentJob -SqlInstance $script:instance2 -Job "dbatoolsci_job_2_$random" -Description "Just another job"
            $jobThree = New-DbaAgentJob -SqlInstance $script:instance2 -Job "dbatoolsci_job_3_$random" -Description "Just another job"
        }

        AfterAll {
            Remove-DbaAgentJob -SqlInstance $script:instance2 -Job "dbatoolsci_job_1_$random", "dbatoolsci_job_2_$random", "dbatoolsci_job_3_$random"
        }

        It "Should have the right name and description" {
            $results = New-DbaAgentJobStep -SqlInstance $script:instance2 -Job $job -StepName "Step One"
            $results.Name | Should -Be "Step One"
        }

        It "Should have the right properties" {
            $jobStep = @{
                SqlInstance    = $script:instance2
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
            $newresults = Get-DbaAgentJob -SqlInstance $script:instance2 -Job "dbatoolsci_job_1_$random"
            $newresults.JobSteps.Name | Should -Be "Step One"
        }

        It "Should not write over existing job steps" {
            New-DbaAgentJobStep -SqlInstance $script:instance2 -Job "dbatoolsci_job_1_$random" -StepName "Step One" -WarningAction SilentlyContinue -WarningVariable warn
            $warn -match "already exists" | Should -Be $true
            $newresults = Get-DbaAgentJob -SqlInstance $script:instance2 -Job "dbatoolsci_job_1_$random"
            $newresults.JobSteps.Name | Should -Be "Step One"
            $newresults.JobSteps | Where-Object Id -eq 1 | Select-Object -ExpandProperty Name | Should -Be "Step One"
        }

        It "Force should replace the job step" {
            $results = New-DbaAgentJobStep -SqlInstance $script:instance2 -Job "dbatoolsci_job_1_$random" -StepName "New Step One" -StepId 1 -Force
            $results.Name | Should -Be "New Step One"
            $newresults = Get-DbaAgentJob -SqlInstance $script:instance2 -Job "dbatoolsci_job_1_$random"
            $newresults.JobSteps | Where-Object Id -eq 1 | Select-Object -ExpandProperty Name | Should -Be "New Step One"
        }

        It "Insert should insert jobstep and update IDs" {
            $results = New-DbaAgentJobStep -SqlInstance $script:instance2 -Job "dbatoolsci_job_1_$random" -StepName "New Step Three" -StepId 1 -Insert
            $results.Name | Should -Be "New Step Three"
            $newresults = Get-DbaAgentJob -SqlInstance $script:instance2 -Job "dbatoolsci_job_1_$random"
            $newresults.JobSteps | Where-Object Id -eq 1 | Select-Object -ExpandProperty Name | Should -Be "New Step Three"
            $newresults.JobSteps | Where-Object Id -eq 2 | Select-Object -ExpandProperty Name | Should -Be "New Step One"
        }

        # see 7199 and 7200
        It "Job is refreshed from the server" {
            $agentStep1 = New-DbaAgentJobStep -SqlInstance $script:instance2 -Job $jobThree -StepName "Error collection" -OnFailAction QuitWithFailure -OnSuccessAction QuitWithFailure
            $agentStep2 = New-DbaAgentJobStep -SqlInstance $script:instance2 -Job $jobThree -StepName "Step 1" -OnFailAction GoToStep -OnFailStepId 1 -OnSuccessAction GoToNextStep
            $agentStep3 = New-DbaAgentJobStep -SqlInstance $script:instance2 -Job $jobThree -StepName "Step 2" -OnFailAction GoToStep -OnFailStepId 1 -OnSuccessAction GoToNextStep
            $agentStep4 = New-DbaAgentJobStep -SqlInstance $script:instance2 -Job $jobThree -StepName "Step 3" -OnFailAction GoToStep -OnFailStepId 1 -OnSuccessAction GoToNextStep
            $agentStep5 = New-DbaAgentJobStep -SqlInstance $script:instance2 -Job $jobThree -StepName "Step 4" -OnFailAction GoToStep -OnFailStepId 1 -OnSuccessAction GoToNextStep

            $agentStep1.Name | Should -Be "Error collection"
            $agentStep2.Name | Should -Be "Step 1"
            $agentStep3.Name | Should -Be "Step 2"
            $agentStep4.Name | Should -Be "Step 3"
            $agentStep5.Name | Should -Be "Step 4"

            $results = Get-DbaAgentJob -SqlInstance $script:instance2 -Job $jobThree
            $results.JobSteps | Where-Object Id -eq 1 | Select-Object -ExpandProperty Name | Should -Be "Error collection"
            $results.JobSteps | Where-Object Id -eq 2 | Select-Object -ExpandProperty Name | Should -Be "Step 1"
            $results.JobSteps | Where-Object Id -eq 3 | Select-Object -ExpandProperty Name | Should -Be "Step 2"
            $results.JobSteps | Where-Object Id -eq 4 | Select-Object -ExpandProperty Name | Should -Be "Step 3"
            $results.JobSteps | Where-Object Id -eq 5 | Select-Object -ExpandProperty Name | Should -Be "Step 4"
        }
    }
}