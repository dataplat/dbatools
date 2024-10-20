param($ModuleName = 'dbatools')

Describe "Get-DbaHideInstance" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaHideInstance
        }

        $params = @(
            "SqlInstance",
            "Credential",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
        BeforeAll {
            $results = Get-DbaHideInstance -SqlInstance $global:instance1 -EnableException
        }

        It "returns true or false" {
            $results.HideInstance | Should -Not -BeNullOrEmpty
        }
    }
}
