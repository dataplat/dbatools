param($ModuleName = 'dbatools')

Describe "Get-DbaRunningJob" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaRunningJob
        }
        It "Should have SqlInstance as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have InputObject as a non-mandatory parameter of type Microsoft.SqlServer.Management.Smo.Agent.Job[]" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Management.Smo.Agent.Job[] -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type switch -Mandatory:$false
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
