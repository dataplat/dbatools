param($ModuleName = 'dbatools')

Describe "Stop-DbaAgentJob" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Stop-DbaAgentJob
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Job as a parameter" {
            $CommandUnderTest | Should -HaveParameter Job
        }
        It "Should have ExcludeJob as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeJob
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have Wait as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Wait
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command execution" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        It "Returns a CurrentRunStatus of Idle" -Skip:($null -ne [Environment]::GetEnvironmentVariable('appveyor')) {
            BeforeAll {
                $jobName = 'DatabaseBackup - SYSTEM_DATABASES - FULL'
                $server = Connect-DbaInstance -SqlInstance $global:instance2
                $job = Get-DbaAgentJob -SqlInstance $server -Job $jobName
            }

            $job | Start-DbaAgentJob
            $results = $job | Stop-DbaAgentJob
            $results.CurrentRunStatus | Should -Be 'Idle'
        }
    }
}
