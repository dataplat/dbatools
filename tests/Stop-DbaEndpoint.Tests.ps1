param($ModuleName = 'dbatools')

Describe "Stop-DbaEndpoint" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Stop-DbaEndpoint
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Endpoint as a parameter" {
            $CommandUnderTest | Should -HaveParameter Endpoint -Type String[]
        }
        It "Should have AllEndpoints as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter AllEndpoints -Type SwitchParameter
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Endpoint[]
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $endpoint = Get-DbaEndpoint -SqlInstance $server -Endpoint 'TSQL Default TCP'
            $endpoint | Start-DbaEndpoint
        }

        AfterAll {
            $endpoint | Start-DbaEndpoint
        }

        It "stops the endpoint" {
            $results = $endpoint | Stop-DbaEndpoint -Confirm:$false
            $results.EndpointState | Should -Be 'Stopped'
        }
    }
}
