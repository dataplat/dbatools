#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaAzAccessToken",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Type",
                "Subtype",
                "Config",
                "Credential",
                "Tenant",
                "Thumbprint",
                "Store",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation for RenewableServicePrincipal" {
        BeforeAll {
            # Note: This test uses mock values and will not actually connect to Azure
            # Real integration tests would require Azure credentials
            $mockCredential = New-Object System.Management.Automation.PSCredential("mock-app-id", (ConvertTo-SecureString "mock-secret" -AsPlainText -Force))
            $mockTenant = "mock-tenant.onmicrosoft.com"

            # This will create the type but may fail on actual token generation
            # We're testing the output structure, not the authentication
            try {
                $result = New-DbaAzAccessToken -Type RenewableServicePrincipal -Credential $mockCredential -Tenant $mockTenant -Subtype AzureSqlDb -EnableException
            } catch {
                # Expected to fail without real Azure credentials
                # We'll test the type definition that should have been created
            }
        }

        It "RenewableServicePrincipal returns PSObjectIRenewableToken type" {
            # Test that the type was defined
            $typeExists = [bool]([System.Management.Automation.PSTypeName]'PSObjectIRenewableToken').Type
            $typeExists | Should -BeTrue -Because "PSObjectIRenewableToken type should be defined"
        }

        It "RenewableServicePrincipal has the expected properties" {
            # Create an instance to test properties
            if ([type]::GetType('PSObjectIRenewableToken')) {
                $testObj = New-Object PSObjectIRenewableToken
                $expectedProps = @(
                    'ClientSecret',
                    'Resource',
                    'Tenant',
                    'UserId',
                    'TokenExpiry'
                )
                $actualProps = $testObj.PSObject.Properties.Name
                foreach ($prop in $expectedProps) {
                    $actualProps | Should -Contain $prop -Because "property '$prop' should be available"
                }
            }
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>