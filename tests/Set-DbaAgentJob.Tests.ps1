param($ModuleName = 'dbatools')

Describe "Set-DbaAgentJob" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaAgentJob
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Job",
                "Schedule",
                "ScheduleId",
                "NewName",
                "Enabled",
                "Disabled",
                "Description",
                "StartStepId",
                "Category",
                "OwnerLogin",
                "EventLogLevel",
                "EmailLevel",
                "NetsendLevel",
                "PageLevel",
                "EmailOperator",
                "NetsendOperator",
                "PageOperator",
                "DeleteLevel",
                "Force",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }
}

# Integration tests
Describe "Set-DbaAgentJob Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $PSDefaultParameterValues['*:WarningAction'] = 'SilentlyContinue'
        $PSDefaultParameterValues['*:ErrorAction'] = 'Stop'
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Command actually works" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $jobName = "dbatoolsci_test_job"
            $newJobName = "dbatoolsci_test_job_renamed"
            $null = New-DbaAgentJob -SqlInstance $server -Job $jobName
        }
        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $server -Job $jobName, $newJobName -Confirm:$false
        }

        It "Renames a job" {
            $results = Set-DbaAgentJob -SqlInstance $server -Job $jobName -NewName $newJobName
            $results.Name | Should -Be $newJobName
            $server.JobServer.Jobs[$newJobName] | Should -Not -BeNullOrEmpty
        }

        It "Disables a job" {
            $results = Set-DbaAgentJob -SqlInstance $server -Job $newJobName -Disabled
            $results.IsEnabled | Should -Be $false
            $server.JobServer.Jobs[$newJobName].IsEnabled | Should -Be $false
        }

        It "Enables a job" {
            $results = Set-DbaAgentJob -SqlInstance $server -Job $newJobName -Enabled
            $results.IsEnabled | Should -Be $true
            $server.JobServer.Jobs[$newJobName].IsEnabled | Should -Be $true
        }

        It "Changes the description" {
            $newDescription = "This is a test description"
            $results = Set-DbaAgentJob -SqlInstance $server -Job $newJobName -Description $newDescription
            $results.Description | Should -Be $newDescription
            $server.JobServer.Jobs[$newJobName].Description | Should -Be $newDescription
        }
    }
}
