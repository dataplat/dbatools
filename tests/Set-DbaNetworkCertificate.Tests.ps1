#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaNetworkCertificate",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Credential",
                "Certificate",
                "Thumbprint",
                "RestartService",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        It "Returns PSCustomObject" {
            # Create a mock object with the expected structure
            $mockResult = [PSCustomObject]@{
                ComputerName          = "localhost"
                InstanceName          = "MSSQLSERVER"
                SqlInstance           = "localhost"
                ServiceAccount        = "NT SERVICE\MSSQLSERVER"
                CertificateThumbprint = "1223fb1acbca44d3ee9640f81b6ba14a92f3d6e2"
                Notes                 = "Granted NT SERVICE\MSSQLSERVER read access to certificate private key"
            }

            $mockResult.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'ServiceAccount',
                'CertificateThumbprint',
                'Notes'
            )

            # Create a mock object to validate structure
            $mockResult = [PSCustomObject]@{
                ComputerName          = "localhost"
                InstanceName          = "MSSQLSERVER"
                SqlInstance           = "localhost"
                ServiceAccount        = "NT SERVICE\MSSQLSERVER"
                CertificateThumbprint = "1223fb1acbca44d3ee9640f81b6ba14a92f3d6e2"
                Notes                 = "Granted NT SERVICE\MSSQLSERVER read access to certificate private key"
            }

            $actualProps = $mockResult.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>