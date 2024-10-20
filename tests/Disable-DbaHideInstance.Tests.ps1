param($ModuleName = 'dbatools')

Describe "Disable-DbaHideInstance" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Disable-DbaHideInstance
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

    Context "Integration Tests" {
        BeforeAll {
            $results = Disable-DbaHideInstance -SqlInstance $global:instance1 -EnableException
        }

        It "Returns false for HideInstance" {
            $results.HideInstance | Should -Be $false
        }
    }
}
