param($ModuleName = 'dbatools')

Describe "Get-DbaFirewallRule" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaFirewallRule
        }

        $params = @(
            "SqlInstance",
            "Credential",
            "Type",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
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
