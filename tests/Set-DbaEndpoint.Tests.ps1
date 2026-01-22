#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaEndpoint",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Endpoint",
                "Owner",
                "Type",
                "AllEndpoints",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
            # Create a test endpoint for modification
            $endpointName = "dbatoolsci_test_endpoint_$(Get-Random)"
            $endpoint = New-Object Microsoft.SqlServer.Management.Smo.Endpoint($server, $endpointName)
            $endpoint.EndpointType = [Microsoft.SqlServer.Management.Smo.EndpointType]::DatabaseMirroring
            $endpoint.ProtocolType = [Microsoft.SqlServer.Management.Smo.ProtocolType]::Tcp
            $endpoint.Protocol.Tcp.ListenerPort = 5022
            $endpoint.Create()
            $endpoint.Start()

            # Test the command
            $result = Set-DbaEndpoint -SqlInstance $TestConfig.instance1 -Endpoint $endpointName -Owner "sa" -EnableException
        }

        AfterAll {
            # Clean up test endpoint
            if ($endpoint) {
                $endpoint.Drop()
            }
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Endpoint]
        }

        It "Has standard SMO Endpoint properties" {
            $expectedProps = @(
                'Name',
                'EndpointType',
                'Owner',
                'ProtocolType',
                'EndpointState',
                'IsSystemObject'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be present on SMO Endpoint object"
            }
        }

        It "Reflects the updated Owner property" {
            $result.Owner | Should -Be "sa" -Because "the Owner should be updated to 'sa'"
        }
    }
}