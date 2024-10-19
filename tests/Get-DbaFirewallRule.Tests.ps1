param($ModuleName = 'dbatools')

Describe "Get-DbaFirewallRule" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaFirewallRule
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "Credential",
                "Type",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" {
        BeforeAll {
            # Add any necessary setup code here
        }

        It "Should do something" {
            # Add actual tests here
            $true | Should -Be $true
        }
    }
}

# The command will be tested together with New-DbaFirewallRule
