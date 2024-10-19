param($ModuleName = 'dbatools')

Describe "Get-DbaDeprecatedFeature" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDeprecatedFeature
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
