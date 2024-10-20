param($ModuleName = 'dbatools')

Describe "Test-DbaConnection" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaConnection
        }

        $params = @(
            "SqlInstance",
            "Credential",
            "SqlCredential",
            "SkipPSRemoting",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
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
