param($ModuleName = 'dbatools')

Describe "Get-DbaRunningJob" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaRunningJob
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have InputObject as a non-mandatory parameter of type Job[]" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Job[] -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type switch -Not -Mandatory
        }
        It "Should have Verbose as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Verbose -Type switch -Not -Mandatory
        }
        It "Should have Debug as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Debug -Type switch -Not -Mandatory
        }
        It "Should have ErrorAction as a non-mandatory parameter of type ActionPreference" {
            $CommandUnderTest | Should -HaveParameter ErrorAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have WarningAction as a non-mandatory parameter of type ActionPreference" {
            $CommandUnderTest | Should -HaveParameter WarningAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have InformationAction as a non-mandatory parameter of type ActionPreference" {
            $CommandUnderTest | Should -HaveParameter InformationAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have ProgressAction as a non-mandatory parameter of type ActionPreference" {
            $CommandUnderTest | Should -HaveParameter ProgressAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have ErrorVariable as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter ErrorVariable -Type String -Not -Mandatory
        }
        It "Should have WarningVariable as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter WarningVariable -Type String -Not -Mandatory
        }
        It "Should have InformationVariable as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter InformationVariable -Type String -Not -Mandatory
        }
        It "Should have OutVariable as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter OutVariable -Type String -Not -Mandatory
        }
        It "Should have OutBuffer as a non-mandatory parameter of type Int32" {
            $CommandUnderTest | Should -HaveParameter OutBuffer -Type Int32 -Not -Mandatory
        }
        It "Should have PipelineVariable as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter PipelineVariable -Type String -Not -Mandatory
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            # Setup code for all tests in this context
            $server = Connect-DbaInstance -SqlInstance $script:instance2
        }

        It "Returns running jobs" {
            # Create a mock job that's running
            $jobName = "TestRunningJob"
            $null = New-DbaAgentJob -SqlInstance $server -Job $jobName
            $null = Start-DbaAgentJob -SqlInstance $server -Job $jobName

            $runningJobs = Get-DbaRunningJob -SqlInstance $server
            $runningJobs | Should -Not -BeNullOrEmpty
            $runningJobs.Name | Should -Contain $jobName

            # Cleanup
            $null = Stop-DbaAgentJob -SqlInstance $server -Job $jobName
            $null = Remove-DbaAgentJob -SqlInstance $server -Job $jobName
        }

        It "Returns no jobs when none are running" {
            # Ensure no jobs are running
            Get-DbaRunningJob -SqlInstance $server | Stop-DbaAgentJob

            $runningJobs = Get-DbaRunningJob -SqlInstance $server
            $runningJobs | Should -BeNullOrEmpty
        }

        It "Accepts pipeline input" {
            $server | Get-DbaRunningJob | Should -Not -Throw
        }
    }
}
