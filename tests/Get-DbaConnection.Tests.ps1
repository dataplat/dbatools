param($ModuleName = 'dbatools')

Describe "Get-DbaConnection" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaConnection
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $results = Get-DbaConnection -SqlInstance $global:instance1
        }

        It "Returns the proper authentication scheme" {
            foreach ($result in $results) {
                $result.AuthScheme | Should -BeIn @('ntlm', 'Kerberos')
            }
        }
    }
}
