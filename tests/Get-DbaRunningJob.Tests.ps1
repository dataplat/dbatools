param($ModuleName = 'dbatools')

Describe "Get-DbaRunningJob" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaRunningJob
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "InputObject",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            # Setup code for all tests in this context
            $server = Connect-DbaInstance -SqlInstance $global:instance2
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
