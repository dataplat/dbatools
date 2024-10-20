param($ModuleName = 'dbatools')

Describe "Stop-DbaAgentJob" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Stop-DbaAgentJob
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Job",
            "ExcludeJob",
            "InputObject"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
        $CommandUnderTest | Should -HaveParameter Wait
        $CommandUnderTest | Should -HaveParameter EnableException
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
