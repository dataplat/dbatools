#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaClientProtocol",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip:(-not $env:appveyor) {
    # Skip on local tests as we don't get any results on SQL Server 2022

    Context "Get some client protocols" {
        It "Should return some protocols" {
            $results = @(Get-DbaClientProtocol)
            $results.Status.Count | Should -BeGreaterThan 1
            $results | Where-Object ProtocolDisplayName -eq "TCP/IP" | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaClientProtocol -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].PSObject.TypeNames | Should -Contain 'Microsoft.Management.Infrastructure.CimInstance#root/Microsoft/SQLServer/ComputerManagement'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'DisplayName',
                'DLL',
                'Order',
                'IsEnabled'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has the IsEnabled property added by dbatools" {
            $result[0].PSObject.Properties.Name | Should -Contain 'IsEnabled'
            $result[0].IsEnabled | Should -BeOfType [System.Boolean]
        }

        It "Has the Enable method added by dbatools" {
            $result[0].PSObject.Methods.Name | Should -Contain 'Enable'
        }

        It "Has the Disable method added by dbatools" {
            $result[0].PSObject.Methods.Name | Should -Contain 'Disable'
        }
    }
}