param($ModuleName = 'dbatools')

Describe "New-DbaAgentJob" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaAgentJob
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Job",
                "Schedule",
                "ScheduleId",
                "Disabled",
                "Description",
                "StartStepId",
                "Category",
                "OwnerLogin",
                "EventLogLevel",
                "EmailLevel",
                "PageLevel",
                "EmailOperator",
                "NetsendOperator",
                "PageOperator",
                "DeleteLevel",
                "Force",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "New Agent Job is added properly" {
        BeforeAll {
            $jobName = "Job One"
            $jobDescription = "Just another job"
        }

        AfterAll {
            # Cleanup and ignore all output
            Remove-DbaAgentJob -SqlInstance $global:instance2 -Job $jobName -Confirm:$false *> $null
        }

        It "Should create a new job with the right name and description" {
            $results = New-DbaAgentJob -SqlInstance $global:instance2 -Job $jobName -Description $jobDescription
            $results.Name | Should -Be $jobName
            $results.Description | Should -Be $jobDescription
        }

        It "Should verify the job exists" {
            $newResults = Get-DbaAgentJob -SqlInstance $global:instance2 -Job $jobName
            $newResults.Name | Should -Be $jobName
            $newResults.Description | Should -Be $jobDescription
        }

        It "Should not overwrite existing jobs" {
            $warn = $null
            $results = New-DbaAgentJob -SqlInstance $global:instance2 -Job $jobName -Description $jobDescription -WarningAction SilentlyContinue -WarningVariable warn
            $warn | Should -Match "already exists"
        }
    }
}
