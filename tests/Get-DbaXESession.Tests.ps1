param($ModuleName = 'dbatools')

Describe "Get-DbaXESession" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaXESession
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Session as a non-mandatory parameter of type Object[]" {
            $CommandUnderTest | Should -HaveParameter Session -Type Object[] -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
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
