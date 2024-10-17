param($ModuleName = 'dbatools')

Describe "Get-DbaXESessionTarget" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaXESessionTarget
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Session as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Session -Type String[] -Not -Mandatory
        }
        It "Should have Target as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Target -Type String[] -Not -Mandatory
        }
        It "Should have InputObject as a non-mandatory parameter of type Session[]" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Session[] -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type switch -Not -Mandatory
        }
    }

    Context "Verifying command output" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
        }

        It "returns only the system_health session" {
            $results = Get-DbaXESessionTarget -SqlInstance $script:instance2 -Target package0.event_file
            foreach ($result in $results) {
                $result.Name | Should -Be 'package0.event_file'
            }
        }

        It "supports the pipeline" {
            $results = Get-DbaXESession -SqlInstance $script:instance2 -Session system_health | Get-DbaXESessionTarget -Target package0.event_file
            $results.Count | Should -BeGreaterThan 0
        }
    }
}
