param($ModuleName = 'dbatools')

Describe "Test-DbaEndpoint" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaEndpoint
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Endpoint",
            "InputObject",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        It "Returns success" -Skip {
            $results = Test-DbaEndpoint -SqlInstance $global:instance3
            $results | Select-Object -First 1 -ExpandProperty Connection | Should -Be 'Success'
        }
    }
}
