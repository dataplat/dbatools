param($ModuleName = 'dbatools')

Describe "Get-DbaXESessionTarget" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaXESessionTarget
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Session",
                "Target",
                "InputObject"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Verifying command output" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
        }

        It "returns only the system_health session" {
            $results = Get-DbaXESessionTarget -SqlInstance $global:instance2 -Target package0.event_file
            foreach ($result in $results) {
                $result.Name | Should -Be 'package0.event_file'
            }
        }

        It "supports the pipeline" {
            $results = Get-DbaXESession -SqlInstance $global:instance2 -Session system_health | Get-DbaXESessionTarget -Target package0.event_file
            $results.Count | Should -BeGreaterThan 0
        }
    }
}
