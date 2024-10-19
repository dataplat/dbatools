param($ModuleName = 'dbatools')

Describe "Get-DbaStartupParameter" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaStartupParameter
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "Credential",
                "Simple",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
