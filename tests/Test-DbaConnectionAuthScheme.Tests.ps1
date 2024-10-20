param($ModuleName = 'dbatools')

Describe "Test-DbaConnectionAuthScheme" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaConnectionAuthScheme
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Kerberos",
            "Ntlm",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "returns the proper transport" {
        BeforeAll {
            $results = Test-DbaConnectionAuthScheme -SqlInstance $global:instance1
        }
        It "returns ntlm auth scheme" {
            $results.AuthScheme | Should -Be 'ntlm'
        }
    }
}
