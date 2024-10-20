param($ModuleName = 'dbatools')

Describe "Get-DbaInstanceUserOption" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaInstanceUserOption
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

    Context "Gets UserOptions for the Instance" {
        BeforeAll {
            $results = Get-DbaInstanceUserOption -SqlInstance $global:instance2 | Where-Object {$_.name -eq 'AnsiNullDefaultOff'}
        }
        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should return AnsiNullDefaultOff UserOption" {
            $results.Name | Should -Be 'AnsiNullDefaultOff'
        }
        It "Should be set to false" {
            $results.Value | Should -BeFalse
        }
    }
}
