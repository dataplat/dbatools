param($ModuleName = 'dbatools')

Describe "New-DbaAgentJob" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaAgentJob
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Job parameter" {
            $CommandUnderTest | Should -HaveParameter Job -Type String -Not -Mandatory
        }
        It "Should have Schedule parameter" {
            $CommandUnderTest | Should -HaveParameter Schedule -Type Object[] -Not -Mandatory
        }
        It "Should have ScheduleId parameter" {
            $CommandUnderTest | Should -HaveParameter ScheduleId -Type Int32[] -Not -Mandatory
        }
        It "Should have Disabled parameter" {
            $CommandUnderTest | Should -HaveParameter Disabled -Type SwitchParameter -Not -Mandatory
        }
        It "Should have Description parameter" {
            $CommandUnderTest | Should -HaveParameter Description -Type String -Not -Mandatory
        }
        It "Should have StartStepId parameter" {
            $CommandUnderTest | Should -HaveParameter StartStepId -Type Int32 -Not -Mandatory
        }
        It "Should have Category parameter" {
            $CommandUnderTest | Should -HaveParameter Category -Type String -Not -Mandatory
        }
        It "Should have OwnerLogin parameter" {
            $CommandUnderTest | Should -HaveParameter OwnerLogin -Type String -Not -Mandatory
        }
        It "Should have EventLogLevel parameter" {
            $CommandUnderTest | Should -HaveParameter EventLogLevel -Type Object -Not -Mandatory
        }
        It "Should have EmailLevel parameter" {
            $CommandUnderTest | Should -HaveParameter EmailLevel -Type Object -Not -Mandatory
        }
        It "Should have PageLevel parameter" {
            $CommandUnderTest | Should -HaveParameter PageLevel -Type Object -Not -Mandatory
        }
        It "Should have EmailOperator parameter" {
            $CommandUnderTest | Should -HaveParameter EmailOperator -Type String -Not -Mandatory
        }
        It "Should have NetsendOperator parameter" {
            $CommandUnderTest | Should -HaveParameter NetsendOperator -Type String -Not -Mandatory
        }
        It "Should have PageOperator parameter" {
            $CommandUnderTest | Should -HaveParameter PageOperator -Type String -Not -Mandatory
        }
        It "Should have DeleteLevel parameter" {
            $CommandUnderTest | Should -HaveParameter DeleteLevel -Type Object -Not -Mandatory
        }
        It "Should have Force parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type SwitchParameter -Not -Mandatory
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
        }
    }

    Context "New Agent Job is added properly" {
        BeforeAll {
            $jobName = "Job One"
            $jobDescription = "Just another job"
        }

        AfterAll {
            # Cleanup and ignore all output
            Remove-DbaAgentJob -SqlInstance $script:instance2 -Job $jobName -Confirm:$false *> $null
        }

        It "Should create a new job with the right name and description" {
            $results = New-DbaAgentJob -SqlInstance $script:instance2 -Job $jobName -Description $jobDescription
            $results.Name | Should -Be $jobName
            $results.Description | Should -Be $jobDescription
        }

        It "Should verify the job exists" {
            $newResults = Get-DbaAgentJob -SqlInstance $script:instance2 -Job $jobName
            $newResults.Name | Should -Be $jobName
            $newResults.Description | Should -Be $jobDescription
        }

        It "Should not overwrite existing jobs" {
            $warn = $null
            $results = New-DbaAgentJob -SqlInstance $script:instance2 -Job $jobName -Description $jobDescription -WarningAction SilentlyContinue -WarningVariable warn
            $warn | Should -Match "already exists"
        }
    }
}
