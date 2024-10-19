param($ModuleName = 'dbatools')

Describe "Disable-DbaHideInstance" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Disable-DbaHideInstance
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

    Context "Integration Tests" {
        BeforeAll {
            $results = Disable-DbaHideInstance -SqlInstance $global:instance1 -EnableException
        }

        It "Returns false for HideInstance" {
            $results.HideInstance | Should -Be $false
        }
    }
}
