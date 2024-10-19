param($ModuleName = 'dbatools')

Describe "Disable-DbaAgHadr" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Disable-DbaAgHadr
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "Credential",
                "Force",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Integration Tests" -Tag "IntegrationTests" {
        AfterAll {
            Enable-DbaAgHadr -SqlInstance $global:instance3 -Confirm:$false -Force
        }

        It "disables hadr" {
            $results = Disable-DbaAgHadr -SqlInstance $global:instance3 -Confirm:$false -Force
            $results.IsHadrEnabled | Should -Be $false
        }
    }
}
