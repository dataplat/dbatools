param($ModuleName = 'dbatools')

Describe "Get-DbaRgResourcePool" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaRgResourcePool
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $results = Get-DbaRgResourcePool -SqlInstance $global:instance2
        }
        It "Gets Results" {
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Command actually works using -Type" {
        BeforeAll {
            $results = Get-DbaRgResourcePool -SqlInstance $global:instance2 -Type Internal
        }
        It "Gets Results" {
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
