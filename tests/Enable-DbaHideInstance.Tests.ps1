param($ModuleName = 'dbatools')

Describe "Enable-DbaHideInstance" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Enable-DbaHideInstance
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "Credential",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
