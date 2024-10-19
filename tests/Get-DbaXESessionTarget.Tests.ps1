param($ModuleName = 'dbatools')

Describe "Get-DbaXESessionTarget" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaXESessionTarget
        }
        It "Should have SqlInstance as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Session as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Session
        }
        It "Should have Target as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Target
        }
        It "Should have InputObject as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
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
