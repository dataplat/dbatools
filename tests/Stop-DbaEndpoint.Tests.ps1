param($ModuleName = 'dbatools')

Describe "Stop-DbaEndpoint" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Stop-DbaEndpoint
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Endpoint as a parameter" {
            $CommandUnderTest | Should -HaveParameter Endpoint
        }
        It "Should have AllEndpoints as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter AllEndpoints
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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
