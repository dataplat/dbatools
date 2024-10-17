param($ModuleName = 'dbatools')

Describe "Set-DbaAgentJob" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaAgentJob
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Job as a parameter" {
            $CommandUnderTest | Should -HaveParameter Job -Type Object[]
        }
        It "Should have Schedule as a parameter" {
            $CommandUnderTest | Should -HaveParameter Schedule -Type Object[]
        }
        It "Should have ScheduleId as a parameter" {
            $CommandUnderTest | Should -HaveParameter ScheduleId -Type Int32[]
        }
        It "Should have NewName as a parameter" {
            $CommandUnderTest | Should -HaveParameter NewName -Type String
        }
        It "Should have Enabled as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Enabled -Type Switch
        }
        It "Should have Disabled as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Disabled -Type Switch
        }
        It "Should have Description as a parameter" {
            $CommandUnderTest | Should -HaveParameter Description -Type String
        }
        It "Should have StartStepId as a parameter" {
            $CommandUnderTest | Should -HaveParameter StartStepId -Type Int32
        }
        It "Should have Category as a parameter" {
            $CommandUnderTest | Should -HaveParameter Category -Type String
        }
        It "Should have OwnerLogin as a parameter" {
            $CommandUnderTest | Should -HaveParameter OwnerLogin -Type String
        }
        It "Should have EventLogLevel as a parameter" {
            $CommandUnderTest | Should -HaveParameter EventLogLevel -Type Object
        }
        It "Should have EmailLevel as a parameter" {
            $CommandUnderTest | Should -HaveParameter EmailLevel -Type Object
        }
        It "Should have NetsendLevel as a parameter" {
            $CommandUnderTest | Should -HaveParameter NetsendLevel -Type Object
        }
        It "Should have PageLevel as a parameter" {
            $CommandUnderTest | Should -HaveParameter PageLevel -Type Object
        }
        It "Should have EmailOperator as a parameter" {
            $CommandUnderTest | Should -HaveParameter EmailOperator -Type String
        }
        It "Should have NetsendOperator as a parameter" {
            $CommandUnderTest | Should -HaveParameter NetsendOperator -Type String
        }
        It "Should have PageOperator as a parameter" {
            $CommandUnderTest | Should -HaveParameter PageOperator -Type String
        }
        It "Should have DeleteLevel as a parameter" {
            $CommandUnderTest | Should -HaveParameter DeleteLevel -Type Object
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Job[]
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
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
            $server = Connect-DbaInstance -SqlInstance $env:instance2
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
