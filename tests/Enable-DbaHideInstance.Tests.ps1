param($ModuleName = 'dbatools')

Describe "Enable-DbaHideInstance" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Enable-DbaHideInstance
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

    Context "Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            $instance = $global:instance1
        }

        AfterAll {
            $null = Disable-DbaHideInstance -SqlInstance $instance
        }

        It "Enables Hide Instance" {
            $results = Enable-DbaHideInstance -SqlInstance $instance -EnableException
            $results.HideInstance | Should -Be $true
        }
    }
}
