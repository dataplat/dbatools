param($ModuleName = 'dbatools')

Describe "Stop-DbaEndpoint" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Stop-DbaEndpoint
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Endpoint",
                "AllEndpoints",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $endpoint = Get-DbaEndpoint -SqlInstance $server -Endpoint 'TSQL Default TCP'
            $endpoint | Start-DbaEndpoint
        }

        AfterAll {
            $endpoint | Start-DbaEndpoint
        }

        It "stops the endpoint" {
            $results = $endpoint | Stop-DbaEndpoint
            $results.EndpointState | Should -Be 'Stopped'
        }
    }
}
