param($ModuleName = 'dbatools')

Describe "Test-DbaConnection" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaConnection
        }
        It "Should have SqlInstance as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have Credential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have SqlCredential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have SkipPSRemoting as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter SkipPSRemoting
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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
