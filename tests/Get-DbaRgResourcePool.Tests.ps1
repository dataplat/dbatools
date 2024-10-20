param($ModuleName = 'dbatools')

Describe "Get-DbaRgResourcePool" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaRgResourcePool
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "InputObject",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
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
