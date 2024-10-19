param($ModuleName = 'dbatools')

Describe "Start-DbaEndpoint" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Start-DbaEndpoint
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
            $endpoint | Stop-DbaEndpoint
        }

        AfterAll {
            $endpoint | Start-DbaEndpoint
        }

        It "starts the endpoint" {
            $results = $endpoint | Start-DbaEndpoint
            $results.EndpointState | Should -Be 'Started'
        }
    }
}
