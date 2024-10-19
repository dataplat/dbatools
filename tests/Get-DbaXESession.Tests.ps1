param($ModuleName = 'dbatools')

Describe "Get-DbaXESession" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaXESession
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
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Verifying command output" {
        It "returns some results" {
            $results = Get-DbaXESession -SqlInstance $global:instance2
            $results.Count | Should -BeGreaterThan 1
        }

        It "returns only the system_health session" {
            $results = Get-DbaXESession -SqlInstance $global:instance2 -Session system_health
            $results.Name | Should -Be 'system_health'
        }
    }
}
