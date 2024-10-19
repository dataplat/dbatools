param($ModuleName = 'dbatools')

Describe "Enable-DbaAgHadr" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Enable-DbaAgHadr
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
        BeforeAll {
            $null = Disable-DbaAgHadr -SqlInstance $global:instance3 -Confirm:$false -Force
        }

        It "enables hadr" {
            $results = Enable-DbaAgHadr -SqlInstance $global:instance3 -Confirm:$false -Force
            $results.IsHadrEnabled | Should -Be $true
        }
    }
}
