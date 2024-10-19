param($ModuleName = 'dbatools')

Describe "Get-DbaStartupParameter" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaStartupParameter
        }
        It "Should have SqlInstance as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have Credential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have Simple as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter Simple
        }
        It "Should have EnableException as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $results = Get-DbaStartupParameter -SqlInstance $global:instance2
        }
        It "Gets Results" {
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
