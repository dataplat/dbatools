param($ModuleName = 'dbatools')

Describe "Test-DbaAgSpn" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaAgSpn
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Credential",
            "AvailabilityGroup",
            "Listener",
            "InputObject",
            "EnableException"
        )

        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    # Add more contexts and tests as needed for the specific functionality of Test-DbaAgSpn
}
