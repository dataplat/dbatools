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

    Context "Output validation" {
        BeforeAll {
            $result = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle -Endpoint "TSQL Default TCP"
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Endpoint"
        }

        It "Has the expected default display properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            # Base properties present on all endpoints regardless of TCP listener
            $baseDefaults = @("ComputerName", "InstanceName", "SqlInstance", "ID", "Name", "EndpointState", "EndpointType", "Owner", "IsAdminEndpoint", "Fqdn", "IsSystemObject")
            foreach ($prop in $baseDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
            # TCP endpoints additionally include IPAddress and Port
            if ($result[0].Protocol.Tcp.ListenerPort) {
                $defaultProps | Should -Contain "IPAddress" -Because "TCP endpoints should show IPAddress"
                $defaultProps | Should -Contain "Port" -Because "TCP endpoints should show Port"
            }
        }
    }
}