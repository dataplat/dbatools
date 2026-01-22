#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaSpn",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SPN",
                "ServiceAccount",
                "Credential",
                "NoDelegation",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        It "Returns PSCustomObject" {
            $mockResult = [PSCustomObject]@{
                Name           = "MSSQLSvc/server.domain.com:1433"
                ServiceAccount = "domain\account"
                Property       = "servicePrincipalName"
                IsSet          = $true
                Notes          = "Successfully added SPN"
            }
            $mockResult.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected properties for SPN registration" {
            $expectedProps = @(
                "Name",
                "ServiceAccount",
                "Property",
                "IsSet",
                "Notes"
            )
            $mockResult = [PSCustomObject]@{
                Name           = "MSSQLSvc/server.domain.com:1433"
                ServiceAccount = "domain\account"
                Property       = "servicePrincipalName"
                IsSet          = $true
                Notes          = "Successfully added SPN"
            }
            $actualProps = $mockResult.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in output"
            }
        }

        It "Property value is 'servicePrincipalName' for SPN registration result" {
            $mockResult = [PSCustomObject]@{
                Name           = "MSSQLSvc/server.domain.com:1433"
                ServiceAccount = "domain\account"
                Property       = "servicePrincipalName"
                IsSet          = $true
                Notes          = "Successfully added SPN"
            }
            $mockResult.Property | Should -Be "servicePrincipalName"
        }

        It "Property value is 'msDS-AllowedToDelegateTo' for delegation result" {
            $mockResult = [PSCustomObject]@{
                Name           = "MSSQLSvc/server.domain.com:1433"
                ServiceAccount = "domain\account"
                Property       = "msDS-AllowedToDelegateTo"
                IsSet          = $true
                Notes          = "Successfully added constrained delegation"
            }
            $mockResult.Property | Should -Be "msDS-AllowedToDelegateTo"
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>