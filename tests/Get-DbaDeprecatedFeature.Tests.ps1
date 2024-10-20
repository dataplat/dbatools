param($ModuleName = 'dbatools')

Describe "Get-DbaDeprecatedFeature" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDeprecatedFeature
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

    Context "Gets Deprecated Features" {
        BeforeAll {
            $results = Get-DbaDeprecatedFeature -SqlInstance $global:instance1
        }
        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
