param($ModuleName = 'dbatools')

Describe "Get-DbaHideInstance" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaHideInstance
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

    Context "Command usage" {
        BeforeAll {
            $results = Get-DbaHideInstance -SqlInstance $global:instance1 -EnableException
        }

        It "returns true or false" {
            $results.HideInstance | Should -Not -BeNullOrEmpty
        }
    }
}
