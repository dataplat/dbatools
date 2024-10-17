param($ModuleName = 'dbatools')

Describe "Test-DbaConnection" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaConnection
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have Credential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential -Not -Mandatory
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have SkipPSRemoting as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter SkipPSRemoting -Type switch -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type switch -Not -Mandatory
        }
    }

    Context "Testing if command works" {
        BeforeAll {
            $results = Test-DbaConnection -SqlInstance $global:instance1
            $whoami = whoami
        }

        It "returns the correct port" {
            $results.TcpPort | Should -Be 1433
        }

        It "returns the correct authtype" {
            $results.AuthType | Should -Be 'Windows Authentication'
        }

        It "returns the correct user" {
            $results.ConnectingAsUser | Should -Be $whoami
        }
    }
}
