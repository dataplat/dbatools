param($ModuleName = 'dbatools')

Describe "Set-DbaAgentJob" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaAgentJob
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have Job as a parameter" {
            $CommandUnderTest | Should -HaveParameter Job -Type System.Object[]
        }
        It "Should have Schedule as a parameter" {
            $CommandUnderTest | Should -HaveParameter Schedule -Type System.Object[]
        }
        It "Should have ScheduleId as a parameter" {
            $CommandUnderTest | Should -HaveParameter ScheduleId -Type System.Int32[]
        }
        It "Should have NewName as a parameter" {
            $CommandUnderTest | Should -HaveParameter NewName -Type System.String
        }
        It "Should have Enabled as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Enabled -Type System.Management.Automation.SwitchParameter
        }
        It "Should have Disabled as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Disabled -Type System.Management.Automation.SwitchParameter
        }
        It "Should have Description as a parameter" {
            $CommandUnderTest | Should -HaveParameter Description -Type System.String
        }
        It "Should have StartStepId as a parameter" {
            $CommandUnderTest | Should -HaveParameter StartStepId -Type System.Int32
        }
        It "Should have Category as a parameter" {
            $CommandUnderTest | Should -HaveParameter Category -Type System.String
        }
        It "Should have OwnerLogin as a parameter" {
            $CommandUnderTest | Should -HaveParameter OwnerLogin -Type System.String
        }
        It "Should have EventLogLevel as a parameter" {
            $CommandUnderTest | Should -HaveParameter EventLogLevel -Type System.Object
        }
        It "Should have EmailLevel as a parameter" {
            $CommandUnderTest | Should -HaveParameter EmailLevel -Type System.Object
        }
        It "Should have NetsendLevel as a parameter" {
            $CommandUnderTest | Should -HaveParameter NetsendLevel -Type System.Object
        }
        It "Should have PageLevel as a parameter" {
            $CommandUnderTest | Should -HaveParameter PageLevel -Type System.Object
        }
        It "Should have EmailOperator as a parameter" {
            $CommandUnderTest | Should -HaveParameter EmailOperator -Type System.String
        }
        It "Should have NetsendOperator as a parameter" {
            $CommandUnderTest | Should -HaveParameter NetsendOperator -Type System.String
        }
        It "Should have PageOperator as a parameter" {
            $CommandUnderTest | Should -HaveParameter PageOperator -Type System.String
        }
        It "Should have DeleteLevel as a parameter" {
            $CommandUnderTest | Should -HaveParameter DeleteLevel -Type System.Object
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type System.Management.Automation.SwitchParameter
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Management.Smo.Agent.Job[]
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
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
