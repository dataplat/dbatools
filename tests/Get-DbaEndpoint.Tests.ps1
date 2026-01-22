#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaEndpoint",
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
                "Type",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When connecting to SQL Server" {
        It "gets some endpoints" {
            $results = @(Get-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle)
            $results.Count | Should -BeGreaterThan 1
            $results.Name | Should -Contain "TSQL Default TCP"
        }

        It "gets one endpoint" {
            $results = @(Get-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle -Endpoint "TSQL Default TCP")
            $results.Name | Should -Be "TSQL Default TCP"
            $results.Count | Should -Be 1
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle -EnableException
        }

        It "Returns the documented output type" {
            $result[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Endpoint]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'ID',
                'Name',
                'EndpointState',
                'EndpointType',
                'Owner',
                'IsAdminEndpoint',
                'Fqdn',
                'IsSystemObject'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Includes custom-added IPAddress and Port properties" {
            $actualProps = $result[0].PSObject.Properties.Name
            $actualProps | Should -Contain 'IPAddress' -Because "IPAddress is added by dbatools"
            $actualProps | Should -Contain 'Port' -Because "Port is added by dbatools"
        }

        It "Has TCP endpoints with IPAddress and Port populated" {
            $tcpEndpoint = $result | Where-Object { $null -ne $_.Port }
            $tcpEndpoint | Should -Not -BeNullOrEmpty -Because "at least one endpoint should have TCP configured"
            $tcpEndpoint[0].IPAddress | Should -Not -BeNullOrEmpty
            $tcpEndpoint[0].Port | Should -BeGreaterThan 0
        }

        It "Has Fqdn in correct format for TCP endpoints" {
            $tcpEndpoint = $result | Where-Object { $null -ne $_.Port }
            $tcpEndpoint | Should -Not -BeNullOrEmpty
            $tcpEndpoint[0].Fqdn | Should -Match '^TCP://.+:\d+$' -Because "Fqdn should be in TCP://hostname:port format"
        }
    }
}