param($ModuleName = 'dbatools')

Describe "Set-DbaAgListener" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaAgListener
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "AvailabilityGroup",
            "Listener",
            "Port",
            "InputObject",
            "EnableException",
            "WhatIf",
            "Confirm"
        )

        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}
