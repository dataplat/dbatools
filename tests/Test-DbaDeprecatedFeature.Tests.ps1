param($ModuleName = 'dbatools')

Describe "Test-DbaDeprecatedFeature" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
        . "$PSScriptRoot\..\public\Test-DbaDeprecatedFeature.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaDeprecatedFeature
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command actually works" {
        It "Should return a result" {
            $results = Test-DbaDeprecatedFeature -SqlInstance $global:instance2
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should return a result for a database" {
            $results = Test-DbaDeprecatedFeature -SqlInstance $global:instance2 -Database Master
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
