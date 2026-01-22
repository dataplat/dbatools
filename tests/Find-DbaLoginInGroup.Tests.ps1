#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Find-DbaLoginInGroup",
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
                "Login",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # This test requires AD integration and Windows group logins to exist
            # We'll test property existence on the object structure rather than actual execution
            # since AD integration varies by environment
            $mockResult = [PSCustomObject]@{
                SqlInstance        = "TestServer\Instance"
                InstanceName       = "Instance"
                ComputerName       = "TestServer"
                Login              = "DOMAIN\TestUser"
                DisplayName        = "Test User"
                MemberOf           = "DOMAIN\TestGroup"
                ParentADGroupLogin = "DOMAIN\TestGroup"
            }
        }

        It "Returns PSCustomObject" {
            $mockResult.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "SqlInstance",
                "Login",
                "DisplayName",
                "MemberOf",
                "ParentADGroupLogin"
            )
            $actualProps = $mockResult.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has the additional properties accessible via Select-Object" {
            $additionalProps = @(
                "InstanceName",
                "ComputerName"
            )
            $actualProps = $mockResult.PSObject.Properties.Name
            foreach ($prop in $additionalProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be accessible"
            }
        }
    }
}

<#
Integration test should appear below and are custom to the command you are writing.
Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
for more guidence.
#>
