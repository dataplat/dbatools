#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaNetworkCertificate",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
    }

    AfterAll {
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Output Validation" {
        BeforeAll {
            # Only test if instance actually has a certificate configured
            $result = Get-DbaNetworkCertificate -SqlInstance $TestConfig.instance1 -EnableException
        }

        It "Returns PSCustomObject" {
            if ($result) {
                $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
            } else {
                Set-ItResult -Skipped -Because "No certificate configured on test instance"
            }
        }

        It "Has the expected default properties" {
            if ($result) {
                $expectedProps = @(
                    'ComputerName',
                    'InstanceName',
                    'SqlInstance',
                    'VSName',
                    'ServiceAccount',
                    'ForceEncryption',
                    'FriendlyName',
                    'DnsNameList',
                    'Thumbprint',
                    'Generated',
                    'Expires',
                    'IssuedTo',
                    'IssuedBy',
                    'Certificate'
                )
                $actualProps = $result.PSObject.Properties.Name
                foreach ($prop in $expectedProps) {
                    $actualProps | Should -Contain $prop -Because "property '$prop' should be present in output"
                }
            } else {
                Set-ItResult -Skipped -Because "No certificate configured on test instance"
            }
        }

        It "Returns only instances with certificates (Thumbprint not empty)" {
            if ($result) {
                $result.Thumbprint | Should -Not -BeNullOrEmpty
            } else {
                Set-ItResult -Skipped -Because "No certificate configured on test instance"
            }
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>